#!/bin/bash
# score.sh - fake scoring engine. Run from a DIFFERENT VM, not the box you're defending.
# Usage: ./score.sh <target-ip> [interval-seconds]
# Edit the CHECKS section to match your practice services.
T="${1:?Usage: $0 <target-ip> [interval]}"
INTERVAL="${2:-60}"
GRN=$'\e[32m'; RED=$'\e[31m'; RST=$'\e[0m'
UP=0; TOTAL=0

check() {  # check "name" "command"
  TOTAL=$((TOTAL+1))
  if eval "$2" >/dev/null 2>&1; then echo "  ${GRN}[UP]  ${RST} $1"; UP=$((UP+1))
  else echo "  ${RED}[DOWN]${RST} $1"; fi
}

while true; do
  clear; echo "Target: $T   $(date '+%H:%M:%S')   (every ${INTERVAL}s, Ctrl+C to stop)"; echo
  ROUND_UP=$UP; ROUND_TOTAL=$TOTAL
  # ---------- CHECKS ----------
  check "PING"           "ping -c1 -W2 $T"
  check "SSH  (22)"      "timeout 3 bash -c '</dev/tcp/$T/22'"
  check "HTTP (80)"      "curl -s --max-time 4 http://$T/ | grep -q 'scored ok'"
  # check "HTTPS (443)"  "curl -sk --max-time 4 https://$T/ | grep -q 'scored ok'"
  # check "MySQL (3306)" "timeout 3 bash -c '</dev/tcp/$T/3306'"
  # check "DNS (53)"     "dig +short +time=2 @$T example.lab"
  # ----------------------------
  echo; echo "  This round: $((UP-ROUND_UP))/$((TOTAL-ROUND_TOTAL))   Overall uptime: $((100*UP/TOTAL))%"
  sleep "$INTERVAL"
done
