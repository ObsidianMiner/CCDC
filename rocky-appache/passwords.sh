#!/bin/bash
# passwords.sh - change passwords for every account with a login shell.
# Prompts per user so you choose each password (nothing is stored or logged).
# Check your competition rules about reporting changed scored-user passwords!
source "$(dirname "$0")/lib.sh"
need_root

hdr "ACCOUNTS WITH A LOGIN SHELL"
mapfile -t USERS < <(awk -F: '$7!~/nologin|false/{print $1}' /etc/passwd)
printf '  %s\n' "${USERS[@]}"

for u in "${USERS[@]}"; do
  echo
  read -rp "${BLU}?${RST} $u: [c]hange password, [l]ock account, [s]kip? " a
  case "$a" in
    c|C) passwd "$u" ;;
    l|L) if [[ "$u" == "root" ]]; then bad "Not locking root."; else
           usermod -L -s /sbin/nologin "$u" && ok "Locked $u (undo: usermod -U -s /bin/bash $u)"; fi ;;
    *)   echo "  skipped" ;;
  esac
done

hdr "Also consider"
echo "  - Database root password:  mysql -u root -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'NEW';\""
echo "  - Web app / CMS admin passwords"
echo "  - Remove unknown users from wheel:  gpasswd -d <user> wheel"
