#!/bin/bash
# hunt.sh - READ-ONLY persistence/backdoor hunt. Flags things to look at;
# it does NOT delete anything. Review each finding yourself.
source "$(dirname "$0")/lib.sh"
need_root
start_log hunt

hdr "UID 0 ACCOUNTS"
awk -F: '$3==0 && $1!="root"{print}' /etc/passwd | while read -r l; do bad "Extra UID 0: $l"; done

hdr "ACCOUNTS WITH EMPTY PASSWORDS"
awk -F: '($2==""){print $1}' /etc/shadow | while read -r u; do bad "Empty password: $u"; done

hdr "AUTHORIZED SSH KEYS"
find / -xdev -name 'authorized_keys*' 2>/dev/null | while read -r f; do
  warn "$f ($(wc -l < "$f") keys)"; sed 's/^/       /' "$f" | cut -c1-120
done

hdr "CRON JOBS"
cat /etc/crontab 2>/dev/null | grep -v '^#' | grep -v '^\s*$'
ls -la /etc/cron.d/ /etc/cron.hourly/ 2>/dev/null
for f in /var/spool/cron/*; do [[ -f "$f" ]] && { warn "User crontab: $f"; sed 's/^/       /' "$f"; }; done

hdr "SYSTEMD TIMERS"
systemctl list-timers --all --no-pager

hdr "RECENTLY MODIFIED SYSTEMD UNITS (last 7 days)"
find /etc/systemd /usr/lib/systemd -name '*.service' -mtime -7 2>/dev/null

hdr "LD_PRELOAD HIJACK"
if [[ -s /etc/ld.so.preload ]]; then bad "/etc/ld.so.preload has content:"; cat /etc/ld.so.preload
else ok "/etc/ld.so.preload empty/absent"; fi

hdr "SHELL STARTUP FILES (aliases / odd commands)"
grep -HnE 'alias|curl|wget|nc |ncat|/dev/tcp|base64|python|bash -i' \
  /etc/profile /etc/bashrc /etc/profile.d/* /root/.bashrc /root/.bash_profile /home/*/.bashrc /home/*/.bash_profile 2>/dev/null

hdr "rc.local"
[[ -x /etc/rc.d/rc.local ]] && { warn "rc.local is executable:"; grep -v '^#' /etc/rc.d/rc.local; } || ok "rc.local not executable"

hdr "PAM (pam_exec / pam_permit used in auth)"
grep -rn 'pam_exec\|pam_permit' /etc/pam.d/ 2>/dev/null

hdr "SUID/SGID FILES NOT OWNED BY A PACKAGE"
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | while read -r f; do
  rpm -qf "$f" >/dev/null 2>&1 || bad "Unpackaged SUID/SGID: $f"
done

hdr "FILES IN TEMP DIRS"
ls -la /tmp /var/tmp /dev/shm 2>/dev/null | grep -vE '^total|\s\.\.?$'

hdr "EXECUTABLES IN TEMP DIRS"
find /tmp /var/tmp /dev/shm -type f -perm /111 2>/dev/null | while read -r f; do bad "$f"; done

hdr "POSSIBLE WEBSHELLS in $WEB_ROOT"
grep -rlE 'eval\(|base64_decode|system\(|shell_exec|passthru|exec\(\$_' "$WEB_ROOT" 2>/dev/null | while read -r f; do bad "$f"; done

hdr "PROCESSES RUNNING FROM DELETED FILES"
ls -l /proc/*/exe 2>/dev/null | grep deleted

hdr "MODIFIED PACKAGE BINARIES (rpm -Va, may take a minute)"
rpm -Va 2>/dev/null | grep -E '^..5' | grep -v ' c ' | while read -r l; do bad "$l"; done

echo; ok "Hunt saved to $LOGFILE. Nothing was changed."
