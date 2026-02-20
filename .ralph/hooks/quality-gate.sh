#!/usr/bin/env bash
# =============================================================================
# Quality Gate Hook
# =============================================================================
#
# Validates AI output before proceeding to next step.
# Calls testing.sh hook for test execution.
#
# Exit codes:
#   0 = success, continue
#   1 = hard failure, stop session
#   2 = replan required
#   3 = retry current step
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
RESPONSE_FILE="${RALPH_RESPONSE_FILE:-}"
WORKSPACE="${RALPH_WORKSPACE:-.}"
DRY_RUN="${RALPH_DRY_RUN:-0}"
SESSION_DIR="${RALPH_SESSION_DIR:-}"
GUIDE_FILE="${RALPH_GUIDE_FILE:-}"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/log.sh"
else
  ralph_log() { echo "[$2] $3"; }
  ralph_event() { :; }
fi

# =============================================================================
# Call Sub-Hook
# =============================================================================

call_hook() {
  local hook_name="$1"
  local hook_path="${HOOKS_DIR}/${hook_name}.sh"

  if [[ -x "${hook_path}" ]]; then
    ralph_log "INFO" "quality-gate" "Calling: ${hook_name}"
    RALPH_HOOK_DEPTH="$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))" "${hook_path}"
    return $?
  else
    ralph_log "INFO" "quality-gate" "Hook not found: ${hook_name}"
    return 0
  fi
}

# =============================================================================
# Response Checks
# =============================================================================

check_response() {
  ralph_log "INFO" "quality-gate" "Checking response"

  # Check exists
  if [[ ! -f "${RESPONSE_FILE}" ]]; then
    ralph_log "ERROR" "quality-gate" "Response file missing"
    return 1
  fi

  # Check not empty
  if [[ ! -s "${RESPONSE_FILE}" ]]; then
    ralph_log "ERROR" "quality-gate" "Response is empty"
    return 1
  fi

  # Check size
  local size
  size=$(wc -c < "${RESPONSE_FILE}")
  ralph_log "INFO" "quality-gate" "Response: ${size} bytes"

  # Warn if very short
  if [[ "${size}" -lt 50 ]]; then
    ralph_log "WARN" "quality-gate" "Response very short"
  fi

  # Check for error markers
  if grep -qi "error:\|failed:\|exception:\|traceback:" "${RESPONSE_FILE}" 2>/dev/null; then
    ralph_log "WARN" "quality-gate" "Response may contain errors"
  fi

  ralph_log "INFO" "quality-gate" "Response check: OK"
  return 0
}

# Ensures guide file remains unchanged during the session.
# If changed, restores from snapshot and signals failure.
enforce_guide_read_only() {
  [[ -n "${GUIDE_FILE}" ]] || return 0
  [[ -n "${SESSION_DIR}" ]] || return 0

  local snapshot_file="${SESSION_DIR}/.guide_snapshot"
  [[ -f "${snapshot_file}" ]] || return 0

  if [[ ! -f "${GUIDE_FILE}" ]]; then
    cp -a "${snapshot_file}" "${GUIDE_FILE}"
    ralph_log "WARN" "quality-gate" "Guide file was removed and has been restored: ${GUIDE_FILE}"
    ralph_event "guide_guard" "restored" "guide removed and restored from snapshot"
    return 1
  fi

  if ! cmp -s "${snapshot_file}" "${GUIDE_FILE}"; then
    cp -a "${snapshot_file}" "${GUIDE_FILE}"
    ralph_log "WARN" "quality-gate" "Guide file is read-only; reverted changes: ${GUIDE_FILE}"
    ralph_event "guide_guard" "reverted" "guide modifications were reverted"
    return 1
  fi
  return 0
}

# =============================================================================
# Dry-Run
# =============================================================================

run_dry() {
  echo "[quality-gate] === DRY-RUN ==="
  ralph_log "INFO" "quality-gate" "Step ${STEP}/${STEPS}"
  ralph_event "quality_gate" "started" "step ${STEP}/${STEPS}"
  echo ""

  echo "[quality-gate] Checks:"
  echo "  - Response exists and has content"
  echo "  - Response size is reasonable"
  echo "  - No error markers in response"
  echo "  - Run testing.sh hook"
  echo ""

  # Simulate response check
  if [[ -f "${RESPONSE_FILE}" ]]; then
    local size
    size=$(wc -c < "${RESPONSE_FILE}" 2>/dev/null || echo 0)
    echo "[quality-gate] [x] Response: ${size} bytes"
  else
    echo "[quality-gate] [ ] Response: missing"
  fi

  # Call testing hook in dry-run
  echo ""
  local test_rc=0
  set +e
  call_hook "testing"
  test_rc=$?
  set -e
  if [[ "${test_rc}" -eq 130 || "${test_rc}" -eq 143 ]]; then
    ralph_log "WARN" "quality-gate" "Interrupted during testing hook"
    return 130
  fi

  echo ""
  echo "[quality-gate] DRY-RUN: Simulated pass"
  return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "[quality-gate] Step ${STEP}/${STEPS}"

  # Dry-run mode
  if [[ "${DRY_RUN}" == "1" ]]; then
    run_dry
    exit 0
  fi

  local failed=0

  # Check response
  check_response || ((failed++)) || true

  # Enforce immutable guide input (if provided via --guide)
  enforce_guide_read_only || ((failed++)) || true

  # Run tests
  local test_rc=0
  set +e
  call_hook "testing"
  test_rc=$?
  set -e
  if [[ "${test_rc}" -eq 130 || "${test_rc}" -eq 143 ]]; then
    ralph_log "WARN" "quality-gate" "Interrupted during testing hook"
    ralph_event "quality_gate" "interrupted" "testing hook interrupted"
    exit 130
  fi
  [[ "${test_rc}" -ne 0 ]] && ((failed++)) || true

  # Result
  if [[ "${failed}" -gt 0 ]]; then
    ralph_log "ERROR" "quality-gate" "FAILED: ${failed} check(s) failed"
    ralph_event "quality_gate" "failed" "${failed} checks failed"
    exit 3  # Retry step
  fi

  # Optional human approval before accepting step
  local scope
  scope="${RALPH_HUMAN_GUARD_SCOPE:-both}"
  if [[ "${scope}" == "both" || "${scope}" == "step" ]]; then
    export RALPH_HUMAN_GUARD_STAGE="step"
    if ! call_hook "human-gate"; then
      ralph_log "WARN" "quality-gate" "Step rejected by human gate"
      ralph_event "quality_gate" "rejected" "human gate rejected step"
      exit 1
    fi
  else
    ralph_log "INFO" "quality-gate" "Human guard skipped at step stage (scope=${scope})"
  fi

  ralph_log "INFO" "quality-gate" "Passed"
  ralph_event "quality_gate" "passed" "all checks passed"
  exit 0
}

main "$@"
