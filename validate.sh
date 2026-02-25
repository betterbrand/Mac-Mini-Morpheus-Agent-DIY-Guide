#!/usr/bin/env bash
# Mac Mini Agent Setup Validator
# Checks your setup against the DIY Agent Guide and reports issues.
#
# Usage:
#   ./validate.sh                  # Full check with colored output
#   ./validate.sh --json           # Machine-readable JSON only
#   ./validate.sh --phase 1        # Run only Phase 1 checks
#   ./validate.sh --quiet          # Summary only
#   ./validate.sh --help           # Show usage
#
# Requires: validate-config.sh in the same directory (copy from validate-config.example.sh)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/validate-config.sh"

# ─── Defaults ───────────────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
CHECKS_JSON="[]"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TIMESTAMP_FILE="$(date +"%Y-%m-%d-%H%M%S")"
OUTPUT_JSON=false
OUTPUT_QUIET=false
PHASE_FILTER=""

# ─── Colors ─────────────────────────────────────────────────────────────────────

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ─── Usage ──────────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Mac Mini Agent Setup Validator

Usage: ./validate.sh [OPTIONS]

Options:
  --json        Output machine-readable JSON only (no color terminal output)
  --phase N     Run only phase N checks (0-7)
  --quiet       Summary only, no individual check lines
  --help        Show this help message

Setup:
  cp validate-config.example.sh validate-config.sh
  nano validate-config.sh   # fill in your values
  ./validate.sh
EOF
  exit 0
}

# ─── Parse flags ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)   OUTPUT_JSON=true; shift ;;
    --quiet)  OUTPUT_QUIET=true; shift ;;
    --phase)
      PHASE_FILTER="$2"; shift 2
      if ! [[ "$PHASE_FILTER" =~ ^[0-7]$ ]]; then
        echo "Error: --phase must be 0-7" >&2; exit 1
      fi
      ;;
    --help|-h) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ─── Load config ────────────────────────────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE" >&2
  echo "Run: cp validate-config.example.sh validate-config.sh" >&2
  exit 1
fi

# shellcheck source=validate-config.example.sh
source "$CONFIG_FILE"

# Validate required config
for var in AGENT_USER ADMIN_USER WORKSPACE_DIR LOG_DIR; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: $var not set in $CONFIG_FILE" >&2
    exit 1
  fi
done

# Defaults for optional config
BRIDGE_ENABLED="${BRIDGE_ENABLED:-false}"
BRIDGE_CERT_PATH="${BRIDGE_CERT_PATH:-$HOME/.config/proton-bridge-cert.pem}"
SIGNAL_ENABLED="${SIGNAL_ENABLED:-false}"
MORPHEUS_ENABLED="${MORPHEUS_ENABLED:-false}"
OLLAMA_ENABLED="${OLLAMA_ENABLED:-false}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
SAFE_ENABLED="${SAFE_ENABLED:-false}"

# ─── Detect user context ────────────────────────────────────────────────────────

CURRENT_USER="$(whoami)"
HOSTNAME="$(hostname -s 2>/dev/null || hostname)"

if [[ "$CURRENT_USER" == "$ADMIN_USER" ]]; then
  USER_TYPE="admin"
elif [[ "$CURRENT_USER" == "$AGENT_USER" ]]; then
  USER_TYPE="agent"
else
  USER_TYPE="other"
fi

# ─── Ensure log directory ──────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"

# ─── Check function ────────────────────────────────────────────────────────────

# check PHASE DESCRIPTION LEVEL COMMAND...
#   PHASE:       integer 0-7
#   DESCRIPTION: human-readable check description
#   LEVEL:       FAIL | WARN (determines severity if check fails)
#   COMMAND...:  the test to run; exit 0 = pass, nonzero = fail
#
# A failed FAIL-level check counts as a failure.
# A failed WARN-level check counts as a warning.
# SKIP and INFO are set internally, not passed as LEVEL.

check() {
  local phase="$1" description="$2" level="$3"
  shift 3

  # Phase filter
  if [[ -n "$PHASE_FILTER" ]] && [[ "$phase" != "$PHASE_FILTER" ]]; then
    return
  fi

  local result detail
  detail=""

  # Capture both stdout and exit code from the test
  if detail="$(eval "$@" 2>&1)"; then
    result="PASS"
  else
    result="$level"
  fi

  # Record result
  case "$result" in
    PASS) ((PASS_COUNT++)) ;;
    FAIL) ((FAIL_COUNT++)) ;;
    WARN) ((WARN_COUNT++)) ;;
    SKIP) ((SKIP_COUNT++)) ;;
  esac

  # Append to JSON array
  local escaped_desc escaped_detail
  escaped_desc="$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  escaped_detail="$(printf '%s' "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 200)"
  CHECKS_JSON="$(printf '%s' "$CHECKS_JSON" | sed 's/]$//')"
  if [[ "$CHECKS_JSON" != "[" ]]; then
    CHECKS_JSON="${CHECKS_JSON},"
  fi
  CHECKS_JSON="${CHECKS_JSON}{\"phase\":${phase},\"description\":\"${escaped_desc}\",\"level\":\"${level}\",\"result\":\"${result}\",\"detail\":\"${escaped_detail}\"}]"

  # Terminal output
  if [[ "$OUTPUT_JSON" == "true" ]] || [[ "$OUTPUT_QUIET" == "true" ]]; then
    return
  fi

  local color icon
  case "$result" in
    PASS) color="$GREEN"; icon="PASS" ;;
    FAIL) color="$RED";   icon="FAIL" ;;
    WARN) color="$YELLOW"; icon="WARN" ;;
    SKIP) color="$CYAN";  icon="SKIP" ;;
  esac

  printf "  ${color}%s${RESET}  %s" "$icon" "$description"
  if [[ -n "$detail" ]] && [[ "$result" != "PASS" ]]; then
    printf " ${DIM}-- %s${RESET}" "$detail"
  fi
  printf '\n'
}

# skip: record a skipped check (not scored)
skip() {
  local phase="$1" description="$2" reason="$3"

  if [[ -n "$PHASE_FILTER" ]] && [[ "$phase" != "$PHASE_FILTER" ]]; then
    return
  fi

  ((SKIP_COUNT++))

  local escaped_desc escaped_reason
  escaped_desc="$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  escaped_reason="$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  CHECKS_JSON="$(printf '%s' "$CHECKS_JSON" | sed 's/]$//')"
  if [[ "$CHECKS_JSON" != "[" ]]; then
    CHECKS_JSON="${CHECKS_JSON},"
  fi
  CHECKS_JSON="${CHECKS_JSON}{\"phase\":${phase},\"description\":\"${escaped_desc}\",\"level\":\"SKIP\",\"result\":\"SKIP\",\"detail\":\"${escaped_reason}\"}]"

  if [[ "$OUTPUT_JSON" == "true" ]] || [[ "$OUTPUT_QUIET" == "true" ]]; then
    return
  fi

  printf "  ${CYAN}SKIP${RESET}  %s ${DIM}-- %s${RESET}\n" "$description" "$reason"
}

# info: display informational line (not scored)
info() {
  local phase="$1" description="$2" value="$3"

  if [[ -n "$PHASE_FILTER" ]] && [[ "$phase" != "$PHASE_FILTER" ]]; then
    return
  fi

  local escaped_desc escaped_val
  escaped_desc="$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  escaped_val="$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 200)"
  CHECKS_JSON="$(printf '%s' "$CHECKS_JSON" | sed 's/]$//')"
  if [[ "$CHECKS_JSON" != "[" ]]; then
    CHECKS_JSON="${CHECKS_JSON},"
  fi
  CHECKS_JSON="${CHECKS_JSON}{\"phase\":${phase},\"description\":\"${escaped_desc}\",\"level\":\"INFO\",\"result\":\"INFO\",\"detail\":\"${escaped_val}\"}]"

  if [[ "$OUTPUT_JSON" == "true" ]] || [[ "$OUTPUT_QUIET" == "true" ]]; then
    return
  fi

  printf "  ${DIM}INFO${RESET}  %s ${DIM}-- %s${RESET}\n" "$description" "$value"
}

# Print a phase header
phase_header() {
  local phase="$1" title="$2"
  if [[ -n "$PHASE_FILTER" ]] && [[ "$phase" != "$PHASE_FILTER" ]]; then
    return
  fi
  if [[ "$OUTPUT_JSON" == "true" ]] || [[ "$OUTPUT_QUIET" == "true" ]]; then
    return
  fi
  printf '\n%b=== Phase %s: %s ===%b\n' "$BOLD" "$phase" "$title" "$RESET"
}

# ─── Header ────────────────────────────────────────────────────────────────────

if [[ "$OUTPUT_JSON" != "true" ]]; then
  printf '%bMac Mini Agent Setup Validator%b\n' "$BOLD" "$RESET"
  printf 'Run: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'User: %s (%s)\n' "$CURRENT_USER" "$USER_TYPE"
  printf 'Host: %s\n' "$HOSTNAME"
fi

# ─── Phase 0: Hardware & OS Info (INFO only) ───────────────────────────────────

phase_header 0 "Hardware & OS"

hw_model="$(sysctl -n hw.model 2>/dev/null || echo "unknown")"
hw_chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")"
hw_ram="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"
os_version="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
disk_free="$(df -h / 2>/dev/null | awk 'NR==2{print $4}' || echo "unknown")"

info 0 "Hardware model" "$hw_model"
info 0 "Chip" "$hw_chip"
info 0 "RAM" "$hw_ram"
info 0 "macOS version" "$os_version"
info 0 "Disk free" "$disk_free"
info 0 "Current user" "$CURRENT_USER ($USER_TYPE)"

# ─── Phase 1: Mac mini Setup ──────────────────────────────────────────────────

phase_header 1 "Mac mini Setup"

# 1. Agent user exists
check 1 "Agent user '$AGENT_USER' exists" "FAIL" \
  "id '$AGENT_USER' >/dev/null 2>&1"

# 2. Admin user exists
check 1 "Admin user '$ADMIN_USER' exists" "FAIL" \
  "id '$ADMIN_USER' >/dev/null 2>&1"

# 3. Agent user is non-admin (requires admin or agent context)
if [[ "$USER_TYPE" == "admin" ]]; then
  check 1 "Agent user is non-admin" "FAIL" \
    "! dseditgroup -o checkmember -m '$AGENT_USER' admin 2>&1 | grep -q '^yes'"
elif [[ "$USER_TYPE" == "agent" ]]; then
  # Agent can check own membership
  check 1 "Agent user is non-admin" "FAIL" \
    "! dseditgroup -o checkmember -m '$AGENT_USER' admin 2>&1 | grep -q '^yes'"
else
  skip 1 "Agent user is non-admin" "run as agent or admin to check"
fi

# 4. Admin user is Administrator
check 1 "Admin user is Administrator" "FAIL" \
  "dseditgroup -o checkmember -m '$ADMIN_USER' admin 2>&1 | grep -q '^yes'"

# 5. Agent user in com.apple.access_ssh
if [[ "$USER_TYPE" == "admin" ]]; then
  check 1 "Agent user in SSH access group" "FAIL" \
    "dseditgroup -o checkmember -m '$AGENT_USER' com.apple.access_ssh 2>&1 | grep -q '^yes'"
else
  skip 1 "Agent user in SSH access group" "run as admin to check"
fi

# 6. SSH password auth disabled
if [[ "$USER_TYPE" == "admin" ]]; then
  check 1 "SSH password auth disabled" "FAIL" \
    "grep -qE '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config 2>/dev/null"
else
  skip 1 "SSH password auth disabled" "run as admin to check sshd_config"
fi

# 7. macOS firewall enabled
if [[ "$USER_TYPE" == "admin" ]]; then
  check 1 "macOS firewall enabled" "FAIL" \
    "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'enabled'"
else
  skip 1 "macOS firewall enabled" "run as admin to check"
fi

# 8. Sleep disabled
check 1 "Sleep disabled" "FAIL" \
  "pmset -g custom 2>/dev/null | grep -E '^\s*sleep\s' | awk '{print \$2}' | grep -q '^0$'"

# 9. Auto-restart on power failure
check 1 "Auto-restart on power failure" "FAIL" \
  "pmset -g custom 2>/dev/null | grep -E '^\s*autorestart\s' | awk '{print \$2}' | grep -q '^1$'"

# 10. Display detected (HDMI dongle)
check 1 "Display detected (HDMI dongle)" "WARN" \
  "system_profiler SPDisplaysDataType 2>/dev/null | grep -qi 'resolution'"

# 11. Admin-to-agent localhost SSH key
if [[ "$USER_TYPE" == "admin" ]]; then
  agent_home="$(eval echo "~$AGENT_USER" 2>/dev/null)"
  check 1 "Admin SSH key in agent's authorized_keys" "WARN" \
    "test -f '${agent_home}/.ssh/authorized_keys' && test -s '${agent_home}/.ssh/authorized_keys'"
else
  skip 1 "Admin SSH key in agent's authorized_keys" "run as admin to check"
fi

# ─── Phase 2: Agent Identity ──────────────────────────────────────────────────

phase_header 2 "Agent Identity"

if [[ "$BRIDGE_ENABLED" == "true" ]]; then
  # 1. Proton Bridge app installed
  check 2 "Proton Bridge app installed" "FAIL" \
    "test -d '/Applications/Proton Mail Bridge.app'"

  # 2. Bridge wrapper script exists and is executable
  check 2 "Bridge wrapper script exists" "FAIL" \
    "test -x '$HOME/.local/bin/start-bridge.sh'"

  # 3. Wrapper uses tmux send-keys
  check 2 "Wrapper uses 'tmux send-keys'" "FAIL" \
    "grep -q 'send-keys' '$HOME/.local/bin/start-bridge.sh' 2>/dev/null"

  # 4. Bridge tmux session running
  if [[ "$USER_TYPE" == "agent" ]]; then
    check 2 "Bridge tmux session running" "FAIL" \
      "tmux list-sessions 2>/dev/null | grep -qi 'bridge'"
  else
    skip 2 "Bridge tmux session running" "run as agent to check"
  fi

  # 5. IMAP port 1143 listening
  check 2 "IMAP port 1143 listening" "FAIL" \
    "lsof -i :1143 -sTCP:LISTEN >/dev/null 2>&1"

  # 6. SMTP port 1025 listening
  check 2 "SMTP port 1025 listening" "FAIL" \
    "lsof -i :1025 -sTCP:LISTEN >/dev/null 2>&1"

  # 7. TLS cert at permanent path
  check 2 "TLS cert at permanent path" "FAIL" \
    "test -f '$BRIDGE_CERT_PATH'"

  # 8. TLS cert not in /tmp
  check 2 "No TLS cert references to /tmp" "WARN" \
    "! grep -r '/tmp.*\\.pem' '$HOME/.mbsyncrc' '$HOME/.msmtprc' 2>/dev/null | grep -q '/tmp'"

  # 9. No Bridge LaunchAgent (should use tmux, not launchd)
  check 2 "No Bridge LaunchAgent" "FAIL" \
    "! ls '$HOME/Library/LaunchAgents/'*bridge* 2>/dev/null | grep -q ."
else
  skip 2 "Proton Bridge checks (9)" "BRIDGE_ENABLED=false"
fi

# 10. Git user.name configured
if [[ "$USER_TYPE" == "agent" ]] || [[ "$USER_TYPE" == "other" ]]; then
  check 2 "Git user.name configured" "FAIL" \
    "git config --global user.name >/dev/null 2>&1"
else
  skip 2 "Git user.name configured" "run as agent to check"
fi

# 11. Git user.email configured
if [[ "$USER_TYPE" == "agent" ]] || [[ "$USER_TYPE" == "other" ]]; then
  check 2 "Git user.email configured" "FAIL" \
    "git config --global user.email >/dev/null 2>&1"
else
  skip 2 "Git user.email configured" "run as agent to check"
fi

# 12. gh CLI installed
check 2 "gh CLI installed" "WARN" \
  "command -v gh >/dev/null 2>&1"

# 13. gh authenticated
if [[ "$USER_TYPE" == "agent" ]]; then
  check 2 "gh authenticated" "WARN" \
    "gh auth status >/dev/null 2>&1"
else
  skip 2 "gh authenticated" "run as agent to check"
fi

# 14. Dedicated keychain exists
if [[ "$USER_TYPE" == "agent" ]]; then
  # Look for any dedicated keychain (not login.keychain-db)
  check 2 "Dedicated keychain exists" "FAIL" \
    "ls '$HOME'/*.keychain-db 2>/dev/null | grep -v login.keychain-db | grep -q ."
else
  skip 2 "Dedicated keychain exists" "run as agent to check"
fi

# 15. Keychain password file permissions 0400
if [[ "$USER_TYPE" == "agent" ]]; then
  # Find keychain password files
  kc_pass_file="$(ls "$HOME"/.*.keychain-db 2>/dev/null | grep -v login | head -1 | sed 's/keychain-db$//' | sed 's/\.//')"
  # Try common patterns
  kc_pass_candidates=("$HOME/.my-keychain-pass" "$HOME/.safe-keychain-pass")
  kc_pass_found=""
  for f in "${kc_pass_candidates[@]}"; do
    if [[ -f "$f" ]]; then kc_pass_found="$f"; break; fi
  done
  # Also scan for any *keychain*pass* files
  if [[ -z "$kc_pass_found" ]]; then
    kc_pass_found="$(find "$HOME" -maxdepth 1 -name '*keychain*pass*' -type f 2>/dev/null | head -1)"
  fi
  if [[ -n "$kc_pass_found" ]]; then
    check 2 "Keychain password file permissions 0400" "FAIL" \
      "stat -f '%Lp' '$kc_pass_found' 2>/dev/null | grep -q '^400$'"
  else
    skip 2 "Keychain password file permissions 0400" "no keychain password file found"
  fi
else
  skip 2 "Keychain password file permissions 0400" "run as agent to check"
fi

# 16. Keychain password file immutable
if [[ "$USER_TYPE" == "agent" ]] && [[ -n "${kc_pass_found:-}" ]]; then
  check 2 "Keychain password file immutable (uchg)" "FAIL" \
    "ls -lO '$kc_pass_found' 2>/dev/null | grep -q 'uchg'"
else
  skip 2 "Keychain password file immutable (uchg)" "no keychain password file found or run as agent"
fi

# ─── Phase 3: Communication / Signal ──────────────────────────────────────────

phase_header 3 "Communication"

if [[ "$SIGNAL_ENABLED" == "true" ]]; then
  # 1. signal-cli installed
  check 3 "signal-cli installed" "FAIL" \
    "command -v signal-cli >/dev/null 2>&1"

  # 2. signal-cli is Homebrew ARM binary
  check 3 "signal-cli is Homebrew ARM binary" "FAIL" \
    "command -v signal-cli 2>/dev/null | grep -q '/opt/homebrew'"

  # 3. tmux installed
  check 3 "tmux installed" "FAIL" \
    "command -v tmux >/dev/null 2>&1"

  # 4. signal-cli registered
  check 3 "signal-cli has registered accounts" "WARN" \
    "ls '$HOME/.local/share/signal-cli/data/'*.d 2>/dev/null | grep -q . || ls '$HOME/.config/signal-cli/data/'*.d 2>/dev/null | grep -q ."
else
  skip 3 "Signal checks (4)" "SIGNAL_ENABLED=false"
fi

# ─── Phase 4: Model Routing ──────────────────────────────────────────────────

phase_header 4 "Model Routing"

# Tailscale (required for remote access)
check 4 "Tailscale installed" "FAIL" \
  "command -v tailscale >/dev/null 2>&1"

check 4 "Tailscale running" "FAIL" \
  "tailscale status >/dev/null 2>&1"

ts_ip="$(tailscale ip -4 2>/dev/null || echo "none")"
check 4 "Tailscale IP assigned" "FAIL" \
  "echo '$ts_ip' | grep -q '^100\.'"
if [[ "$ts_ip" != "none" ]]; then
  info 4 "Tailscale IP" "$ts_ip"
fi

# Morpheus
if [[ "$MORPHEUS_ENABLED" == "true" ]]; then
  # Proxy-router process running
  check 4 "Proxy-router process running" "FAIL" \
    "pgrep -f 'proxy-router' >/dev/null 2>&1 || lsof -i :8082 -sTCP:LISTEN >/dev/null 2>&1"

  # Proxy-router health endpoint
  check 4 "Proxy-router health endpoint" "FAIL" \
    "curl -sf --max-time 5 'http://127.0.0.1:8082/healthcheck' >/dev/null 2>&1 || curl -sf --max-time 5 'http://127.0.0.1:8082/health' >/dev/null 2>&1"

  # Proxy-router on localhost only
  check 4 "Proxy-router on localhost only" "FAIL" \
    "! lsof -i :8082 -sTCP:LISTEN 2>/dev/null | grep -q '\\*:8082'"

  # Proxy bridge process running
  check 4 "Proxy bridge listening on 8083" "FAIL" \
    "lsof -i :8083 -sTCP:LISTEN >/dev/null 2>&1"

  # Proxy bridge on localhost only
  check 4 "Proxy bridge on localhost only" "FAIL" \
    "! lsof -i :8083 -sTCP:LISTEN 2>/dev/null | grep -q '\\*:8083'"

  # Proxy-router running when bridge is running (dependency order)
  check 4 "Proxy-router up when bridge is up" "FAIL" \
    "if lsof -i :8083 -sTCP:LISTEN >/dev/null 2>&1; then lsof -i :8082 -sTCP:LISTEN >/dev/null 2>&1; else true; fi"

  # Proxy-router LaunchAgent exists
  check 4 "Proxy-router LaunchAgent exists" "WARN" \
    "ls '$HOME/Library/LaunchAgents/'*proxy-router* '$HOME/Library/LaunchAgents/'*morpheus*router* 2>/dev/null | grep -q ."

  # Proxy-router LaunchAgent has KeepAlive
  morpheus_plist="$(ls "$HOME/Library/LaunchAgents/"*proxy-router* "$HOME/Library/LaunchAgents/"*morpheus*router* 2>/dev/null | head -1)"
  if [[ -n "${morpheus_plist:-}" ]]; then
    check 4 "Proxy-router LaunchAgent has KeepAlive" "WARN" \
      "grep -q 'KeepAlive' '$morpheus_plist'"
  else
    skip 4 "Proxy-router LaunchAgent has KeepAlive" "no LaunchAgent plist found"
  fi

  # .env permissions 0600
  morpheus_env="$(find "$HOME/morpheus" "$HOME/.morpheus" -name '.env' -maxdepth 2 2>/dev/null | head -1)"
  if [[ -n "${morpheus_env:-}" ]]; then
    check 4 ".env permissions 0600 or stricter" "FAIL" \
      "perms=\$(stat -f '%Lp' '$morpheus_env' 2>/dev/null); test \"\$perms\" = '600' || test \"\$perms\" = '400'"
  else
    skip 4 ".env permissions 0600 or stricter" "no morpheus .env found"
  fi
else
  skip 4 "Morpheus checks (9)" "MORPHEUS_ENABLED=false"
fi

# Ollama
if [[ "$OLLAMA_ENABLED" == "true" ]]; then
  check 4 "Ollama reachable" "FAIL" \
    "curl -sf --max-time 5 'http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags' >/dev/null 2>&1"

  check 4 "Ollama has models pulled" "FAIL" \
    "curl -sf --max-time 5 'http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags' 2>/dev/null | grep -q '\"name\"'"

  # If remote host, check it's accessible
  if [[ "$OLLAMA_HOST" != "127.0.0.1" ]] && [[ "$OLLAMA_HOST" != "localhost" ]]; then
    check 4 "Ollama accessible from this machine" "WARN" \
      "curl -sf --max-time 5 'http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags' >/dev/null 2>&1"
  fi

  # Display models
  ollama_models="$(curl -sf --max-time 5 "http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | tr '\n' ', ' | sed 's/,$//')"
  if [[ -n "${ollama_models:-}" ]]; then
    info 4 "Ollama models" "$ollama_models"
  fi
else
  skip 4 "Ollama checks (3)" "OLLAMA_ENABLED=false"
fi

# General: framework config and process
if [[ -d "$WORKSPACE_DIR" ]]; then
  framework_config="$(ls "$WORKSPACE_DIR"/*.json 2>/dev/null | head -1)"
  if [[ -n "${framework_config:-}" ]]; then
    info 4 "Agent framework config" "$framework_config"
  fi
fi

# ─── Phase 5: Persona & Workspace ────────────────────────────────────────────

phase_header 5 "Persona & Workspace"

if [[ "$USER_TYPE" == "agent" ]] || [[ -d "$WORKSPACE_DIR" ]]; then
  check 5 "Workspace directory exists" "FAIL" \
    "test -d '$WORKSPACE_DIR'"

  check 5 "SOUL.md exists and non-empty" "FAIL" \
    "test -s '$WORKSPACE_DIR/SOUL.md'"

  check 5 "IDENTITY.md exists" "FAIL" \
    "test -f '$WORKSPACE_DIR/IDENTITY.md'"

  check 5 "USER.md exists" "FAIL" \
    "test -f '$WORKSPACE_DIR/USER.md'"

  check 5 "AGENTS.md exists and mentions kill switch" "FAIL" \
    "test -f '$WORKSPACE_DIR/AGENTS.md' && grep -qi 'kill\|stop.*immediately\|halt' '$WORKSPACE_DIR/AGENTS.md'"

  check 5 "TOOLS.md exists" "FAIL" \
    "test -f '$WORKSPACE_DIR/TOOLS.md'"

  check 5 "MEMORY.md exists" "FAIL" \
    "test -f '$WORKSPACE_DIR/MEMORY.md'"
else
  skip 5 "Persona & workspace checks (7)" "workspace dir not found and not running as agent"
fi

# ─── Phase 6: Security Hardening ─────────────────────────────────────────────

phase_header 6 "Security Hardening"

# 1. No sk- patterns in config dirs (API key leak)
if [[ "$USER_TYPE" == "agent" ]]; then
  check 6 "No API key patterns (sk-) in config dirs" "FAIL" \
    "! grep -r 'sk-[a-zA-Z0-9]\\{20,\\}' '$WORKSPACE_DIR' '$HOME/.config' 2>/dev/null | grep -v '.keychain' | grep -q 'sk-'"
else
  skip 6 "No API key patterns (sk-) in config dirs" "run as agent to check"
fi

# 2. No hex private keys in config dirs
if [[ "$USER_TYPE" == "agent" ]]; then
  check 6 "No hex private keys in config dirs" "FAIL" \
    "! grep -rE '0x[a-fA-F0-9]{64}' '$WORKSPACE_DIR' '$HOME/.config' 2>/dev/null | grep -v '.keychain' | grep -v 'node_modules' | grep -q '0x'"
else
  skip 6 "No hex private keys in config dirs" "run as agent to check"
fi

# 3. No passwords in shell history
if [[ "$USER_TYPE" == "agent" ]]; then
  check 6 "No passwords in shell history" "FAIL" \
    "! grep -iE 'password|passwd|secret|api.key|private.key' '$HOME/.zsh_history' '$HOME/.bash_history' 2>/dev/null | grep -v 'unlock-keychain' | grep -v 'find-generic-password' | grep -v 'add-generic-password' | head -1 | grep -q ."
else
  skip 6 "No passwords in shell history" "run as agent to check"
fi

# 4. Proxy-router not on 0.0.0.0 (security framing)
if [[ "$MORPHEUS_ENABLED" == "true" ]]; then
  check 6 "Proxy-router not exposed to network" "FAIL" \
    "! lsof -i :8082 -sTCP:LISTEN 2>/dev/null | grep -q '\\*:8082'"

  # 5. Proxy bridge not on 0.0.0.0
  check 6 "Proxy bridge not exposed to network" "FAIL" \
    "! lsof -i :8083 -sTCP:LISTEN 2>/dev/null | grep -q '\\*:8083'"
else
  skip 6 "Proxy-router not exposed to network" "MORPHEUS_ENABLED=false"
  skip 6 "Proxy bridge not exposed to network" "MORPHEUS_ENABLED=false"
fi

# 6. SSH password auth disabled (security framing)
if [[ "$USER_TYPE" == "admin" ]]; then
  check 6 "SSH key-only authentication" "FAIL" \
    "grep -qE '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config 2>/dev/null"
else
  skip 6 "SSH key-only authentication" "run as admin to check sshd_config"
fi

# 7. Firewall enabled (security framing)
if [[ "$USER_TYPE" == "admin" ]]; then
  check 6 "Firewall enabled" "FAIL" \
    "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'enabled'"
else
  skip 6 "Firewall enabled" "run as admin to check"
fi

# 8. Agent user cannot sudo
if [[ "$USER_TYPE" == "agent" ]]; then
  check 6 "Agent user cannot sudo" "FAIL" \
    "! sudo -n true 2>/dev/null"
else
  skip 6 "Agent user cannot sudo" "run as agent to check"
fi

# 9. LaunchAgents loaded in launchctl
if [[ "$USER_TYPE" == "agent" ]]; then
  known_agents=()
  if [[ "$MORPHEUS_ENABLED" == "true" ]]; then
    known_agents+=("morpheus" "proxy-router")
  fi
  if [[ ${#known_agents[@]} -gt 0 ]]; then
    loaded_list="$(launchctl list 2>/dev/null || true)"
    missing_agents=""
    for agent_label in "${known_agents[@]}"; do
      if ! echo "$loaded_list" | grep -qi "$agent_label"; then
        missing_agents="$missing_agents $agent_label"
      fi
    done
    check 6 "Known LaunchAgents loaded" "WARN" \
      "test -z '${missing_agents}'"
  else
    skip 6 "Known LaunchAgents loaded" "no known agents to check"
  fi
else
  skip 6 "Known LaunchAgents loaded" "run as agent to check"
fi

# 10. API tokens rotated from defaults
if [[ "$USER_TYPE" == "agent" ]] && [[ -d "$WORKSPACE_DIR" ]]; then
  check 6 "No default/placeholder API tokens" "WARN" \
    "! grep -rE 'YOUR_API_KEY|CHANGEME|TODO|REPLACE_ME|sk-xxx|your-api-key' '$WORKSPACE_DIR' 2>/dev/null | grep -v node_modules | grep -q ."
else
  skip 6 "No default/placeholder API tokens" "run as agent to check"
fi

# ─── Phase 7: Ongoing Operations ─────────────────────────────────────────────

phase_header 7 "Ongoing Operations"

# 1. Cron jobs exist for agent user
if [[ "$USER_TYPE" == "agent" ]]; then
  cron_output="$(crontab -l 2>/dev/null || true)"
  if [[ -n "$cron_output" ]]; then
    check 7 "Cron jobs configured" "WARN" \
      "test -n '$cron_output'"

    # 2. Cron uses absolute paths to node
    check 7 "Cron uses absolute paths to node" "FAIL" \
      "! echo '$cron_output' | grep 'node ' | grep -v '/.*node ' | grep -q 'node '"
  else
    skip 7 "Cron jobs configured" "no crontab for $CURRENT_USER"
    skip 7 "Cron uses absolute paths to node" "no crontab"
  fi
else
  skip 7 "Cron jobs configured" "run as agent to check"
  skip 7 "Cron uses absolute paths to node" "run as agent to check"
fi

# 3. Log directory exists and has recent files
check 7 "Log directory exists" "WARN" \
  "test -d '$LOG_DIR' || mkdir -p '$LOG_DIR'"

# Check for any log files modified in last 7 days
if [[ -d "$LOG_DIR" ]]; then
  recent_logs="$(find "$LOG_DIR" -name '*.log' -mtime -7 2>/dev/null | wc -l | tr -d ' ')"
  info 7 "Recent log files (last 7 days)" "$recent_logs"
fi

# 4. Refill cron job (if SAFE_ENABLED)
if [[ "$SAFE_ENABLED" == "true" ]] && [[ "$USER_TYPE" == "agent" ]]; then
  cron_output="$(crontab -l 2>/dev/null || true)"
  check 7 "Safe refill cron job exists" "WARN" \
    "echo '$cron_output' | grep -q 'refill'"
else
  skip 7 "Safe refill cron job exists" "SAFE_ENABLED=false or not running as agent"
fi

# 5. Last log file timestamps
if [[ -d "$LOG_DIR" ]]; then
  last_log="$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)"
  if [[ -n "${last_log:-}" ]]; then
    last_log_date="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$last_log" 2>/dev/null || echo "unknown")"
    info 7 "Last validation log" "$last_log_date"
  fi
fi

# 6. Uptime
uptime_str="$(uptime 2>/dev/null | sed 's/.*up /up /' | sed 's/,.*//')"
info 7 "System uptime" "$uptime_str"

# ─── Score calculation ─────────────────────────────────────────────────────────

total_scored=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
if [[ $total_scored -gt 0 ]]; then
  # Score = (PASS * 100 + WARN * 50) / (total_scored * 100) * 100
  score_numerator=$(( (PASS_COUNT * 100 + WARN_COUNT * 50) * 100 ))
  score_denominator=$(( total_scored * 100 ))
  SCORE=$(( score_numerator / score_denominator ))
else
  SCORE=100
fi

if [[ $SCORE -ge 95 ]]; then
  GRADE="Excellent"
elif [[ $SCORE -ge 85 ]]; then
  GRADE="Good"
elif [[ $SCORE -ge 70 ]]; then
  GRADE="Needs attention"
else
  GRADE="Critical"
fi

# ─── Summary output ───────────────────────────────────────────────────────────

if [[ "$OUTPUT_JSON" != "true" ]]; then
  printf '\n%b=== Summary ===%b\n' "$BOLD" "$RESET"
  printf "  ${GREEN}Passed: %d${RESET}  ${RED}Failed: %d${RESET}  ${YELLOW}Warnings: %d${RESET}  ${CYAN}Skipped: %d${RESET}\n" \
    "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$SKIP_COUNT"
  printf '  Score: %d/100 (%s)\n' "$SCORE" "$GRADE"
fi

# ─── Write log files ─────────────────────────────────────────────────────────

# Human-readable log
LOG_FILE="$LOG_DIR/validate-${TIMESTAMP_FILE}.log"
{
  printf 'Mac Mini Agent Setup Validator\n'
  printf 'Run: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'User: %s (%s)\n' "$CURRENT_USER" "$USER_TYPE"
  printf 'Host: %s\n' "$HOSTNAME"
  printf 'Score: %d/100 (%s)\n\n' "$SCORE" "$GRADE"
  printf 'Passed: %d  Failed: %d  Warnings: %d  Skipped: %d\n\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$SKIP_COUNT"
  # Write the full checks JSON for reference
  printf 'Checks (JSON):\n%s\n' "$CHECKS_JSON"
} > "$LOG_FILE"

# Machine-readable JSON log
JSON_FILE="$LOG_DIR/validate-${TIMESTAMP_FILE}.json"
cat > "$JSON_FILE" <<JSONEOF
{
  "timestamp": "${TIMESTAMP}",
  "hostname": "${HOSTNAME}",
  "user": "${CURRENT_USER}",
  "user_type": "${USER_TYPE}",
  "macos_version": "${os_version}",
  "hardware": "${hw_model}",
  "chip": "${hw_chip}",
  "ram": "${hw_ram}",
  "score": ${SCORE},
  "grade": "${GRADE}",
  "summary": {
    "pass": ${PASS_COUNT},
    "fail": ${FAIL_COUNT},
    "warn": ${WARN_COUNT},
    "skip": ${SKIP_COUNT}
  },
  "checks": ${CHECKS_JSON}
}
JSONEOF

if [[ "$OUTPUT_JSON" == "true" ]]; then
  cat "$JSON_FILE"
else
  printf '\n  Logs written to:\n'
  printf '    %s\n' "$LOG_FILE"
  printf '    %s\n' "$JSON_FILE"
fi

# Exit with non-zero if any failures
if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
