#!/usr/bin/env bash
# Shared logging helpers for Ralph hooks.
set -euo pipefail

RALPH_HOOK_LOG_FILE="${RALPH_SESSION_DIR:-}/hooks.log"
RALPH_EVENT_LOG_FILE="${RALPH_SESSION_DIR:-}/events.jsonl"
RALPH_LOG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${RALPH_LOG_LIB_DIR}/state.sh" ]]; then
  # shellcheck disable=SC1091
  source "${RALPH_LOG_LIB_DIR}/state.sh"
fi

_ralph_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_ralph_indent() {
  local depth="${RALPH_HOOK_DEPTH:-0}"
  local indent=""
  local i=0
  while [[ "${i}" -lt "${depth}" ]]; do
    indent="${indent}  "
    ((i++)) || true
  done
  printf '%s' "${indent}"
}

ralph_log() {
  local level="$1"
  local component="$2"
  local message="$3"
  local ts
  local indent
  ts="$(_ralph_ts)"
  indent="$(_ralph_indent)"

  echo "${indent}[${component}] ${message}"

  if [[ -n "${RALPH_SESSION_DIR:-}" ]]; then
    mkdir -p "${RALPH_SESSION_DIR}"
    printf '%s [%s] [%s] %s%s\n' "${ts}" "${level}" "${component}" "${indent}" "${message}" >> "${RALPH_HOOK_LOG_FILE}"
  fi
}

ralph_event() {
  local event_type="$1"
  local status="$2"
  local details="${3:-}"
  local ts
  ts="$(_ralph_ts)"

  [[ -z "${RALPH_SESSION_DIR:-}" ]] && return 0
  mkdir -p "${RALPH_SESSION_DIR}"

  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg ts "${ts}" \
      --arg type "${event_type}" \
      --arg status "${status}" \
      --arg details "${details}" \
      --arg session_id "${RALPH_SESSION_ID:-}" \
      --arg step "${RALPH_STEP:-}" \
      --arg workspace "${RALPH_WORKSPACE:-}" \
      '{timestamp:$ts,type:$type,status:$status,details:$details,session_id:$session_id,step:$step,workspace:$workspace}' \
      >> "${RALPH_EVENT_LOG_FILE}"
  else
    printf '{"timestamp":"%s","type":"%s","status":"%s","details":"%s","session_id":"%s","step":"%s","workspace":"%s"}\n' \
      "${ts}" "${event_type}" "${status}" "${details}" "${RALPH_SESSION_ID:-}" "${RALPH_STEP:-}" "${RALPH_WORKSPACE:-}" \
      >> "${RALPH_EVENT_LOG_FILE}"
  fi
}

# Persists a user/hook choice to workspace state when state helpers are available.
# Usage: ralph_state_choice "<hook>" "<choice>" ["details"]
ralph_state_choice() {
  local hook_name="$1"
  local choice="$2"
  local details="${3:-}"
  command -v state_record_choice >/dev/null 2>&1 || return 0
  state_record_choice "hook" "${hook_name}" "${choice}" "${details}" || true
}
