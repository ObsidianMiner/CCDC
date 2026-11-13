# shellcheck shell=bash
# lib.sh - shared helpers. Sourced, not run.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

TS="$(date +%Y%m%d-%H%M%S)"
RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[36m'; RST=$'\e[0m'

hdr()  { echo; echo "${BLU}==== $* ====${RST}"; }
ok()   { echo "${GRN}[OK]${RST}   $*"; }
warn() { echo "${YEL}[WARN]${RST} $*"; }
bad()  { echo "${RED}[!!]${RST}   $*"; }

need_root() {
  if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo $0"; exit 1; fi
}

setup_dirs() {
  mkdir -p "$BACKUP_DIR" "$LOG_DIR"
  chmod 700 "$CCDC_DIR"
}

# Log everything the calling script prints to a timestamped file too
start_log() {
  setup_dirs
  local name="$1"
  LOGFILE="$LOG_DIR/${name}-${TS}.log"
  exec > >(tee -a "$LOGFILE") 2>&1
  echo "Logging to $LOGFILE"
}
