#!/bin/bash
# harden.sh - makes CHANGES. Edit config.sh first!
# Usage: ./harden.sh            -> asks before each section
#        ./harden.sh -y         -> runs everything without asking
#        ./harden.sh --dry-run  -> only shows what it would do
source "$(dirname "$0")/lib.sh"
need_root

AUTO=0; DRY=0
case "$1" in -y) AUTO=1;; --dry-run) DRY=1;; esac

start_log harden

ask() {  # ask "question" -> returns 0 for yes
  [[ $DRY -eq 1 ]] && { echo "${YEL}[DRY-RUN]${RST} would: $1"; return 1; }
  [[ $AUTO -eq 1 ]] && return 0
  read -rp "${BLU}?${RST} $1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]
}

# Always back up first
if [[ $DRY -eq 0 ]]; then
  hdr "BACKUP FIRST"
  "$SCRIPT_DIR/backup.sh" >/dev/null && ok "Backup done ($BACKUP_DIR)"
fi

# ---------- FIREWALL ----------
hdr "FIREWALL"
echo "Will allow ONLY: services [$SCORED_SERVICES] ports [$EXTRA_PORTS]"
echo "Currently allowed: $(firewall-cmd --list-services 2>/dev/null) $(firewall-cmd --list-ports 2>/dev/null)"
if ask "Reset firewall to only scored services?"; then
  systemctl enable --now firewalld
  for s in $(firewall-cmd --permanent --list-services); do
    [[ " $SCORED_SERVICES " == *" $s "* ]] || { firewall-cmd --permanent --remove-service="$s" >/dev/null; warn "removed $s"; }
  done
  for p in $(firewall-cmd --permanent --list-ports); do
    [[ " $EXTRA_PORTS " == *" $p "* ]] || { firewall-cmd --permanent --remove-port="$p" >/dev/null; warn "removed $p"; }
  done
  for s in $SCORED_SERVICES; do firewall-cmd --permanent --add-service="$s" >/dev/null; done
  for p in $EXTRA_PORTS;   do firewall-cmd --permanent --add-port="$p" >/dev/null; done
  firewall-cmd --reload >/dev/null && ok "Firewall now: $(firewall-cmd --list-services) $(firewall-cmd --list-ports)"
fi

# ---------- SSH ----------
hdr "SSH"
SSH_DROPIN=/etc/ssh/sshd_config.d/00-ccdc.conf   # 00- so it wins (first match applies)
if ask "Apply SSH hardening (PermitRootLogin=$SSH_PERMIT_ROOT, AllowUsers='$SSH_ALLOW_USERS')?"; then
  if [[ "$SSH_PERMIT_ROOT" == "no" ]] && [[ -z "$(getent group wheel | cut -d: -f4)" ]]; then
    bad "No users in wheel group! Disabling root SSH could lock you out. Skipping SSH."
  else
    cat > "$SSH_DROPIN" <<EOF
# Added by harden.sh $TS
PermitRootLogin $SSH_PERMIT_ROOT
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    [[ -n "$SSH_ALLOW_USERS" ]] && echo "AllowUsers $SSH_ALLOW_USERS" >> "$SSH_DROPIN"
    if sshd -t; then
      systemctl reload sshd && ok "sshd reloaded. KEEP THIS SESSION OPEN and test a new login!"
    else
      bad "sshd config test FAILED, reverting"; rm -f "$SSH_DROPIN"
    fi
  fi
fi

# ---------- SELINUX ----------
hdr "SELINUX (currently: $(getenforce))"
if [[ "$(getenforce)" != "Enforcing" ]] && ask "Set SELinux to enforcing?"; then
  if [[ "$(getenforce)" == "Disabled" ]]; then
    warn "SELinux is Disabled; needs config change + relabel + reboot. Setting config only."
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config; touch /.autorelabel
  else
    setenforce 1; sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    ok "Enforcing. If a service breaks: ausearch -m avc -ts recent"
  fi
fi

# ---------- UNNEEDED SERVICES ----------
hdr "UNNEEDED SERVICES"
for s in $DISABLE_SERVICES; do
  [[ " $KEEP_RUNNING " == *" ${s%.*} "* ]] && continue
  if systemctl is-enabled --quiet "$s" 2>/dev/null || systemctl is-active --quiet "$s" 2>/dev/null; then
    ask "Disable $s?" && { systemctl disable --now "$s" 2>/dev/null; ok "disabled $s"; }
  fi
done

# ---------- AUDITD ----------
hdr "AUDIT LOGGING"
if ask "Enable auditd with watches on passwd/shadow/sudoers/ssh?"; then
  systemctl enable --now auditd 2>/dev/null
  cat > /etc/audit/rules.d/ccdc.rules <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd
-w /root/.ssh/ -p wa -k rootssh
-w /etc/crontab -p wa -k cron
-w /var/spool/cron/ -p wa -k cron
EOF
  augenrules --load >/dev/null 2>&1 && ok "Audit rules loaded. Search with: ausearch -k identity"
fi

# ---------- SYSCTL ----------
hdr "KERNEL NETWORK SETTINGS"
if ask "Apply safe sysctl hardening?"; then
  cat > /etc/sysctl.d/99-ccdc.conf <<'EOF'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.dmesg_restrict = 1
EOF
  sysctl --system >/dev/null && ok "sysctl applied"
fi

# ---------- VERIFY ----------
hdr "VERIFY SCORED SERVICES STILL RUNNING"
for s in $KEEP_RUNNING; do
  if systemctl is-active --quiet "$s"; then ok "$s running"
  elif systemctl list-unit-files "$s.service" >/dev/null 2>&1 && systemctl cat "$s" >/dev/null 2>&1; then
    bad "$s is NOT running!  ->  systemctl status $s"
  else warn "$s not installed (remove from KEEP_RUNNING in config.sh?)"; fi
done

echo; ok "Done. Log: $LOGFILE"
echo "Next: change passwords (./passwords.sh) and run ./hunt.sh"
