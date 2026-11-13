#!/bin/bash
# backup.sh - back up configs, web files, home dirs, and databases.
# Usage: ./backup.sh            -> make a new backup
#        ./backup.sh list       -> show existing backups
source "$(dirname "$0")/lib.sh"
need_root
setup_dirs

if [[ "$1" == "list" ]]; then
  ls -lh "$BACKUP_DIR"; exit 0
fi

DEST="$BACKUP_DIR/$TS"
mkdir -p "$DEST"
hdr "Backing up to $DEST"

tar czf "$DEST/etc.tgz" /etc 2>/dev/null && ok "/etc" || bad "/etc failed"
[[ -d "$WEB_ROOT" ]] && { tar czf "$DEST/www.tgz" "$WEB_ROOT" 2>/dev/null && ok "$WEB_ROOT" || bad "$WEB_ROOT failed"; }
tar czf "$DEST/home.tgz" /home /root/.ssh 2>/dev/null && ok "/home + /root/.ssh"

# Cron + systemd units (useful for spotting persistence later by diffing)
tar czf "$DEST/cron-systemd.tgz" /var/spool/cron /etc/systemd/system 2>/dev/null && ok "cron + systemd units"

# Databases
if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysqld; then
  if mysqldump --all-databases --single-transaction > "$DEST/db.sql" 2>"$DEST/db.err"; then
    ok "MariaDB/MySQL dump"; rm -f "$DEST/db.err"
  else
    warn "DB dump failed (root has a password?). Run manually:"
    echo "     mysqldump -u root -p --all-databases > $DEST/db.sql"
  fi
fi
if systemctl is-active --quiet postgresql; then
  sudo -u postgres pg_dumpall > "$DEST/pg.sql" 2>/dev/null && ok "PostgreSQL dump"
fi

# Package state + hashes of key binaries (to detect tampering later)
rpm -qa | sort > "$DEST/packages.txt"
sha256sum /usr/bin/{ls,ps,ss,netstat,sudo,su,passwd,login,bash,sshd} /usr/sbin/sshd 2>/dev/null > "$DEST/binary-hashes.txt"
ok "package list + binary hashes"

chmod -R 600 "$DEST"; chmod 700 "$DEST"
hdr "Done"
du -sh "$DEST"
echo
echo "To restore web files:   tar xzf $DEST/www.tgz -C / && restorecon -Rv $WEB_ROOT"
echo "To restore one config:  tar xzf $DEST/etc.tgz -C /tmp && diff -r /tmp/etc/ssh /etc/ssh"
echo "To restore DB:          mysql -u root -p < $DEST/db.sql"
echo "To check binaries:      sha256sum -c $DEST/binary-hashes.txt"
