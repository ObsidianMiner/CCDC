# shellcheck shell=bash
# config.sh - shared settings for all scripts. EDIT THIS FIRST for each box.
# Sourced by the other scripts; not meant to be run directly.

# Firewalld services that the scoring engine checks (names from: firewall-cmd --get-services)
SCORED_SERVICES="ssh http https"
# Extra raw ports to allow, e.g. "8080/tcp 53/udp" (leave empty if none)
EXTRA_PORTS=""

# systemd services that MUST stay running (verified after hardening)
KEEP_RUNNING="sshd httpd mariadb firewalld"

# Services to disable if present AND not in KEEP_RUNNING
DISABLE_SERVICES="cups avahi-daemon rpcbind telnet.socket vsftpd nfs-server smb nmb bluetooth"

# SSH: allow root login? "no" is safer, but make sure you have another sudo user first!
SSH_PERMIT_ROOT="no"
# SSH: restrict to these users (space-separated). Empty = don't restrict.
SSH_ALLOW_USERS=""

# Where output goes
CCDC_DIR="/root/.ccdc"
BACKUP_DIR="$CCDC_DIR/backups"
LOG_DIR="$CCDC_DIR/logs"

# Web root to back up / scan
WEB_ROOT="/var/www"
