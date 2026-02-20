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
ENABLED="${RALPH_HUMAN_GUARD:-0}"
STAGE="${RALPH_HUMAN_GUARD_STAGE:-step}"
ASSUME_YES="${RALPH_HUMAN_GUARD_ASSUME_YES:-0}"
ROOT="${RALPH_WORKSPACE:-$(pwd)}"
HOOKS_JSON_PATH="${RALPH_HOOKS_FILE:-}"
TASKS_JSON_PATH="${RALPH_TASKS_FILE:-}"

# Loads shared libs used by this hook (logging/parser).
load_libs() {
  if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOOKS_DIR}/../lib/log.sh"
  fi
  if [[ -f "${HOOKS_DIR}/../lib/core/hooks-parser.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOOKS_DIR}/../lib/core/hooks-parser.sh"
  fi
}

# Returns success when human gate is enabled.
is_gate_enabled() {
  [[ "${ENABLED}" == "1" ]]
}

# Returns success when approvals should be auto-accepted.
is_assume_yes() {
  [[ "${ASSUME_YES}" == "1" ]]
}

# Returns success when shell is interactive.
is_interactive_tty() {
  [[ -t 0 ]]
}

# Emits consistent approval/rejection telemetry.
emit_decision() {
  local decision="$1"
  local details="${2:-${STAGE}}"
  case "${decision}" in
    approved)
      command -v ralph_log >/dev/null 2>&1 && ralph_log "INFO" "human-gate" "approved ${details}"
      command -v ralph_event >/dev/null 2>&1 && ralph_event "human_gate" "approved" "${details}"
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "human-gate" "approved" "${details}"
      ;;
    rejected)
      command -v ralph_log >/dev/null 2>&1 && ralph_log "WARN" "human-gate" "rejected ${details}"
      command -v ralph_event >/dev/null 2>&1 && ralph_event "human_gate" "rejected" "${details}"
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "human-gate" "rejected" "${details}"
      ;;
  esac
}

# Runs hooks.jsonc-driven select for human gate when configured.
# Uses event: human-gate-confirm.system
run_configured_select() {
  command -v run_json_hook_commands >/dev/null 2>&1 || return 2
  [[ -n "${HOOKS_JSON_PATH}" && -f "${HOOKS_JSON_PATH}" ]] || return 2
  command -v jq >/dev/null 2>&1 || return 2
  command -v json_like_to_temp_file >/dev/null 2>&1 || return 2

  has_human_gate_select() {
    local hooks_file="$1"
    local normalized_hooks merged_hooks
    normalized_hooks="$(json_like_to_temp_file "${hooks_file}")" || return 1
    merged_hooks=""

    # When hooks.jsonc uses include(s), validate against merged view
    # so we do not incorrectly reject as missing-config.
    if command -v build_merged_hooks_json >/dev/null 2>&1; then
      merged_hooks="$(mktemp)"
      if build_merged_hooks_json "${hooks_file}" "${merged_hooks}" >/dev/null 2>&1; then
        rm -f "${normalized_hooks}"
        normalized_hooks="${merged_hooks}"
      else
        rm -f "${merged_hooks}" 2>/dev/null || true
      fi
    fi

    if jq -e '
      .["human-gate-confirm"]?.system as $node
      | if $node == null then false
        elif ($node|type) == "array" then ($node|length) > 0
        elif ($node|type) == "object" then (($node.commands // [])|length) > 0
        else false end
    ' "${normalized_hooks}" >/dev/null 2>&1; then
      rm -f "${normalized_hooks}"
      return 0
    fi
    rm -f "${normalized_hooks}"
    return 1
  }

  local active_hooks_path="${HOOKS_JSON_PATH}"
  if ! has_human_gate_select "${active_hooks_path}"; then
    return 2
  fi

  export RALPH_HUMAN_GUARD_STAGE="${STAGE}"
  HOOKS_JSON_PATH="${active_hooks_path}"
  run_json_hook_commands "human-gate-confirm" "system" "${RALPH_STEP:-}" "${RALPH_STEP_EXIT_CODE:-}"
}

# Main approval flow.
run_gate() {
  if ! is_gate_enabled; then
    command -v ralph_log >/dev/null 2>&1 && ralph_log "INFO" "human-gate" "disabled; continuing"
    return 0
  fi

  if is_assume_yes; then
    emit_decision "approved" "assume-yes:${STAGE}"
    return 0
  fi

  if ! is_interactive_tty; then
    emit_decision "rejected" "non-interactive:${STAGE}"
    return 1
  fi

  local rc=2
  run_configured_select || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    emit_decision "approved" "${STAGE}"
    return 0
  fi
  if [[ "${rc}" -eq 1 ]]; then
    emit_decision "rejected" "${STAGE}"
    return 1
  fi

  command -v ralph_log >/dev/null 2>&1 && ralph_log "ERROR" "human-gate" "missing hooks select config: human-gate-confirm.system"
  emit_decision "rejected" "missing-config:${STAGE}"
  return 1
}

main() {
  load_libs
  run_gate
}

main "$@"
