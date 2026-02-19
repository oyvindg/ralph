#!/usr/bin/env bash
# Workspace state helpers for Ralph core.
set -euo pipefail

# Returns path to workspace state file.
state_file_path() {
  printf '%s' "${ROOT}/.ralph/state.json"
}

# Reads last selected plan path from state file.
state_get_last_plan() {
  local state_file
  state_file="$(state_file_path)"
  [[ -f "${state_file}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.last_plan_file // empty' "${state_file}" 2>/dev/null || true
}

# Converts absolute plan path under ROOT to workspace-relative path.
state_plan_rel_path() {
  local plan_path="${1:-}"
  if [[ "${plan_path}" == "${ROOT}/"* ]]; then
    printf '%s\n' "${plan_path#${ROOT}/}"
    return 0
  fi
  printf '%s\n' ""
}

# Converts state-stored path (relative preferred) to absolute path under ROOT.
state_plan_abs_path() {
  local stored="${1:-}"
  [[ -z "${stored}" ]] && return 0
  stored="${stored/#\~/$HOME}"
  if [[ "${stored}" == /* ]]; then
    printf '%s\n' "${stored}"
    return 0
  fi
  printf '%s\n' "${ROOT}/${stored}"
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
  selected_by="$(git -C "${ROOT}" config --get user.name 2>/dev/null || true)"
  [[ -z "${selected_by}" ]] && selected_by="$(git -C "${ROOT}" config --get user.email 2>/dev/null || true)"
  [[ -z "${selected_by}" ]] && selected_by="${USER:-$(id -un 2>/dev/null || echo unknown)}"
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
