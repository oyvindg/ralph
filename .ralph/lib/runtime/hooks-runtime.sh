#!/usr/bin/env bash
# Hook runtime helpers for Ralph orchestrator.
set -euo pipefail

run_hook() {
  local hook_name="$1"
  local step="${2:-}"
  local step_exit_code="${3:-}"
  local hook_depth="${RALPH_HOOK_DEPTH:-0}"

  local hook_path
  hook_path=$(resolve_hook "${hook_name}")

  export RALPH_SESSION_ID="${session_id}"
  export RALPH_SESSION_DIR="${session_dir}"
  export RALPH_WORKSPACE="${ROOT}"
  export RALPH_STEPS="${MAX_STEPS}"
  export RALPH_PROMPT_FILE="${prompt_input_file:-}"
  export RALPH_RESPONSE_FILE="${last_response:-}"
  export RALPH_PLAN_FILE="$(plan_json_path)"
  export RALPH_GUIDE_FILE="${GUIDE_PATH:-}"
  export RALPH_PLAN_CONTEXT_FILE="${PLAN_CONTEXT_FILE:-}"
  export RALPH_ENGINE="${ACTIVE_ENGINE:-${RALPH_ENGINE:-codex}}"
  export RALPH_MODEL="${ACTIVE_MODEL:-${MODEL:-}}"
  export RALPH_GOAL="${GOAL}"
  export RALPH_TICKET="${TICKET:-}"
  export RALPH_SOURCE_CONTROL_ENABLED="${RALPH_SOURCE_CONTROL_ENABLED}"
  export RALPH_SOURCE_CONTROL_BACKEND="${RALPH_SOURCE_CONTROL_BACKEND}"
  export RALPH_SOURCE_CONTROL_ALLOW_COMMITS="${RALPH_SOURCE_CONTROL_ALLOW_COMMITS}"
  export RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION="${RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION}"
  export RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE="${RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE}"
  export RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH="${RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH}"
  export RALPH_ISSUES_PROVIDERS="${ISSUES_PROVIDERS}"
  export RALPH_CHECKPOINT_ENABLED="${CHECKPOINT_ENABLED}"
  export RALPH_CHECKPOINT_PER_STEP="${CHECKPOINT_PER_STEP}"
  export RALPH_TIMEOUT="${TIMEOUT_SECONDS:-0}"
  export RALPH_DRY_RUN="${DRY_RUN}"
  export RALPH_DRY_RUN_EXECUTE_TESTS="${DRY_RUN}"
  export RALPH_PROJECT_DIR="${RALPH_PROJECT_DIR:-}"
  export RALPH_GLOBAL_DIR="${RALPH_GLOBAL_DIR:-}"
  export RALPH_HUMAN_GUARD="${HUMAN_GUARD}"
  export RALPH_HUMAN_GUARD_ASSUME_YES="${HUMAN_GUARD_ASSUME_YES}"
  export RALPH_HUMAN_GUARD_SCOPE="${HUMAN_GUARD_SCOPE}"
  export RALPH_LANG="${LANG_CODE:-en}"
  export RALPH_VERBOSE="${VERBOSE}"
  export RALPH_WORKFLOW_TYPE="${RALPH_WORKFLOW_TYPE:-$(state_get_workflow_type || true)}"
  export RALPH_HOOKS_FILE="${HOOKS_JSON_PATH:-}"
  export RALPH_TASKS_FILE="${TASKS_JSON_PATH:-}"

  if [[ -n "${step}" ]]; then
    export RALPH_STEP="${step}"
    export RALPH_ENGINE_LOG="${session_dir}/engine_${step}.md"
    export RALPH_STEP_MARKER="${session_dir}/.step_${step}.start"
    export RALPH_CHANGE_LOG_FILE="${session_dir}/changes_step_${step}.md"
  fi

  if [[ -n "${step_exit_code}" ]]; then
    export RALPH_STEP_EXIT_CODE="${step_exit_code}"
  fi

  local rc=0
  if ! run_json_hook_commands "${hook_name}" "before-system" "${step}" "${step_exit_code}"; then
    return 1
  fi

  if [[ -n "${hook_path}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "${C_MAGENTA}[${hook_name}]${C_RESET} ${C_DIM}(dry-run)${C_RESET}"
    else
      echo "${C_MAGENTA}[${hook_name}]${C_RESET}"
    fi

    set +e
    RALPH_HOOK_DEPTH="$((hook_depth + 1))" "${hook_path}"
    rc=$?
    set -e
    [[ "${rc}" -ne 0 ]] && return "${rc}"
  fi

  if ! run_json_hook_commands "${hook_name}" "system" "${step}" "${step_exit_code}"; then
    return 1
  fi

  if ! run_json_hook_commands "${hook_name}" "after-system" "${step}" "${step_exit_code}"; then
    return 1
  fi

  return 0
}

run_required_hook() {
  local hook_name="$1"
  local step="${2:-}"
  local step_exit_code="${3:-}"
  local rc=0

  set +e
  run_hook "${hook_name}" "${step}" "${step_exit_code}"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    exit "${rc}"
  fi
}
