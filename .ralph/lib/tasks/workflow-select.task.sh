#!/usr/bin/env bash
# Persists selected workflow profile for empty workspace bootstrap.
set -euo pipefail

TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${TASK_DIR}/.." && pwd)"

if [[ -f "${LIB_DIR}/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/log.sh"
else
  ralph_log() { echo "[$2] $3"; }
  ralph_event() { :; }
fi

if [[ -f "${LIB_DIR}/state.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/state.sh"
fi

# Validates workflow values allowed by Ralph.
is_valid_workflow() {
  case "${1:-}" in
    coding|project-management|finance|non-code) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local workflow_type="${1:-}"
  if ! is_valid_workflow "${workflow_type}"; then
    ralph_log "WARN" "task.workflow-select" "Invalid workflow: ${workflow_type:-<empty>}"
    exit 1
  fi

  export RALPH_WORKFLOW_TYPE="${workflow_type}"
  if command -v state_set_workflow_type >/dev/null 2>&1; then
    state_set_workflow_type "${workflow_type}" "hooks.json" "empty-workspace select"
  fi
  if command -v state_record_choice >/dev/null 2>&1; then
    state_record_choice "hooks.json" "before-session" "workflow-selected" "${workflow_type}"
  fi

  ralph_log "INFO" "task.workflow-select" "Workflow profile: ${workflow_type}"
  ralph_event "wizard" "selected" "workflow=${workflow_type}"
}

main "$@"
