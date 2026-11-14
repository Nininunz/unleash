RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
MAG='\033[1;35m'
NC='\033[0m'

LOG_FILE=""
VERBOSE=false
DRY_RUN=false

log() {
  local level="$1"
  local msg="$2"
  local color=""
  local label=""

  case "$level" in
    ERROR)   color="$RED";   label="ERR"  ;;
    WARN)    color="$YEL";   label="WRN"  ;;
    OK)      color="$GRN";   label=" OK"  ;;
    INFO)    color="$BLU";   label="INF"  ;;
    STEP)    color="$CYAN";  label="STP"  ;;
    DEBUG)   color="$MAG";   label="DBG"  ;;
    *)       color="$NC";    label="LOG"  ;;
  esac

  if [ "$level" = "DEBUG" ] && [ "$VERBOSE" = false ]; then
    return
  fi

  local ts
  ts=$(date '+%H:%M:%S')
  echo -e "${color}[${label}]${NC} ${msg}" >&2

  if [ -n "$LOG_FILE" ]; then
    echo "[${ts}] [${label}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

error_exit() {
  log "ERROR" "$1"
  exit 1
}

warn() {
  log "WARN" "$1"
}

success() {
  log "OK" "$1"
}

info() {
  log "INFO" "$1"
}

step() {
  log "STEP" "$1"
}

debug() {
  log "DEBUG" "$1"
}

header() {
  local title="$1"
  local len="${#title}"
  local line
  line=$(printf '%*s' "$((len + 4))" '')
  line="${line// /═}"
  echo ""
  echo -e "${CYAN}╔${line}╗${NC}"
  echo -e "${CYAN}║  ${title}  ║${NC}"
  echo -e "${CYAN}╚${line}╝${NC}"
  echo ""
}

begin() {
  local label="$1"
  echo -ne "${CYAN}  ${label} ... ${NC}"
}

spinner() {
  local pid=$1
  local msg="${2:-Working}"
  local spin='-\|/'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    echo -ne "\r${CYAN}  ${msg} ... ${spin:$i:1}${NC}"
    sleep 0.2
  done
  echo -ne "\r${CYAN}  ${msg} ... ${NC}"
}

end_ok() {
  echo -e "${GRN}✓${NC}"
}

end_fail() {
  echo -e "${RED}✗${NC}"
}

# Only scalar identifiers are supported. Reserve our locals' prefix so Bash's
# dynamic scoping cannot silently assign to a helper local instead of the caller.
prompt_destination_valid() {
  if [[ ! "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || [[ "$1" == __unleash_prompt_* ]]; then
    printf '%s\n' 'Invalid prompt destination variable' >&2
    return 1
  fi
}

# Literal printf -v assignment adapted from ejams1's approach:
# https://github.com/ejams1/unleash/commit/574b70a
prompt_default() {
  prompt_destination_valid "$1" || return 1
  local __unleash_prompt_value
  IFS= read -r -p "${CYAN}${2}${NC} (default '${3}'): " __unleash_prompt_value || return 1
  printf -v "$1" '%s' "${__unleash_prompt_value:-$3}"
}

confirm() {
  local prompt="$1"
  local response
  read -r -p "${prompt} (y/N): " response
  [[ "$response" =~ ^[Yy]$ ]]
}
