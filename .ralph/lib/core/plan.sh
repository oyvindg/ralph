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
  jq -r '.steps[] | select(.status == "pending") | @json' "${plan_file}" 2>/dev/null | head -n1
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
