<#
.SYNOPSIS
  Inject SA103 - SNMPv2c, read-only, on the MSSQL Server 2019 VM.

.DESCRIPTION
  1. Installs the Windows SNMP Service feature (if missing).
  2. Configures ONE read-only community string (you type it; existing communities such as 'public' are removed).
  3. Accepts SNMP packets from any host (default) or only from -AllowedManagers.
  4. Opens inbound UDP 161 in Windows Firewall (rule CCDC-SNMP-161).
  5. Turns off authentication traps and removes the LAN Manager MIB extension (it would otherwise expose
     local user account names and share names to anyone who knows the community string).
  6. Restarts the service, tests it locally, and prints the three facts the inject memo needs:
     external IP, community string, host name.

  SNMPv2c is unencrypted: the community string crosses the network in clear text and is effectively a
  shared password. Choose a non-default string, and do not reuse any account password.

.EXAMPLE
  .\Enable-SNMP.ps1 -TeamNumber 1
  .\Enable-SNMP.ps1 -TeamNumber 1 -AllowedManagers 172.31.21.50
  .\Enable-SNMP.ps1 -Remove
#>
[CmdletBinding()]
param(
    [int]$TeamNumber,                      # used only to compute the external ("public") IP for the memo
    [string]$Community,                    # optional; if omitted you are prompted (hidden, entered twice)
    [string[]]$AllowedManagers = @(),      # optional monitoring-provider IPs; empty = accept from any host
    [string]$Contact  = 'IT Operations',
    [string]$Location = 'Data Center',
    [switch]$KeepLanManMib,                # keep the LAN Manager MIB (exposes usernames/shares) - not recommended
    [switch]$Remove,                       # stop/disable SNMP and delete the firewall rule
    [string]$OutDir = 'C:\ccdc'
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Warning 'Run this from an elevated (Administrator) PowerShell window.'; return }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$RuleName = 'CCDC-SNMP-161'
$Base     = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters'
$Valid    = "$Base\ValidCommunities"
$Perm     = "$Base\PermittedManagers"
$Agent    = "$Base\RFC1156Agent"
$Ext      = "$Base\ExtensionAgents"

function Convert-SecureToPlain([System.Security.SecureString]$Secure) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Clear-RegValues([string]$Path) {
    if (Test-Path $Path) {
        foreach ($n in @((Get-Item $Path).Property)) { Remove-ItemProperty -Path $Path -Name $n -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------- remove mode
if ($Remove) {
    Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    if (Get-Service SNMP -ErrorAction SilentlyContinue) {
        Stop-Service SNMP -Force -ErrorAction SilentlyContinue
        Set-Service SNMP -StartupType Disabled
    }
    Write-Host '[+] SNMP service stopped and disabled; firewall rule removed.' -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------- community string
if (-not $Community) {
    $s1 = Read-Host 'Read-only community string (hidden)' -AsSecureString
    $s2 = Read-Host 'Confirm community string' -AsSecureString
    $c1 = Convert-SecureToPlain $s1
    if ($c1 -cne (Convert-SecureToPlain $s2)) { Write-Warning 'Entries did not match. Nothing changed.'; return }
    $Community = $c1
}
if ([string]::IsNullOrWhiteSpace($Community) -or $Community -match '\s') {
    Write-Warning 'Community string must be non-empty and contain no spaces. Nothing changed.'; return
}
if ($Community -in 'public', 'private') {
    Write-Warning "'$Community' is the well-known default and is trivially guessed. Continuing, but consider a different string unless the White Team requires it."
}

# ---------------------------------------------------------------- install feature
if (-not (Get-WindowsFeature -Name SNMP-Service).Installed) {
    Write-Host '[*] Installing SNMP Service feature...' -ForegroundColor Cyan
    $r = Install-WindowsFeature -Name SNMP-Service -IncludeManagementTools
    if (-not $r.Success) { Write-Warning 'Feature install failed (may need the Windows component store or internet). Nothing else changed.'; return }
    if ($r.RestartNeeded -ne 'No') { Write-Warning "Install reports RestartNeeded=$($r.RestartNeeded). Plan a reboot when scoring allows." }
}
if (-not (Test-Path $Valid)) { Write-Warning 'SNMP registry keys not found. Is the feature installed correctly?'; return }

reg export 'HKLM\SYSTEM\CurrentControlSet\Services\SNMP' (Join-Path $OutDir 'snmp-reg-backup.reg') /y | Out-Null
Write-Host "[+] Registry backup: $OutDir\snmp-reg-backup.reg"

# ---------------------------------------------------------------- configure agent
$old = @((Get-Item $Valid).Property)
if ($old.Count) { Write-Host "[*] Removing existing communities: $($old -join ', ')" -ForegroundColor Cyan }
Clear-RegValues $Valid
New-ItemProperty -Path $Valid -Name $Community -Value 4 -PropertyType DWord -Force | Out-Null   # 4 = READ ONLY
Write-Host '[+] Read-only community configured (rights = 4).'

if (-not (Test-Path $Perm)) { New-Item -Path $Perm -Force | Out-Null }
Clear-RegValues $Perm
if ($AllowedManagers.Count -gt 0) {
    $i = 1
    foreach ($m in $AllowedManagers) { New-ItemProperty -Path $Perm -Name "$i" -Value $m -PropertyType String -Force | Out-Null; $i++ }
    Write-Host "[+] Accepting SNMP only from: $($AllowedManagers -join ', ')"
} else {
    Write-Host '[+] Accepting SNMP packets from any host (no permitted-manager list).'
}

if (-not (Test-Path $Agent)) { New-Item -Path $Agent -Force | Out-Null }
New-ItemProperty -Path $Agent -Name 'sysContact'  -Value $Contact  -PropertyType String -Force | Out-Null
New-ItemProperty -Path $Agent -Name 'sysLocation' -Value $Location -PropertyType String -Force | Out-Null
New-ItemProperty -Path $Base  -Name 'EnableAuthenticationTraps' -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host '[+] sysContact/sysLocation set; authentication traps off.'

# ---------------------------------------------------------------- hide the LAN Manager MIB (usernames/shares)
if (-not $KeepLanManMib -and (Test-Path $Ext)) {
    $entries = @((Get-Item $Ext).Property | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ } | ForEach-Object {
        [pscustomobject]@{ Name = $_; Value = (Get-ItemProperty -Path $Ext -Name $_).$_ }
    })
    $keep = @($entries | Where-Object { $_.Value -notmatch 'LANManagerMIB2' })
    if ($keep.Count -lt $entries.Count) {
        foreach ($e in $entries) { Remove-ItemProperty -Path $Ext -Name $e.Name -ErrorAction SilentlyContinue }
        $i = 1
        foreach ($e in $keep) { New-ItemProperty -Path $Ext -Name "$i" -Value $e.Value -PropertyType String -Force | Out-Null; $i++ }
        Write-Host '[+] LAN Manager MIB extension removed (no user/share enumeration over SNMP).' -ForegroundColor Green
    } else {
        Write-Host '[*] LAN Manager MIB extension not present; nothing to remove.'
    }
}

# ---------------------------------------------------------------- firewall
Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
$fw = @{ DisplayName = $RuleName; Direction = 'Inbound'; Protocol = 'UDP'; LocalPort = 161; Action = 'Allow'; Profile = 'Any' }
if ($AllowedManagers.Count -gt 0) { $fw.RemoteAddress = $AllowedManagers }
New-NetFirewallRule @fw | Out-Null
Write-Host "[+] Firewall rule $RuleName created (inbound UDP 161). Replies are allowed automatically (stateful)."

# ---------------------------------------------------------------- start service + test
Set-Service SNMP -StartupType Automatic
Restart-Service SNMP -Force
Start-Sleep -Seconds 3
$svc = Get-Service SNMP
Write-Host ("[{0}] SNMP service: {1}" -f $(if ($svc.Status -eq 'Running') { '+' } else { '!' }), $svc.Status) -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })
if (Get-NetUDPEndpoint -LocalPort 161 -ErrorAction SilentlyContinue) { Write-Host '[+] Listening on UDP 161.' -ForegroundColor Green }
else { Write-Warning 'Nothing is listening on UDP 161 yet.' }

try {
    $snmp = New-Object -ComObject olePrn.OleSNMP
    $snmp.Open('127.0.0.1', $Community, 2, 3000)
    $sysName = $snmp.Get('.1.3.6.1.2.1.1.5.0')
    $snmp.Close()
    Write-Host "[+] Local SNMP query succeeded (sysName = $sysName)." -ForegroundColor Green
} catch {
    Write-Warning "Local SNMP test failed: $($_.Exception.Message). Test from another machine instead (see notes)."
}

# ---------------------------------------------------------------- facts for the memo
$hostName = $env:COMPUTERNAME
$extIp = if ($TeamNumber -gt 0) { "172.25.$(20 + $TeamNumber).120" } else { '172.25.<20+team#>.120' }
Write-Host "`n===== Facts for the SA103 memo =====" -ForegroundColor Cyan
Write-Host "Device:            MSSQL Server (Windows Server 2019)"
Write-Host "Host name:         $hostName"
Write-Host "External IP:       $extIp   (per rulebook VM table: 172.25.20+team#.120)"
Write-Host "Community string:  $Community   (read-only, SNMPv2c)"
Write-Host "Internal IP:       172.20.240.120"
Write-Host "`nTest from another machine (e.g. Kali):  snmpget -v2c -c <community> $extIp 1.3.6.1.2.1.1.5.0" -ForegroundColor Yellow
Write-Host "The Palo Alto / VyOS teammates must permit and NAT UDP 161 to $extIp." -ForegroundColor Yellow
