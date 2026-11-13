#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$BlockSMB,
    [switch]$BlockNetBIOS,
    [switch]$BlockRDP,
    [switch]$BlockWinRM,
    [switch]$BlockFTP,
    [switch]$BlockTelnet
)

$ErrorActionPreference = 'Stop'
$profiles = @('Domain', 'Private', 'Public')

# Save a restorable backup before making changes.
$backupDir = Join-Path $env:USERPROFILE 'Desktop'
if (-not (Test-Path -LiteralPath $backupDir)) {
    $backupDir = [Environment]::GetFolderPath('MyDocuments')
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $backupDir "firewall-backup-$timestamp.wfw"

Write-Host 'Current firewall configuration:'
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogBlocked | Format-Table -AutoSize

if ($WhatIfPreference) {
    Write-Host 'WhatIf: backup and configuration changes would be performed. No changes made.'
    return
}

& netsh.exe advfirewall export $backup | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
    throw 'Firewall backup failed. No changes applied.'
}
Write-Host "Backup saved to: $backup"

if (-not $PSCmdlet.ShouldProcess('Windows Firewall', 'Enable profiles, set defaults, configure logging and selected block rules')) {
    Write-Host 'No firewall changes made.'
    return
}

Set-NetFirewallProfile -Profile $profiles -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow

# Optional explicit inbound blocks. Only enable these after verifying CCDC service requirements.
$rules = @(
    @{Name='SMB'; Protocol='TCP'; Ports='445'; Selected=$BlockSMB.IsPresent},
    @{Name='NetBIOS TCP'; Protocol='TCP'; Ports='139'; Selected=$BlockNetBIOS.IsPresent},
    @{Name='NetBIOS UDP'; Protocol='UDP'; Ports='137-138'; Selected=$BlockNetBIOS.IsPresent},
    @{Name='RDP TCP'; Protocol='TCP'; Ports='3389'; Selected=$BlockRDP.IsPresent},
    @{Name='RDP UDP'; Protocol='UDP'; Ports='3389'; Selected=$BlockRDP.IsPresent},
    @{Name='Telnet'; Protocol='TCP'; Ports='23'; Selected=$BlockTelnet.IsPresent},
    @{Name='FTP'; Protocol='TCP'; Ports='21'; Selected=$BlockFTP.IsPresent},
    @{Name='WinRM'; Protocol='TCP'; Ports='5985-5986'; Selected=$BlockWinRM.IsPresent}
)

foreach ($rule in $rules) {
    if (-not $rule.Selected) { continue }
    $displayName = "Hardening - Block Inbound $($rule.Name)"
    if (-not (Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $displayName `
            -Direction Inbound -Action Block `
            -Protocol $rule.Protocol -LocalPort $rule.Ports `
            -Profile Any -Enabled True | Out-Null
        Write-Host "Created: $displayName"
    } else {
        Write-Host "Already exists: $displayName"
    }
}

Set-NetFirewallProfile -Profile $profiles -LogBlocked True -LogMaxSizeKilobytes 16384

Write-Host "`nFinal firewall configuration:"
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogBlocked | Format-Table -AutoSize
Write-Host "`nFirewall hardening completed."
Write-Host "Backup saved to: $backup"
Write-Host 'Rollback (Administrator, only if needed): netsh advfirewall import "<backup-path>"'
Write-Warning 'Verify required CCDC services, remote access, and scoring immediately after changes.'
