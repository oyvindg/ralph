#!/usr/bin/env bash
# Core configuration helpers for Ralph orchestrator.
set -euo pipefail

# Finds project and global .ralph directories.
find_ralph_dirs() {
  RALPH_GLOBAL_DIR="${HOME}/.ralph"

  local dir="${ROOT}"
  while [[ "${dir}" != "/" ]]; do
    if [[ -d "${dir}/.ralph" ]]; then
      RALPH_PROJECT_DIR="${dir}/.ralph"
      break
    fi
    dir="$(dirname "${dir}")"
  done
}

# Parses a simple TOML scalar value (string/number/bool) by key.
parse_toml_value() {
  local key="$1"
  local file="$2"
  [[ ! -f "${file}" ]] && return

  local value
  value="$(grep -E "^${key}[[:space:]]*=" "${file}" 2>/dev/null | head -n1 | sed 's/^[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)"
  if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "${value}"
}

# Parses a TOML array value by key (supports multi-line arrays).
parse_toml_array() {
  local key="$1"
  local file="$2"
  [[ ! -f "${file}" ]] && return

  local value items
  value="$(
    awk -v key="${key}" '
      BEGIN { in_array = 0 }
      $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        line = $0
        sub(/^[^=]*=/, "", line)
        print line
        if (line ~ /\]/) exit
        in_array = 1
        next
      }
      in_array == 1 {
        print $0
        if ($0 ~ /\]/) exit
      }
    ' "${file}" 2>/dev/null | tr '\n' ' '
  )"

  if [[ "${value}" =~ \[(.*)\] ]]; then
    items="${BASH_REMATCH[1]}"
    printf '%s' "${items}" | tr ',' '\n' | sed 's/^[[:space:]]*"//' | sed 's/"[[:space:]]*$//' | tr '\n' ' '
  fi
  return 0
}

# Loads and merges profile values (global first, project overrides).
load_profile() {
  local global_profile="${RALPH_GLOBAL_DIR}/profile.toml"
  local project_profile="${RALPH_PROJECT_DIR}/profile.toml"

  if [[ -f "${global_profile}" ]]; then
    PROFILE_STEPS=$(parse_toml_value "steps" "${global_profile}")
    [[ -z "${PROFILE_STEPS}" ]] && PROFILE_STEPS=$(parse_toml_value "iterations" "${global_profile}")
    PROFILE_ENGINE=$(parse_toml_value "engine" "${global_profile}")
    PROFILE_MODEL=$(parse_toml_value "model" "${global_profile}")
    PROFILE_TIMEOUT=$(parse_toml_value "timeout" "${global_profile}")
    PROFILE_SKIP_GIT_CHECK=$(parse_toml_value "skip_git_check" "${global_profile}")
    PROFILE_DISABLED_HOOKS=$(parse_toml_array "disabled" "${global_profile}")
    PROFILE_AUTHOR=$(parse_toml_value "author" "${global_profile}")
    PROFILE_PROJECT=$(parse_toml_value "project" "${global_profile}")
    PROFILE_HUMAN_GUARD=$(parse_toml_value "human_guard" "${global_profile}")
    PROFILE_HUMAN_GUARD_ASSUME_YES=$(parse_toml_value "human_guard_assume_yes" "${global_profile}")
    PROFILE_HUMAN_GUARD_SCOPE=$(parse_toml_value "human_guard_scope" "${global_profile}")
    PROFILE_AGENT_ROUTES=$(parse_toml_array "agent_routes" "${global_profile}")
    PROFILE_TICKET=$(parse_toml_value "ticket" "${global_profile}")
    PROFILE_SOURCE_CONTROL_ENABLED=$(parse_toml_value "source_control_enabled" "${global_profile}")
    PROFILE_SOURCE_CONTROL_BACKEND=$(parse_toml_value "source_control_backend" "${global_profile}")
    PROFILE_SOURCE_CONTROL_ALLOW_COMMITS=$(parse_toml_value "source_control_allow_commits" "${global_profile}")
    PROFILE_SOURCE_CONTROL_BRANCH_PER_SESSION=$(parse_toml_value "source_control_branch_per_session" "${global_profile}")
    PROFILE_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE=$(parse_toml_value "source_control_branch_name_template" "${global_profile}")
    PROFILE_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=$(parse_toml_value "source_control_require_ticket_for_branch" "${global_profile}")
    PROFILE_ISSUES_PROVIDER=$(parse_toml_value "issues_provider" "${global_profile}")
    PROFILE_CHECKPOINT_ENABLED=$(parse_toml_value "checkpoint_enabled" "${global_profile}")
    PROFILE_CHECKPOINT_PER_STEP=$(parse_toml_value "checkpoint_per_step" "${global_profile}")
    PROFILE_HOOKS_JSON=$(parse_toml_value "hooks_json" "${global_profile}")
    PROFILE_TASKS_JSON=$(parse_toml_value "tasks_json" "${global_profile}")
    PROFILE_LANGUAGE=$(parse_toml_value "language" "${global_profile}")
  fi

  if [[ -n "${RALPH_PROJECT_DIR}" ]] && [[ -f "${project_profile}" ]]; then
    local val
    val=$(parse_toml_value "steps" "${project_profile}")
    [[ -z "${val}" ]] && val=$(parse_toml_value "iterations" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_STEPS="${val}"

    val=$(parse_toml_value "model" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_MODEL="${val}"

    val=$(parse_toml_value "engine" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_ENGINE="${val}"

    val=$(parse_toml_value "timeout" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_TIMEOUT="${val}"

    val=$(parse_toml_value "skip_git_check" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SKIP_GIT_CHECK="${val}"

    val=$(parse_toml_array "disabled" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_DISABLED_HOOKS="${val}"

    val=$(parse_toml_value "author" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_AUTHOR="${val}"

    val=$(parse_toml_value "project" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_PROJECT="${val}"

    val=$(parse_toml_value "human_guard" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_HUMAN_GUARD="${val}"

    val=$(parse_toml_value "human_guard_assume_yes" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_HUMAN_GUARD_ASSUME_YES="${val}"

    val=$(parse_toml_value "human_guard_scope" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_HUMAN_GUARD_SCOPE="${val}"

    val=$(parse_toml_array "agent_routes" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_AGENT_ROUTES="${val}"

    val=$(parse_toml_value "ticket" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_TICKET="${val}"

    val=$(parse_toml_value "source_control_enabled" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_ENABLED="${val}"

    val=$(parse_toml_value "source_control_backend" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_BACKEND="${val}"

    val=$(parse_toml_value "source_control_allow_commits" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_ALLOW_COMMITS="${val}"

    val=$(parse_toml_value "source_control_branch_per_session" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_BRANCH_PER_SESSION="${val}"

    val=$(parse_toml_value "source_control_branch_name_template" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE="${val}"

    val=$(parse_toml_value "source_control_require_ticket_for_branch" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH="${val}"

    val=$(parse_toml_value "issues_provider" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_ISSUES_PROVIDER="${val}"

    val=$(parse_toml_value "checkpoint_enabled" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_CHECKPOINT_ENABLED="${val}"

    val=$(parse_toml_value "checkpoint_per_step" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_CHECKPOINT_PER_STEP="${val}"

    val=$(parse_toml_value "hooks_json" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_HOOKS_JSON="${val}"

    val=$(parse_toml_value "tasks_json" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_TASKS_JSON="${val}"

    val=$(parse_toml_value "language" "${project_profile}")
    [[ -n "${val}" ]] && PROFILE_LANGUAGE="${val}"
  fi

  return 0
}

# Resolves optional hooks.json path from env override or workspace default.
# Default path is `.ralph/hooks.json` with fallback to legacy `.ralph/hooks/hooks.json`.
resolve_hooks_json_path() {
  local configured="${RALPH_HOOKS_JSON:-}"
  local candidate=""
  if [[ -n "${configured}" ]]; then
    configured="${configured/#\~/$HOME}"
    if [[ "${configured}" == /* ]]; then
      candidate="${configured}"
    else
      candidate="${ROOT}/${configured}"
    fi
  else
    if [[ -f "${ROOT}/.ralph/hooks.json" ]]; then
      candidate="${ROOT}/.ralph/hooks.json"
    else
      candidate="${ROOT}/.ralph/hooks/hooks.json"
    fi
  fi

  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
  fi
}

# Resolves optional tasks.json path from env override or workspace default.
# Default path is `.ralph/tasks.json` with fallback to legacy `.ralph/tasks/tasks.json`.
resolve_tasks_json_path() {
  local configured="${RALPH_TASKS_JSON:-}"
  local candidate=""
  if [[ -n "${configured}" ]]; then
    configured="${configured/#\~/$HOME}"
    if [[ "${configured}" == /* ]]; then
      candidate="${configured}"
    else
      candidate="${ROOT}/${configured}"
    fi
  else
    if [[ -f "${ROOT}/.ralph/tasks.json" ]]; then
      candidate="${ROOT}/.ralph/tasks.json"
    else
      candidate="${ROOT}/.ralph/tasks/tasks.json"
    fi
  fi

  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
  fi
}

# Resolves execution plan path from input value.
resolve_plan_file_path() {
  local input="$1"
  [[ -z "${input}" ]] && return

  input="${input/#\~/$HOME}"
  if [[ "${input}" == */* ]]; then
    if [[ "${input}" == /* ]]; then
      printf '%s' "${input}"
    else
      printf '%s' "${ROOT}/${input}"
    fi
    return
  fi

  printf '%s' "${ROOT}/.ralph/plans/${input}"
}

# Resolves hook script path by precedence and disabled hook policy.
resolve_hook() {
  local hook_name="$1"
  local hook_file="${hook_name}.sh"

  if [[ " ${PROFILE_DISABLED_HOOKS} " == *" ${hook_name} "* ]]; then
    return
  fi

  if [[ -n "${RALPH_PROJECT_DIR}" ]] && [[ -x "${RALPH_PROJECT_DIR}/hooks/${hook_file}" ]]; then
    printf '%s' "${RALPH_PROJECT_DIR}/hooks/${hook_file}"
    return
  fi

  if [[ -x "${RALPH_GLOBAL_DIR}/hooks/${hook_file}" ]]; then
    printf '%s' "${RALPH_GLOBAL_DIR}/hooks/${hook_file}"
    return
  fi

  if [[ -x "${SCRIPT_DIR}/.ralph/hooks/${hook_file}" ]]; then
    printf '%s' "${SCRIPT_DIR}/.ralph/hooks/${hook_file}"
    return
  fi
}
