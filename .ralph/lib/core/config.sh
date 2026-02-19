#!/usr/bin/env bash
# Core configuration helpers for Ralph orchestrator.
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_LIB_PATH="${CONFIG_DIR}/../json.sh"
if [[ -f "${JSON_LIB_PATH}" ]]; then
  # shellcheck disable=SC1090
  source "${JSON_LIB_PATH}"
else
  echo "Missing JSON helper library: ${JSON_LIB_PATH}" >&2
  return 1 2>/dev/null || exit 1
fi

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

# Loads profile values from one profile.jsonc file.
load_profile_jsonc_file() {
  local profile_file="$1"
  [[ -f "${profile_file}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local norm val
  norm="$(json_like_to_temp_file "${profile_file}")" || return 0

  val="$(jq -r '.defaults.steps // .defaults.iterations // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_STEPS="${val}"
  val="$(jq -r '.defaults.engine // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_ENGINE="${val}"
  val="$(jq -r '.defaults.model // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_MODEL="${val}"
  val="$(jq -r '.defaults.timeout // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_TIMEOUT="${val}"
  val="$(jq -r '.defaults.skip_git_check // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SKIP_GIT_CHECK="${val}"
  val="$(jq -r '.defaults.author // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_AUTHOR="${val}"
  val="$(jq -r '.defaults.project // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_PROJECT="${val}"
  val="$(jq -r '.defaults.human_guard // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_HUMAN_GUARD="${val}"
  val="$(jq -r '.defaults.human_guard_assume_yes // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_HUMAN_GUARD_ASSUME_YES="${val}"
  val="$(jq -r '.defaults.human_guard_scope // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_HUMAN_GUARD_SCOPE="${val}"
  val="$(jq -r '.defaults.ticket // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_TICKET="${val}"
  val="$(jq -r '.defaults.source_control_enabled // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_ENABLED="${val}"
  val="$(jq -r '.defaults.source_control_backend // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_BACKEND="${val}"
  val="$(jq -r '.defaults.source_control_allow_commits // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_ALLOW_COMMITS="${val}"
  val="$(jq -r '.defaults.source_control_branch_per_session // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_BRANCH_PER_SESSION="${val}"
  val="$(jq -r '.defaults.source_control_branch_name_template // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE="${val}"
  val="$(jq -r '.defaults.source_control_require_ticket_for_branch // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH="${val}"
  if jq -e '.defaults | has("issues_providers")' "${norm}" >/dev/null 2>&1; then
    PROFILE_ISSUES_PROVIDERS="$(
      jq -r '.defaults.issues_providers // [] | .[]' "${norm}" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
    )"
  else
    val="$(jq -r '.defaults.issues_provider // empty' "${norm}" 2>/dev/null || true)"
    [[ -n "${val}" ]] && PROFILE_ISSUES_PROVIDERS="${val}"
  fi
  val="$(jq -r '.defaults.checkpoint_enabled // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_CHECKPOINT_ENABLED="${val}"
  val="$(jq -r '.defaults.checkpoint_per_step // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_CHECKPOINT_PER_STEP="${val}"
  val="$(jq -r '.defaults.hooks_json // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_HOOKS_JSON="${val}"
  val="$(jq -r '.defaults.tasks_json // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_TASKS_JSON="${val}"
  val="$(jq -r '.defaults.language // empty' "${norm}" 2>/dev/null || true)"
  [[ -n "${val}" ]] && PROFILE_LANGUAGE="${val}"

  if jq -e '.hooks | has("disabled")' "${norm}" >/dev/null 2>&1; then
    PROFILE_DISABLED_HOOKS="$({ jq -r '.hooks.disabled // [] | .[]' "${norm}" 2>/dev/null || true; } | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  fi

  if jq -e '.defaults | has("agent_routes")' "${norm}" >/dev/null 2>&1; then
    PROFILE_AGENT_ROUTES="$({
      jq -r '
        (.defaults.agent_routes // [])
        | .[]
        | if type == "string" then .
          elif type == "object" then [(.match // ""), (.engine // ""), (.model // "-")] | join("|")
          else empty end
      ' "${norm}" 2>/dev/null || true
    } | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  fi

  rm -f "${norm}"
}

# Loads and merges profile values from JSONC (global first, project overrides).
load_profile() {
  local global_profile="${RALPH_GLOBAL_DIR}/profile.jsonc"
  local project_profile="${RALPH_PROJECT_DIR}/profile.jsonc"

  load_profile_jsonc_file "${global_profile}"
  if [[ -n "${RALPH_PROJECT_DIR}" ]]; then
    load_profile_jsonc_file "${project_profile}"
  fi

  return 0
}

# Resolves optional hooks config path from env override or workspace default.
# Default path is `.ralph/hooks.jsonc` with fallback to `.ralph/hooks.json`.
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
    if [[ -f "${ROOT}/.ralph/hooks.jsonc" ]]; then
      candidate="${ROOT}/.ralph/hooks.jsonc"
    elif [[ -f "${ROOT}/.ralph/hooks.json" ]]; then
      candidate="${ROOT}/.ralph/hooks.json"
    else
      candidate=""
    fi
  fi

  if [[ -n "${candidate}" ]] && [[ -f "${candidate}" ]]; then
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
