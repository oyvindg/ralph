#!/usr/bin/env bash
# =============================================================================
# After Step Hook
# =============================================================================
#
# Runs after each step completes (after quality-gate passes).
# Use for: logging, metrics, notifications, cleanup.
#
# Note: quality-gate is called by core BEFORE after-step.
# This hook is for post-quality-gate actions.
#
# Exit codes:
#   0 = success
#   1 = failure (stops session)
#
# Environment variables:
#   RALPH_SESSION_ID, RALPH_SESSION_DIR, RALPH_WORKSPACE
#   RALPH_STEP, RALPH_STEPS, RALPH_STEP_EXIT_CODE
#   RALPH_RESPONSE_FILE, RALPH_ENGINE_LOG
#   RALPH_DRY_RUN
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

STEP="${RALPH_STEP:-?}"
STEPS="${RALPH_STEPS:-?}"
SESSION_DIR="${RALPH_SESSION_DIR:-}"
RESPONSE_FILE="${RALPH_RESPONSE_FILE:-}"
DRY_RUN="${RALPH_DRY_RUN:-0}"
IS_VERBOSE="${RALPH_VERBOSE:-0}"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/log.sh"
else
  ralph_log() { echo "[$2] $3"; }
  ralph_event() { :; }
fi
if [[ -f "${HOOKS_DIR}/../lib/checkpoint.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/checkpoint.sh"
fi

# Returns success when verbose logging is enabled.
is_verbose() {
  case "${IS_VERBOSE}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Logs INFO messages only in verbose mode.
log_info_verbose() {
  local message="$1"
  is_verbose || return 0
  ralph_log "INFO" "after-step" "${message}"
}

# =============================================================================
# Logging
# =============================================================================

log_step_completion() {
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  ralph_log "INFO" "after-step" "Step ${STEP}/${STEPS} completed at ${timestamp}"

  # Log response summary
  if [[ -f "${RESPONSE_FILE}" ]]; then
    local lines words
    lines=$(wc -l < "${RESPONSE_FILE}")
    words=$(wc -w < "${RESPONSE_FILE}")
    log_info_verbose "Response: ${lines} lines, ${words} words"
    ralph_event "after_step" "ok" "step=${STEP} lines=${lines} words=${words}"
  fi
}

# =============================================================================
# Git Commit (optional)
# =============================================================================

maybe_commit() {
  # Only commit if there are changes
  if ! git -C "${RALPH_WORKSPACE}" diff --quiet 2>/dev/null; then
    log_info_verbose "Changes detected, could auto-commit here"
    # Uncomment to enable auto-commit:
    # git -C "${RALPH_WORKSPACE}" add -A
    # git -C "${RALPH_WORKSPACE}" commit -m "Ralph step ${STEP}: auto-commit"
  fi
}

create_step_checkpoint() {
  if [[ "${RALPH_CHECKPOINT_ENABLED:-1}" != "1" ]] || [[ "${RALPH_CHECKPOINT_PER_STEP:-1}" != "1" ]]; then
    return 0
  fi
  command -v checkpoint_create >/dev/null 2>&1 || return 0
  [[ -n "${SESSION_DIR}" ]] || return 0

  local cp_path
  cp_path="$(checkpoint_create \
    "${RALPH_WORKSPACE}" \
    "${SESSION_DIR}" \
    "step_${STEP}" \
    "${STEP}" \
    "${RALPH_PLAN_FILE:-}" \
    "${RALPH_TICKET:-}" || true)"
  [[ -n "${cp_path}" ]] && log_info_verbose "Checkpoint created: ${cp_path}"
}

# =============================================================================
# Dry-Run
# =============================================================================

run_dry() {
  echo "[after-step] === DRY-RUN ==="
  echo "[after-step] Step ${STEP}/${STEPS}"
  if is_verbose; then
    echo ""
    echo "[after-step] Would do:"
    echo "  - Log step completion"
    echo "  - Record response metrics"
    echo "  - Check for uncommitted changes"
    echo ""
  fi

  # Show simulated metrics
  if is_verbose && [[ -f "${RESPONSE_FILE}" ]]; then
    local lines words bytes
    lines=$(wc -l < "${RESPONSE_FILE}")
    words=$(wc -w < "${RESPONSE_FILE}")
    bytes=$(wc -c < "${RESPONSE_FILE}")
    echo "[after-step] Response metrics:"
    echo "  - Lines: ${lines}"
    echo "  - Words: ${words}"
    echo "  - Bytes: ${bytes}"
  fi

  if is_verbose; then
    echo ""
    echo "[after-step] DRY-RUN: Complete"
  fi
  return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
  # Dry-run mode
  if [[ "${DRY_RUN}" == "1" ]]; then
    run_dry
    exit 0
  fi

  log_step_completion

  # Optional filesystem checkpoint snapshot
  create_step_checkpoint || true

  # Optional: auto-commit changes
  # maybe_commit

  log_info_verbose "Done"
  exit 0
}

main "$@"
