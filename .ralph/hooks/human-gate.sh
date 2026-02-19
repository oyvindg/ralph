#!/usr/bin/env bash
# Human approval guard for session/step progression.
#
# Environment:
#   RALPH_HUMAN_GUARD=0|1          Enable/disable (default: 0)
#   RALPH_HUMAN_GUARD_STAGE        session|step (default: step)
#   RALPH_HUMAN_GUARD_ASSUME_YES=1 Auto-approve (for CI)
#
# Exit codes:
#   0 = approved / skipped
#   1 = rejected

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/log.sh"
fi

ENABLED="${RALPH_HUMAN_GUARD:-0}"
STAGE="${RALPH_HUMAN_GUARD_STAGE:-step}"
ASSUME_YES="${RALPH_HUMAN_GUARD_ASSUME_YES:-0}"

if [[ "${ENABLED}" != "1" ]]; then
  command -v ralph_log >/dev/null 2>&1 && ralph_log "INFO" "human-gate" "disabled; continuing"
  exit 0
fi

if [[ "${ASSUME_YES}" == "1" ]]; then
  command -v ralph_log >/dev/null 2>&1 && ralph_log "INFO" "human-gate" "assume-yes enabled; approved"
  command -v ralph_event >/dev/null 2>&1 && ralph_event "human_gate" "approved" "assume-yes"
  command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "human-gate" "approved" "assume-yes:${STAGE}"
  exit 0
fi

if [[ ! -t 0 ]]; then
  command -v ralph_log >/dev/null 2>&1 && ralph_log "WARN" "human-gate" "non-interactive shell; rejected"
  command -v ralph_event >/dev/null 2>&1 && ralph_event "human_gate" "rejected" "non-interactive shell"
  command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "human-gate" "rejected" "non-interactive:${STAGE}"
  exit 1
fi

prompt="Approve this ${STAGE} to continue? [y/N]: "
if [[ "${STAGE}" == "session" ]]; then
  prompt="Approve starting session ${RALPH_SESSION_ID:-}? [y/N]: "
fi

read -r -p "${prompt}" answer
case "${answer}" in
  y|Y|yes|YES)
    command -v ralph_log >/dev/null 2>&1 && ralph_log "INFO" "human-gate" "approved ${STAGE}"
    command -v ralph_event >/dev/null 2>&1 && ralph_event "human_gate" "approved" "${STAGE}"
    command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "human-gate" "approved" "${STAGE}"
    exit 0
    ;;
  *)
    command -v ralph_log >/dev/null 2>&1 && ralph_log "WARN" "human-gate" "rejected ${STAGE}"
    command -v ralph_event >/dev/null 2>&1 && ralph_event "human_gate" "rejected" "${STAGE}"
    command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "human-gate" "rejected" "${STAGE}"
    exit 1
    ;;
esac
