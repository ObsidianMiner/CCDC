#!/bin/bash
# recon.sh - READ-ONLY snapshot of the box. Safe to run anytime.
# Run first thing, and again later to diff:  diff <old log> <new log>
source "$(dirname "$0")/lib.sh"
need_root
start_log recon

hdr "SYSTEM"
grep -E '^(NAME|VERSION)=' /etc/os-release
echo "Hostname: $(hostname)"; uptime

hdr "IP ADDRESSES"
ip -br a

hdr "LOGGED IN NOW"
w

hdr "RECENT LOGINS"
last -n 15 | head -15

hdr "LISTENING PORTS"
ss -tulpn

hdr "ESTABLISHED CONNECTIONS (look for reverse shells)"
ss -tanp state established

hdr "RUNNING SERVICES"
systemctl list-units --type=service --state=running --no-pager --no-legend

hdr "ENABLED SERVICES (start at boot)"
systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend

hdr "USERS WITH A LOGIN SHELL"
awk -F: '$7!~/nologin|false/{printf "%-15s uid=%-6s %s\n",$1,$3,$7}' /etc/passwd

hdr "UID 0 ACCOUNTS (should only be root)"
awk -F: '$3==0{print $1}' /etc/passwd

hdr "SUDO ACCESS"
getent group wheel
grep -rhv '^\s*#' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^\s*$'

hdr "SELINUX"
getenforce

hdr "FIREWALL"
firewall-cmd --state 2>/dev/null && firewall-cmd --list-all

hdr "PROCESS TREE"
ps auxf --width 200

echo; ok "Recon saved to $LOGFILE"
