#!/usr/bin/env bash
# Workspace state helpers for Ralph core.
set -euo pipefail

# Resolves workspace root for state operations.
state_workspace_root() {
  if [[ -n "${ROOT:-}" ]]; then
    printf '%s\n' "${ROOT}"
    return 0
  fi
  if [[ -n "${RALPH_WORKSPACE:-}" ]]; then
    printf '%s\n' "${RALPH_WORKSPACE}"
    return 0
  fi
  pwd
}

# Returns path to workspace state file.
state_file_path() {
  local root
  root="$(state_workspace_root)"
  printf '%s' "${root}/.ralph/state.json"
}

# Reads last selected plan path from state file.
state_get_last_plan() {
  local state_file
  state_file="$(state_file_path)"
  [[ -f "${state_file}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.last_plan_file // empty' "${state_file}" 2>/dev/null || true
}

# Reads last selected workflow type from state file.
state_get_workflow_type() {
  local state_file
  state_file="$(state_file_path)"
  [[ -f "${state_file}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.workflow.type // empty' "${state_file}" 2>/dev/null || true
}

# Converts absolute plan path under ROOT to workspace-relative path.
state_plan_rel_path() {
  local plan_path="${1:-}"
  local root
  root="$(state_workspace_root)"
  if [[ "${plan_path}" == "${root}/"* ]]; then
    printf '%s\n' "${plan_path#${root}/}"
    return 0
  fi
  printf '%s\n' ""
}

# Converts state-stored path (relative preferred) to absolute path under ROOT.
state_plan_abs_path() {
  local stored="${1:-}"
  local root
  root="$(state_workspace_root)"
  [[ -z "${stored}" ]] && return 0
  stored="${stored/#\~/$HOME}"
  if [[ "${stored}" == /* ]]; then
    printf '%s\n' "${stored}"
    return 0
  fi
  printf '%s\n' "${root}/${stored}"
}

# Resolves actor identity for state entries.
state_actor_identity() {
  local root selected_by
  root="$(state_workspace_root)"
  selected_by="$(git -C "${root}" config --get user.name 2>/dev/null || true)"
  [[ -z "${selected_by}" ]] && selected_by="$(git -C "${root}" config --get user.email 2>/dev/null || true)"
  [[ -z "${selected_by}" ]] && selected_by="${USER:-$(id -un 2>/dev/null || echo unknown)}"
  printf '%s\n' "${selected_by}"
}

# Persists last selected plan path to workspace state file.
state_set_last_plan() {
  local plan_path="$1"
  local plan_rel_path state_file tmp now selected_by
  plan_rel_path="$(state_plan_rel_path "${plan_path}")"
  [[ -n "${plan_rel_path}" ]] || return 0

  state_file="$(state_file_path)"
  mkdir -p "$(dirname "${state_file}")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  selected_by="$(state_actor_identity)"
  tmp="${state_file}.tmp"

  if command -v jq >/dev/null 2>&1 && [[ -f "${state_file}" ]]; then
    jq --arg plan "${plan_rel_path}" --arg now "${now}" --arg by "${selected_by}" \
      '.last_plan_file = $plan | .last_selected_at = $now | .last_selected_by = $by' \
      "${state_file}" > "${tmp}" 2>/dev/null || true
  fi

  if [[ ! -f "${tmp}" ]]; then
    cat > "${tmp}" <<JSON
{
  "last_plan_file": "${plan_rel_path}",
  "last_selected_at": "${now}",
  "last_selected_by": "${selected_by}"
}
JSON
  fi
  mv "${tmp}" "${state_file}"
}

# Persists selected workflow type to workspace state file.
state_set_workflow_type() {
  local workflow_type="$1"
  local source="${2:-wizard}"
  local details="${3:-}"
  local state_file tmp now selected_by

  [[ -n "${workflow_type}" ]] || return 0
  state_file="$(state_file_path)"
  mkdir -p "$(dirname "${state_file}")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  selected_by="$(state_actor_identity)"
  tmp="${state_file}.tmp"

  if command -v jq >/dev/null 2>&1 && [[ -f "${state_file}" ]]; then
    jq \
      --arg ts "${now}" \
      --arg type "${workflow_type}" \
      --arg by "${selected_by}" \
      --arg source "${source}" \
      --arg details "${details}" \
      '
      .workflow = {
        type: $type,
        selected_at: $ts,
        selected_by: $by,
        source: $source,
        details: $details
      }
      ' "${state_file}" > "${tmp}" 2>/dev/null || true
  fi

  if [[ ! -f "${tmp}" ]]; then
    cat > "${tmp}" <<JSON
{
  "workflow": {
    "type": "${workflow_type}",
    "selected_at": "${now}",
    "selected_by": "${selected_by}",
    "source": "${source}",
    "details": "${details}"
  }
}
JSON
  fi
  mv "${tmp}" "${state_file}"
}
# Appends a hook/user choice entry to state.json for auditability.
# Usage: state_record_choice "<source>" "<hook>" "<choice>" ["details"]
state_record_choice() {
  local source="${1:-hook}"
  local hook_name="${2:-unknown}"
  local choice="${3:-unknown}"
  local details="${4:-}"
  local state_file tmp now selected_by

  state_file="$(state_file_path)"
  mkdir -p "$(dirname "${state_file}")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  selected_by="$(state_actor_identity)"
  tmp="${state_file}.tmp"

  if command -v jq >/dev/null 2>&1 && [[ -f "${state_file}" ]]; then
    jq \
      --arg ts "${now}" \
      --arg source "${source}" \
      --arg hook "${hook_name}" \
      --arg choice "${choice}" \
      --arg details "${details}" \
      --arg by "${selected_by}" \
      --arg session_id "${RALPH_SESSION_ID:-}" \
      --arg step "${RALPH_STEP:-}" \
      '
      .hook_choices = ((.hook_choices // []) + [{
        timestamp: $ts,
        source: $source,
        hook: $hook,
        choice: $choice,
        details: $details,
        selected_by: $by,
        session_id: $session_id,
        step: (if $step == "" then null else $step end)
      }] | if length > 300 then .[-300:] else . end)
      | .last_choice_at = $ts
      | .last_choice_by = $by
      ' "${state_file}" > "${tmp}" 2>/dev/null || true
  fi

  if [[ ! -f "${tmp}" ]]; then
    cat > "${tmp}" <<JSON
{
  "hook_choices": [
    {
      "timestamp": "${now}",
      "source": "${source}",
      "hook": "${hook_name}",
      "choice": "${choice}",
      "details": "${details}",
      "selected_by": "${selected_by}",
      "session_id": "${RALPH_SESSION_ID:-}",
      "step": "${RALPH_STEP:-}"
    }
  ],
  "last_choice_at": "${now}",
  "last_choice_by": "${selected_by}"
}
JSON
  fi
  mv "${tmp}" "${state_file}"
}
