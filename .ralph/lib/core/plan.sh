#!/usr/bin/env bash
# Plan state helpers for Ralph orchestrator.
set -euo pipefail

# Returns absolute plan file path, with default fallback.
plan_json_path() {
  if [[ -n "${PLAN_FILE_PATH}" ]]; then
    printf '%s' "${PLAN_FILE_PATH}"
  else
    printf '%s' "${ROOT}/.ralph/plans/plan.json"
  fi
}

# Returns success when a plan file currently exists.
plan_exists() {
  [[ -f "$(plan_json_path)" ]]
}

# Returns total number of plan steps.
get_step_count() {
  local plan_file
  plan_file="$(plan_json_path)"
  [[ -f "${plan_file}" ]] || { echo "0"; return; }
  jq -r '.steps | length' "${plan_file}" 2>/dev/null || echo "0"
}

# Returns number of pending plan steps.
get_pending_count() {
  local plan_file
  plan_file="$(plan_json_path)"
  [[ -f "${plan_file}" ]] || { echo "0"; return; }
  jq -r '[.steps[] | select(.status == "pending")] | length' "${plan_file}" 2>/dev/null || echo "0"
}

# Returns first pending step as JSON, or empty when none.
get_current_step() {
  local plan_file
  plan_file="$(plan_json_path)"
  [[ -f "${plan_file}" ]] || return
  jq -r 'first(.steps[] | select(.status == "pending")) | if . == null then empty else @json end' "${plan_file}" 2>/dev/null || true
}

# Returns id of current pending step.
get_current_step_id() {
  local step_json
  step_json="$(get_current_step)"
  [[ -z "${step_json}" ]] && return
  echo "${step_json}" | jq -r '.id' 2>/dev/null
}

# Returns description of current pending step.
get_current_step_description() {
  local step_json
  step_json="$(get_current_step)"
  [[ -z "${step_json}" ]] && return
  echo "${step_json}" | jq -r '.description' 2>/dev/null
}

# Returns acceptance criteria of current pending step.
get_current_step_acceptance() {
  local step_json
  step_json="$(get_current_step)"
  [[ -z "${step_json}" ]] && return
  echo "${step_json}" | jq -r '.acceptance' 2>/dev/null
}

# Updates step status and timestamps in plan file.
# Usage: update_step_status "step-id" "new-status" ["commit-hash"]
update_step_status() {
  local step_id="$1"
  local new_status="$2"
  local commit_hash="${3:-}"
  local plan_file now tmp_file

  plan_file="$(plan_json_path)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -f "${plan_file}" ]] || return 1
  tmp_file="${plan_file}.tmp"

  if [[ -n "${commit_hash}" ]]; then
    jq --arg id "${step_id}" --arg status "${new_status}" --arg commit "${commit_hash}" --arg now "${now}" \
      '.steps = [.steps[] | if .id == $id then .status = $status | .commit = $commit | .updated_at = $now | .completed_at = (if $status == "completed" then $now elif ($status == "pending" or $status == "in_progress") then null else .completed_at end) else . end]
       | .updated_at = $now' \
      "${plan_file}" > "${tmp_file}"
  else
    jq --arg id "${step_id}" --arg status "${new_status}" --arg now "${now}" \
      '.steps = [.steps[] | if .id == $id then .status = $status | .updated_at = $now | .completed_at = (if $status == "completed" then $now elif ($status == "pending" or $status == "in_progress") then null else .completed_at end) else . end]
       | .updated_at = $now' \
      "${plan_file}" > "${tmp_file}"
  fi

  mv "${tmp_file}" "${plan_file}"
}

# Returns plan goal text when available.
get_plan_goal() {
  local plan_file
  plan_file="$(plan_json_path)"
  [[ -f "${plan_file}" ]] || return
  jq -r '.goal // empty' "${plan_file}" 2>/dev/null
}

# Returns per-plan execution limit (0 means unlimited / not set).
get_plan_max_steps() {
  local plan_file
  plan_file="$(plan_json_path)"
  [[ -f "${plan_file}" ]] || { echo "0"; return; }
  jq -r 'if (.max_steps // 0) | type == "number" then (.max_steps // 0) else 0 end' "${plan_file}" 2>/dev/null || echo "0"
}

# Resets all structured plan steps to pending.
# Writes a timestamped backup and prints its path on success.
reset_plan_steps_to_pending() {
  local plan_file now backup tmp_file backup_dir backup_name plan_dir
  plan_file="$(plan_json_path)"
  [[ -f "${plan_file}" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  if ! jq -e '.steps | type == "array"' "${plan_file}" >/dev/null 2>&1; then
    # Non-structured plans are context files; nothing to reset.
    return 0
  fi

  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  plan_dir="$(dirname "${plan_file}")"
  backup_dir="${plan_dir}/.backups"
  mkdir -p "${backup_dir}"
  backup_name="$(basename "${plan_file}").bak.$(date +%Y%m%d_%H%M%S)"
  backup="${backup_dir}/${backup_name}"
  cp "${plan_file}" "${backup}"
  tmp_file="${plan_file}.tmp"

  jq --arg now "${now}" '
    .updated_at = $now
    | .steps = [
        .steps[]
        | .status = "pending"
        | .commit = null
        | .completed_at = null
        | .updated_at = $now
      ]
  ' "${plan_file}" > "${tmp_file}"
  mv "${tmp_file}" "${plan_file}"
  printf '%s\n' "${backup}"
}
