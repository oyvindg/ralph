#!/usr/bin/env bash
set -euo pipefail

resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "${source}" ]]; do
    local dir
    dir="$(cd "$(dirname "${source}")" && pwd)"
    source="$(readlink "${source}")"
    [[ "${source}" != /* ]] && source="${dir}/${source}"
  done
  local final_dir
  final_dir="$(cd "$(dirname "${source}")" && pwd)"
  printf '%s' "${final_dir}"
}

# Initializes runtime defaults and shared globals.
init_runtime_defaults() {
  SCRIPT_DIR="$(resolve_script_dir)"
  RALPH_VERSION="0.1.0"

  # =============================================================================
  # Global Variables
  # =============================================================================
  CALLER_ROOT="$(pwd)"
  ROOT="${CALLER_ROOT}"
  WORKSPACE=""
  MAX_STEPS=0  # 0 = no limit (run all pending steps)
  GOAL=""
  PLAN_FILE="plan.json"
  PLAN_FILE_PATH=""
  PLAN_CONTEXT_FILE=""
  PLAN_CLI_SET=0
  RESET_PLAN=0
  NEW_PLAN=0
  GUIDE_PATH=""
  GUIDE_CONTENT=""
  DRY_RUN=0
  TIMEOUT_SECONDS=""
  MODEL=""
  NO_COLORS=0
  VERBOSE=0
  SKIP_GIT_CHECK=0
  HUMAN_GUARD=""
  HUMAN_GUARD_ASSUME_YES=""
  HUMAN_GUARD_SCOPE=""
  ALLOW_RALPH_EDITS=""
  TICKET=""
  SOURCE_CONTROL_ENABLED=""
  SOURCE_CONTROL_BACKEND=""
  SOURCE_CONTROL_ALLOW_COMMITS=""
  SOURCE_CONTROL_BRANCH_PER_SESSION=""
  SOURCE_CONTROL_BRANCH_NAME_TEMPLATE=""
  SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=""
  ISSUES_PROVIDERS=""
  CHECKPOINT_ENABLED=""
  CHECKPOINT_PER_STEP=""
  CHECKPOINT_MODE=""
  ENGINE_CLI_SET=0
  MODEL_CLI_SET=0
  ACTIVE_ENGINE=""
  ACTIVE_MODEL=""
  STATE_FILE_PATH=""
  HOOKS_JSON_PATH=""
  TASKS_JSON_PATH=""
  LANG_CODE=""
  SETUP_MODE=0
  SETUP_FORCE=0
  SETUP_TARGET=""
  TEST_MODE=0

  # Session variables (set in setup_session)
  session_dir=""
  summary_md=""
  last_response=""
  prompt_input_file=""
  step_stats_rows_file=""
  step_details_file=""
  session_id=""
  session_start_epoch=""
  session_start_iso=""
  total_duration_sec=0

  # Color variables (set in setup_colors)
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_MAGENTA=""

  # Ralph config directories (set in find_ralph_dirs)
  RALPH_PROJECT_DIR=""   # <project>/.ralph
  RALPH_GLOBAL_DIR=""    # ~/.ralph

  # Profile values (set in load_profile)
  PROFILE_STEPS=""
  PROFILE_ENGINE=""
  PROFILE_MODEL=""
  PROFILE_TIMEOUT=""
  PROFILE_SKIP_GIT_CHECK=""
  PROFILE_DISABLED_HOOKS=""
  PROFILE_AUTHOR=""
  PROFILE_PROJECT=""
  PROFILE_HUMAN_GUARD=""
  PROFILE_HUMAN_GUARD_ASSUME_YES=""
  PROFILE_HUMAN_GUARD_SCOPE=""
  PROFILE_AGENT_ROUTES=""
  PROFILE_TICKET=""
  PROFILE_SOURCE_CONTROL_ENABLED=""
  PROFILE_SOURCE_CONTROL_BACKEND=""
  PROFILE_SOURCE_CONTROL_ALLOW_COMMITS=""
  PROFILE_SOURCE_CONTROL_BRANCH_PER_SESSION=""
  PROFILE_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE=""
  PROFILE_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=""
  PROFILE_ISSUES_PROVIDERS=""
  PROFILE_CHECKPOINT_ENABLED=""
  PROFILE_CHECKPOINT_PER_STEP=""
  PROFILE_HOOKS_JSON=""
  PROFILE_TASKS_JSON=""
  PROFILE_LANGUAGE=""
}

version_task_command() {
  # Resolves version.print task command from tasks.jsonc.
  local saved_root="${ROOT}"
  local tasks_file=""
  local cmd=""

  bootstrap_config_lib
  ROOT="${SCRIPT_DIR}"
  tasks_file="$(resolve_tasks_json_path || true)"
  ROOT="${saved_root}"

  [[ -n "${tasks_file}" && -f "${tasks_file}" ]] || return 1
  [[ -f "${SCRIPT_DIR}/.ralph/lib/core/parser.sh" ]] || return 1
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.ralph/lib/core/parser.sh"

  cmd="$(json_hook_when_task_command "version.print" "${tasks_file}")"
  [[ -n "${cmd}" ]] || return 1
  printf '%s\n' "${cmd}"
}

run_version_task() {
  # Runs version.print task with repo_root bound to script directory.
  local cmd
  cmd="$(version_task_command || true)"
  [[ -n "${cmd}" ]] || return 1
  repo_root="${SCRIPT_DIR}" \
  RALPH_PROJECT_DIR="${SCRIPT_DIR}/.ralph" \
  RALPH_WORKSPACE="${SCRIPT_DIR}" \
  bash -lc "${cmd}"
}

init_runtime_defaults

# =============================================================================
# Docker Functions
# =============================================================================
docker_build() {
  echo "Building ralph docker image..."
  docker build -t ralph -f "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}"
  echo "Done."
}

docker_run() {
  local rebuild="$1"
  shift

  # Build image if needed
  if [[ "${rebuild}" -eq 1 ]] || ! docker image inspect ralph >/dev/null 2>&1; then
    docker_build
  fi

  # Parse args to find workspace/plan/guide paths for mounting
  declare -A MOUNT_PATHS
  local DOCKER_ARGS=()
  local DOCKER_WORKSPACE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        DOCKER_WORKSPACE="$(cd "${2/#\~/$HOME}" && pwd)"
        MOUNT_PATHS["${DOCKER_WORKSPACE}"]=1
        DOCKER_ARGS+=("$1" "${DOCKER_WORKSPACE}")
        shift 2
        ;;
      --plan)
        local plan_arg="${2/#\~/$HOME}"
        if [[ "${plan_arg}" == */* ]]; then
          local plan_dir
          plan_dir="$(cd "$(dirname "${plan_arg}")" && pwd)"
          MOUNT_PATHS["${plan_dir}"]=1
          DOCKER_ARGS+=("$1" "${plan_dir}/$(basename "${plan_arg}")")
        else
          DOCKER_ARGS+=("$1" "${plan_arg}")
        fi
        shift 2
        ;;
      --guide)
        local guide_path="${2/#\~/$HOME}"
        guide_path="$(cd "$(dirname "${guide_path}")" && pwd)/$(basename "${guide_path}")"
        MOUNT_PATHS["$(dirname "${guide_path}")"]=1
        DOCKER_ARGS+=("$1" "${guide_path}")
        shift 2
        ;;
      *)
        DOCKER_ARGS+=("$1")
        shift
        ;;
    esac
  done

  # Default workspace to current directory
  if [[ -z "${DOCKER_WORKSPACE}" ]]; then
    DOCKER_WORKSPACE="$(pwd)"
    MOUNT_PATHS["${DOCKER_WORKSPACE}"]=1
  fi

  # Build unique volume mounts
  local VOLUMES=()
  for path in "${!MOUNT_PATHS[@]}"; do
    VOLUMES+=(-v "${path}:${path}")
  done

  # TTY flags
  local TTY_FLAGS=""
  [[ -t 1 ]] && TTY_FLAGS="-t"
  [[ -t 0 ]] && TTY_FLAGS="-it"

  # Temp file for error checking
  local output_file=$(mktemp)
  trap "rm -f ${output_file}" EXIT

  # Run ralph in docker as current user
  set +e
  docker run --rm ${TTY_FLAGS} \
    --user "$(id -u):$(id -g)" \
    -w "${DOCKER_WORKSPACE}" \
    "${VOLUMES[@]}" \
    -v "${HOME}/.codex/auth.json:${HOME}/.codex/auth.json:ro" \
    -v "${HOME}/.codex/config.toml:${HOME}/.codex/config.toml:ro" \
    -e HOME="${HOME}" \
    ralph "${DOCKER_ARGS[@]}" 2>&1 | tee "${output_file}"
  local exit_code=${PIPESTATUS[0]}
  set -e

  # Check for rate limit errors
  if grep -qi "usage limit\|hit your.*limit\|rate limit" "${output_file}" 2>/dev/null; then
    echo ""
    echo $'\033[31m============================================\033[0m'
    echo $'\033[31m  API USAGE LIMIT REACHED\033[0m'
    echo $'\033[33m  Check your plan or wait for quota reset\033[0m'
    echo $'\033[31m============================================\033[0m'
  fi

  exit ${exit_code}
}

check_docker_delegation() {
  for arg in "$@"; do
    if [[ "${arg}" == "--docker-build" ]]; then
      docker_build
      exit 0
    fi
    if [[ "${arg}" == "--docker" ]]; then
      local args=()
      for a in "$@"; do
        [[ "${a}" != "--docker" ]] && args+=("${a}")
      done
      docker_run 0 "${args[@]}"
    fi
    if [[ "${arg}" == "--docker-rebuild" ]]; then
      local args=()
      for a in "$@"; do
        [[ "${a}" != "--docker-rebuild" ]] && args+=("${a}")
      done
      docker_run 1 "${args[@]}"
    fi
  done
}

# =============================================================================
# Configuration Functions
# =============================================================================

# Load UI helpers when available (project first, then global, then built-in).
load_ui_helpers() {
  local candidates=()
  [[ -n "${RALPH_PROJECT_DIR}" ]] && candidates+=("${RALPH_PROJECT_DIR}/lib/ui.sh")
  candidates+=("${RALPH_GLOBAL_DIR}/lib/ui.sh")
  candidates+=("${SCRIPT_DIR}/.ralph/lib/ui.sh")

  local path
  for path in "${candidates[@]}"; do
    if [[ -f "${path}" ]]; then
      # shellcheck disable=SC1090
      source "${path}"
      return 0
    fi
  done
}

# Load core libs when available (project first, then global, then built-in).
load_core_libs() {
  local libs=(
    "state.sh"
    "bootstrap.sh"
    "core/config.sh"
    "core/plan.sh"
    "core/session.sh"
    "core/step-hooks.sh"
    "core/plan-selection.sh"
    "core/parser.sh"
  )
  local rel lib_path
  for rel in "${libs[@]}"; do
    local candidates=()
    [[ -n "${RALPH_PROJECT_DIR}" ]] && candidates+=("${RALPH_PROJECT_DIR}/lib/${rel}")
    candidates+=("${RALPH_GLOBAL_DIR}/lib/${rel}")
    candidates+=("${SCRIPT_DIR}/.ralph/lib/${rel}")
    for lib_path in "${candidates[@]}"; do
      if [[ -f "${lib_path}" ]]; then
        # shellcheck disable=SC1090
        source "${lib_path}"
        break
      fi
    done
  done
}

# Prints a debug line only when verbose mode is enabled.
verbose_log() {
  [[ "${VERBOSE}" -eq 1 ]] || return 0
  echo "${C_DIM}[debug]${C_RESET} $*"
}

# Prints resolved runtime configuration in verbose mode.
print_verbose_runtime_config() {
  [[ "${VERBOSE}" -eq 1 ]] || return 0
  echo "${C_DIM}+---------------- Verbose Runtime ----------------+${C_RESET}"
  echo "${C_DIM}|${C_RESET} workspace=${ROOT}"
  echo "${C_DIM}|${C_RESET} goal=${GOAL}"
  echo "${C_DIM}|${C_RESET} steps=${MAX_STEPS}"
  echo "${C_DIM}|${C_RESET} engine_default=${RALPH_ENGINE:-codex}"
  [[ -n "${MODEL}" ]] && echo "${C_DIM}|${C_RESET} model=${MODEL}"
  echo "${C_DIM}|${C_RESET} dry_run=${DRY_RUN}"
  echo "${C_DIM}|${C_RESET} timeout=${TIMEOUT_SECONDS}"
  echo "${C_DIM}|${C_RESET} plan=$(to_rel_path "$(plan_json_path)")"
  [[ -n "${GUIDE_PATH}" ]] && echo "${C_DIM}|${C_RESET} guide=$(to_rel_path "${GUIDE_PATH}")"
  [[ -n "${HOOKS_JSON_PATH}" ]] && echo "${C_DIM}|${C_RESET} hooks_json=$(to_rel_path "${HOOKS_JSON_PATH}")"
  [[ -n "${TASKS_JSON_PATH}" ]] && echo "${C_DIM}|${C_RESET} tasks_json=$(to_rel_path "${TASKS_JSON_PATH}")"
  echo "${C_DIM}|${C_RESET} human_guard=${HUMAN_GUARD} (${HUMAN_GUARD_SCOPE})"
  echo "${C_DIM}|${C_RESET} allow_ralph_edits=${ALLOW_RALPH_EDITS}"
  echo "${C_DIM}|${C_RESET} language=${LANG_CODE}"
  echo "${C_DIM}+-------------------------------------------------+${C_RESET}"
}

# Loads the minimal config library early so validate_args can resolve dirs/profile.
bootstrap_config_lib() {
  if command -v find_ralph_dirs >/dev/null 2>&1; then
    return 0
  fi

  local dir="${ROOT}"
  while [[ "${dir}" != "/" ]]; do
    if [[ -f "${dir}/.ralph/lib/core/config.sh" ]]; then
      # shellcheck disable=SC1090
      source "${dir}/.ralph/lib/core/config.sh"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done

  if [[ -f "${HOME}/.ralph/lib/core/config.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.ralph/lib/core/config.sh"
    return 0
  fi

  if [[ -f "${SCRIPT_DIR}/.ralph/lib/core/config.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.ralph/lib/core/config.sh"
    return 0
  fi

  echo "ERROR: could not load core config library (config.sh)." >&2
  exit 1
}

# Resolve effective engine/model for one step using profile agent routes.
# Route format:
#   agent_routes = ["<match>|<engine>|<model>", "default|<engine>|<model>"]
# Match is case-insensitive substring against step id + description.
# Use "-" as model to keep the current/default model for that route.
resolve_agent_for_step() {
  local step_id="${1:-}"
  local step_desc="${2:-}"
  local haystack route matched=0
  local default_engine="" default_model=""
  local route_match route_engine route_model

  ACTIVE_ENGINE="${RALPH_ENGINE:-codex}"
  ACTIVE_MODEL="${MODEL:-}"

  # CLI flags always win over profile routing.
  if [[ "${ENGINE_CLI_SET}" -eq 1 || "${MODEL_CLI_SET}" -eq 1 ]]; then
    return 0
  fi

  haystack="$(printf '%s %s' "${step_id}" "${step_desc}" | tr '[:upper:]' '[:lower:]')"

  for route in ${PROFILE_AGENT_ROUTES:-}; do
    route_match=""
    route_engine=""
    route_model=""
    IFS='|' read -r route_match route_engine route_model <<< "${route}"
    route_match="$(printf '%s' "${route_match}" | tr '[:upper:]' '[:lower:]')"

    [[ -z "${route_match}" || -z "${route_engine}" ]] && continue

    if [[ "${route_match}" == "default" ]]; then
      default_engine="${route_engine}"
      default_model="${route_model}"
      continue
    fi

    if [[ "${haystack}" == *"${route_match}"* ]]; then
      ACTIVE_ENGINE="${route_engine}"
      if [[ -n "${route_model}" && "${route_model}" != "-" ]]; then
        ACTIVE_MODEL="${route_model}"
      fi
      matched=1
      break
    fi
  done

  if [[ "${matched}" -eq 0 ]] && [[ -n "${default_engine}" ]]; then
    ACTIVE_ENGINE="${default_engine}"
    if [[ -n "${default_model}" && "${default_model}" != "-" ]]; then
      ACTIVE_MODEL="${default_model}"
    fi
  fi
}

#
# Configuration, plan selection, and hooks.json command helpers are loaded from:
# - `.ralph/lib/core/config.sh`
# - `.ralph/lib/core/plan-selection.sh`
# - `.ralph/lib/core/parser.sh`

# Plan helpers are loaded from:
# - `.ralph/lib/core/plan.sh`

# Run a hook with environment variables
# Returns the hook's exit code (0 if no hook exists)
run_hook() {
  local hook_name="$1"
  local step="${2:-}"
  local step_exit_code="${3:-}"
  local hook_depth="${RALPH_HOOK_DEPTH:-0}"

  local hook_path
  hook_path=$(resolve_hook "${hook_name}")

  # Set up environment
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
  export RALPH_SOURCE_CONTROL_ENABLED="${SOURCE_CONTROL_ENABLED}"
  export RALPH_SOURCE_CONTROL_BACKEND="${SOURCE_CONTROL_BACKEND}"
  export RALPH_SOURCE_CONTROL_ALLOW_COMMITS="${SOURCE_CONTROL_ALLOW_COMMITS}"
  export RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION="${SOURCE_CONTROL_BRANCH_PER_SESSION}"
  export RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE="${SOURCE_CONTROL_BRANCH_NAME_TEMPLATE}"
  export RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH="${SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH}"
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

  # Step-specific vars
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
  # Phase 1: user hooks before system hook.
  if ! run_json_hook_commands "${hook_name}" "before-system" "${step}" "${step_exit_code}"; then
    return 1
  fi

  # Phase 2: system shell hook.
  if [[ -n "${hook_path}" ]]; then
    # Run script hook (hooks receive RALPH_DRY_RUN and handle it themselves)
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

  # Phase 3: hooks.json system phase.
  if ! run_json_hook_commands "${hook_name}" "system" "${step}" "${step_exit_code}"; then
    return 1
  fi

  # Phase 4: user hooks after system hook.
  if ! run_json_hook_commands "${hook_name}" "after-system" "${step}" "${step_exit_code}"; then
    return 1
  fi

  return 0
}

# List available AI engines
list_engines() {
  if ! declare -F find_ralph_dirs >/dev/null 2>&1; then
    bootstrap_config_lib
  fi
  find_ralph_dirs

  local ai_hook
  ai_hook=$(resolve_hook "ai")

  if [[ -n "${ai_hook}" ]]; then
    RALPH_ENGINE=list "${ai_hook}"
  else
    echo "Available AI engines:"
    echo ""
    if command -v codex >/dev/null 2>&1; then
      echo "  [x] codex      - OpenAI Codex CLI (built-in)"
    else
      echo "  [ ] codex      - OpenAI Codex CLI (not installed)"
    fi
    echo ""
    echo "Note: Install .ralph/hooks/ai.sh for more engines"
  fi
}

# =============================================================================
# Usage
# =============================================================================
run_setup_install() {
  local installer="${SCRIPT_DIR}/.ralph/lib/setup/install-global.sh"
  if [[ ! -f "${installer}" ]]; then
    echo "ERROR: setup installer not found: ${installer}" >&2
    exit 1
  fi

  local -a args=()
  [[ "${SETUP_FORCE}" -eq 1 ]] && args+=(--force)
  [[ -n "${SETUP_TARGET}" ]] && args+=(--target "${SETUP_TARGET}")

  chmod +x "${installer}" 2>/dev/null || true
  "${installer}" "${args[@]}"
}

run_repo_tests() {
  local test_runner="${SCRIPT_DIR}/tests/run.sh"
  if [[ ! -x "${test_runner}" ]]; then
    echo "ERROR: test runner not found or not executable: ${test_runner}" >&2
    echo "Next step: see ${SCRIPT_DIR}/tests/README.md" >&2
    exit 1
  fi
  "${test_runner}"
}

usage() {
  cat <<EOF
Usage:
  ./ralph.sh [--goal "<goal>" | --plan <file>] [options]

Required:
      --goal "<text>"     The overall goal for this session (optional when --plan is set)
  or  --plan <file>       Execution plan file with steps/goal metadata

Options:
      --steps <N>         Max steps to run (default: all pending, or profile default)
      --plan <file>       Execution plan file (default: plan.json -> .ralph/plans/plan.json)
      --new-plan          Create/select a new plan interactively, regardless of existing plan state
      --reset-plan        Reset selected structured plan (all steps -> pending) before session start
      --guide <file>      Optional guidance file (e.g., AGENTS.md)
      --workspace <path>  Workspace directory (default: current dir)
      --model <name>      Model name (default: engine default)
      --engine <name>     AI engine: codex, claude, ollama, openai, anthropic
      --ticket <id>       Optional work item/ticket id (agnostic, e.g. ABC-123)
      --timeout <sec>     Timeout per step in seconds (0 = disabled)
      --checkpoint <mode> Checkpoint mode: off|pre|all (or 0|1)
      --checkpoint-per-step <0|1>  Override per-step checkpoint snapshots
      --list-engines      Show available AI engines and exit
      --no-colors         Disable ANSI colors in output
      --verbose           Enable verbose debug logging
      --human-guard <0|1> Enable/disable human approval guard
      --human-guard-assume-yes <0|1>  Auto-approve human guard prompts (CI)
      --human-guard-scope <session|step|both>  Where to enforce guard
      --allow-ralph-edits <0|1>  Allow agent edits under .ralph/
      --skip-git-repo-check  Allow running in non-git directories
      --docker            Run in docker container
      --docker-build      Build docker image only
      --docker-rebuild    Run in docker, rebuild image first
      --setup             Install/update global baseline (~/.ralph) and exit
      --setup-force       Overwrite existing global files (used with --setup)
      --setup-target <dir> Install baseline to custom target dir (with --setup)
      --test              Run Ralph repo test suite and exit
      --version          Show version and exit
      --dry-run           Run full workflow with mock AI (no API calls)

Examples:
  ./ralph.sh --goal "Improve test coverage"              # Run all pending steps
  ./ralph.sh --goal "Refactor auth module" --steps 3     # Run max 3 steps
  ./ralph.sh --goal "Debug build" --dry-run              # Dry-run with mock AI
  ./ralph.sh --goal "Optimize queries" --guide AGENTS.md # With guidance file
  ./ralph.sh --goal "Fix bug" --ticket ABC-123           # Attach work item id
  ./ralph.sh --setup                                      # Install ~/.ralph baseline
  ./ralph.sh --test                                       # Run tests/run.sh
EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================
parse_args() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --steps) MAX_STEPS="${2:-}"; shift 2 ;;
      --goal) GOAL="${2:-}"; shift 2 ;;
      --plan) PLAN_FILE="${2:-}"; PLAN_CLI_SET=1; shift 2 ;;
      --new-plan) NEW_PLAN=1; shift ;;
      --reset-plan) RESET_PLAN=1; shift ;;
      --guide) GUIDE_PATH="${2:-}"; shift 2 ;;
      --workspace) WORKSPACE="${2:-}"; shift 2 ;;
      --model) MODEL="${2:-}"; MODEL_CLI_SET=1; shift 2 ;;
      --engine) export RALPH_ENGINE="${2:-}"; ENGINE_CLI_SET=1; shift 2 ;;
      --ticket) TICKET="${2:-}"; shift 2 ;;
      --timeout) TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
      --checkpoint) CHECKPOINT_MODE="${2:-}"; shift 2 ;;
      --checkpoint-per-step) CHECKPOINT_PER_STEP="${2:-}"; shift 2 ;;
      --list-engines) list_engines; exit 0 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --no-colors) NO_COLORS=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      --human-guard) HUMAN_GUARD="${2:-}"; shift 2 ;;
      --human-guard-assume-yes) HUMAN_GUARD_ASSUME_YES="${2:-}"; shift 2 ;;
      --human-guard-scope) HUMAN_GUARD_SCOPE="${2:-}"; shift 2 ;;
      --allow-ralph-edits) ALLOW_RALPH_EDITS="${2:-}"; shift 2 ;;
      --skip-git-repo-check) SKIP_GIT_CHECK=1; shift ;;
      --setup) SETUP_MODE=1; shift ;;
      --setup-force) SETUP_FORCE=1; shift ;;
      --setup-target) SETUP_TARGET="${2:-}"; shift 2 ;;
      --test) TEST_MODE=1; shift ;;
      --version)
        if run_version_task; then
          : "version.print task executed"
        else
          echo "ralph ${RALPH_VERSION}"
        fi
        exit 0
        ;;
      --help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
  done

  if [[ "${SETUP_MODE}" -eq 1 ]]; then
    run_setup_install
    exit 0
  fi
  if [[ "${TEST_MODE}" -eq 1 ]]; then
    run_repo_tests
    exit 0
  fi
}

plan_file_has_structured_steps() {
  local plan_file="$1"
  [[ -f "${plan_file}" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e '.steps | type == "array"' "${plan_file}" >/dev/null 2>&1
}

derive_structured_plan_path_from_context() {
  local context_file="$1"
  local base_name
  base_name="$(basename "${context_file}")"
  base_name="${base_name%.*}"
  [[ -z "${base_name}" ]] && base_name="context-plan"
  printf '%s/.ralph/plans/%s.plan.json' "${ROOT}" "${base_name}"
}

validate_args() {
  # Set ROOT first (needed for find_ralph_dirs)
  if [[ -n "${WORKSPACE// }" ]]; then
    if [[ ! -d "${WORKSPACE}" ]]; then
      echo "ERROR: --workspace path not found or not a directory: ${WORKSPACE}" >&2
      exit 1
    fi
    ROOT="$(cd "${WORKSPACE}" && pwd)"
  else
    ROOT="${CALLER_ROOT}"
  fi

  # Load config helpers first, then resolve .ralph directories/profile.
  bootstrap_config_lib
  find_ralph_dirs
  load_profile
  if [[ -z "${RALPH_HOOKS_JSON:-}" ]] && [[ -n "${PROFILE_HOOKS_JSON}" ]]; then
    export RALPH_HOOKS_JSON="${PROFILE_HOOKS_JSON}"
  fi
  if [[ -z "${RALPH_TASKS_JSON:-}" ]] && [[ -n "${PROFILE_TASKS_JSON}" ]]; then
    export RALPH_TASKS_JSON="${PROFILE_TASKS_JSON}"
  fi
  load_core_libs
  load_ui_helpers
  HOOKS_JSON_PATH="$(resolve_hooks_json_path || true)"
  TASKS_JSON_PATH="$(resolve_tasks_json_path || true)"

  # Apply profile defaults (CLI args override profile)
  # MAX_STEPS=0 means "no limit" - run all pending steps
  if [[ "${MAX_STEPS}" -eq 0 ]] && [[ -n "${PROFILE_STEPS}" ]]; then
    MAX_STEPS="${PROFILE_STEPS}"
  fi
  if [[ -z "${MODEL}" ]] && [[ -n "${PROFILE_MODEL}" ]]; then
    MODEL="${PROFILE_MODEL}"
  fi
  if [[ -z "${RALPH_ENGINE:-}" ]] && [[ -n "${PROFILE_ENGINE}" ]]; then
    export RALPH_ENGINE="${PROFILE_ENGINE}"
  fi
  if [[ -z "${TIMEOUT_SECONDS}" ]] && [[ -n "${PROFILE_TIMEOUT}" ]]; then
    TIMEOUT_SECONDS="${PROFILE_TIMEOUT}"
  fi
  if [[ "${SKIP_GIT_CHECK}" -eq 0 ]] && [[ "${PROFILE_SKIP_GIT_CHECK}" == "true" ]]; then
    SKIP_GIT_CHECK=1
  fi
  if [[ -z "${TICKET}" ]] && [[ -n "${PROFILE_TICKET}" ]]; then
    TICKET="${PROFILE_TICKET}"
  fi
  LANG_CODE="${RALPH_LANG:-${PROFILE_LANGUAGE:-en}}"
  LANG_CODE="$(printf '%s' "${LANG_CODE}" | tr '[:upper:]' '[:lower:]')"
  [[ -z "${LANG_CODE}" ]] && LANG_CODE="en"

  SOURCE_CONTROL_ENABLED="${RALPH_SOURCE_CONTROL_ENABLED:-${PROFILE_SOURCE_CONTROL_ENABLED:-1}}"
  SOURCE_CONTROL_BACKEND="${RALPH_SOURCE_CONTROL_BACKEND:-${PROFILE_SOURCE_CONTROL_BACKEND:-auto}}"
  SOURCE_CONTROL_ALLOW_COMMITS="${RALPH_SOURCE_CONTROL_ALLOW_COMMITS:-${PROFILE_SOURCE_CONTROL_ALLOW_COMMITS:-0}}"
  SOURCE_CONTROL_BRANCH_PER_SESSION="${RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION:-${PROFILE_SOURCE_CONTROL_BRANCH_PER_SESSION:-0}}"
  SOURCE_CONTROL_BRANCH_NAME_TEMPLATE="${RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE:-${PROFILE_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE:-ralph/{ticket}/{goal_slug}/{session_id}}}"
  SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH="${RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH:-${PROFILE_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH:-0}}"
  ISSUES_PROVIDERS="${RALPH_ISSUES_PROVIDERS:-${PROFILE_ISSUES_PROVIDERS:-none}}"
  CHECKPOINT_ENABLED="${RALPH_CHECKPOINT_ENABLED:-${PROFILE_CHECKPOINT_ENABLED:-1}}"
  CHECKPOINT_PER_STEP="${RALPH_CHECKPOINT_PER_STEP:-${PROFILE_CHECKPOINT_PER_STEP:-1}}"

  if [[ -n "${CHECKPOINT_MODE}" ]]; then
    case "$(printf '%s' "${CHECKPOINT_MODE}" | tr '[:upper:]' '[:lower:]')" in
      off|0|false|no)
        CHECKPOINT_ENABLED=0
        CHECKPOINT_PER_STEP=0
        ;;
      pre)
        CHECKPOINT_ENABLED=1
        CHECKPOINT_PER_STEP=0
        ;;
      all|1|true|yes|on)
        CHECKPOINT_ENABLED=1
        CHECKPOINT_PER_STEP=1
        ;;
      *)
        echo "--checkpoint must be one of: off, pre, all (or 0/1)" >&2
        exit 1
        ;;
    esac
  fi

  # Human guard settings precedence: CLI > env > profile > default
  [[ -z "${HUMAN_GUARD}" ]] && HUMAN_GUARD="${RALPH_HUMAN_GUARD:-${PROFILE_HUMAN_GUARD:-0}}"
  [[ -z "${HUMAN_GUARD_ASSUME_YES}" ]] && HUMAN_GUARD_ASSUME_YES="${RALPH_HUMAN_GUARD_ASSUME_YES:-${PROFILE_HUMAN_GUARD_ASSUME_YES:-0}}"
  [[ -z "${HUMAN_GUARD_SCOPE}" ]] && HUMAN_GUARD_SCOPE="${RALPH_HUMAN_GUARD_SCOPE:-${PROFILE_HUMAN_GUARD_SCOPE:-both}}"
  [[ -z "${ALLOW_RALPH_EDITS}" ]] && ALLOW_RALPH_EDITS="${RALPH_ALLOW_RALPH_EDITS:-0}"
  if [[ "${VERBOSE}" -eq 0 ]]; then
    case "${RALPH_VERBOSE:-0}" in
      1|true|TRUE|yes|YES) VERBOSE=1 ;;
      *) VERBOSE=0 ;;
    esac
  fi

  case "${HUMAN_GUARD}" in
    1|true|TRUE|yes|YES) HUMAN_GUARD=1 ;;
    0|false|FALSE|no|NO) HUMAN_GUARD=0 ;;
    *) echo "--human-guard must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac

  case "${HUMAN_GUARD_ASSUME_YES}" in
    1|true|TRUE|yes|YES) HUMAN_GUARD_ASSUME_YES=1 ;;
    0|false|FALSE|no|NO) HUMAN_GUARD_ASSUME_YES=0 ;;
    *) echo "--human-guard-assume-yes must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac

  HUMAN_GUARD_SCOPE="$(printf '%s' "${HUMAN_GUARD_SCOPE}" | tr '[:upper:]' '[:lower:]')"
  case "${HUMAN_GUARD_SCOPE}" in
    session|step|both) ;;
    *) echo "--human-guard-scope must be one of: session, step, both" >&2; exit 1 ;;
  esac

  case "${ALLOW_RALPH_EDITS}" in
    1|true|TRUE|yes|YES) ALLOW_RALPH_EDITS=1 ;;
    0|false|FALSE|no|NO) ALLOW_RALPH_EDITS=0 ;;
    *) echo "--allow-ralph-edits must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac

  SOURCE_CONTROL_BACKEND="$(printf '%s' "${SOURCE_CONTROL_BACKEND}" | tr '[:upper:]' '[:lower:]')"
  case "${SOURCE_CONTROL_BACKEND}" in
    auto|git|filesystem) ;;
    *) echo "source_control_backend must be one of: auto, git, filesystem" >&2; exit 1 ;;
  esac

  ISSUES_PROVIDERS="$(
    printf '%s' "${ISSUES_PROVIDERS}" \
      | tr '[:upper:]' '[:lower:]' \
      | tr ';' ',' \
      | tr -s '[:space:]' ',' \
      | sed 's/^,*//; s/,*$//; s/,,*/,/g'
  )"
  [[ -z "${ISSUES_PROVIDERS}" ]] && ISSUES_PROVIDERS="none"
  local _issues_provider _issues_seen_non_none=0
  for _issues_provider in ${ISSUES_PROVIDERS//,/ }; do
    case "${_issues_provider}" in
      none|git|jira) ;;
      *) echo "issues_providers must contain only: none, git, jira" >&2; exit 1 ;;
    esac
    [[ "${_issues_provider}" != "none" ]] && _issues_seen_non_none=1
  done
  if [[ "${_issues_seen_non_none}" -eq 1 ]]; then
    ISSUES_PROVIDERS="$(printf '%s' "${ISSUES_PROVIDERS}" | sed 's/\(^\|,\)none,\?//g; s/^,*//; s/,*$//')"
  fi
  [[ -z "${ISSUES_PROVIDERS}" ]] && ISSUES_PROVIDERS="none"

  case "${SOURCE_CONTROL_ENABLED}" in
    1|true|TRUE|yes|YES) SOURCE_CONTROL_ENABLED=1 ;;
    0|false|FALSE|no|NO) SOURCE_CONTROL_ENABLED=0 ;;
    *) echo "source_control_enabled must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${SOURCE_CONTROL_ALLOW_COMMITS}" in
    1|true|TRUE|yes|YES) SOURCE_CONTROL_ALLOW_COMMITS=1 ;;
    0|false|FALSE|no|NO) SOURCE_CONTROL_ALLOW_COMMITS=0 ;;
    *) echo "source_control_allow_commits must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${SOURCE_CONTROL_BRANCH_PER_SESSION}" in
    1|true|TRUE|yes|YES) SOURCE_CONTROL_BRANCH_PER_SESSION=1 ;;
    0|false|FALSE|no|NO) SOURCE_CONTROL_BRANCH_PER_SESSION=0 ;;
    *) echo "source_control_branch_per_session must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH}" in
    1|true|TRUE|yes|YES) SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=1 ;;
    0|false|FALSE|no|NO) SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=0 ;;
    *) echo "source_control_require_ticket_for_branch must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${CHECKPOINT_ENABLED}" in
    1|true|TRUE|yes|YES) CHECKPOINT_ENABLED=1 ;;
    0|false|FALSE|no|NO) CHECKPOINT_ENABLED=0 ;;
    *) echo "checkpoint_enabled must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${CHECKPOINT_PER_STEP}" in
    1|true|TRUE|yes|YES) CHECKPOINT_PER_STEP=1 ;;
    0|false|FALSE|no|NO) CHECKPOINT_PER_STEP=0 ;;
    *) echo "checkpoint_per_step must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac

  # Validate steps (0 = no limit, positive integer = limit)
  if [[ -n "${MAX_STEPS}" ]] && ! [[ "${MAX_STEPS}" =~ ^[0-9]+$ ]]; then
    echo "--steps must be a non-negative integer" >&2
    exit 1
  fi

  # Validate timeout
  if [[ -n "${TIMEOUT_SECONDS}" ]] && { ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${TIMEOUT_SECONDS}" -lt 0 ]]; }; then
    echo "--timeout must be an integer >= 0" >&2
    exit 1
  fi

  # Goal is required unless an explicit plan was provided.
  if [[ -z "${GOAL}" && "${PLAN_CLI_SET}" -ne 1 ]]; then
    echo "--goal is required unless --plan is provided" >&2
    exit 1
  fi

  # Model validation
  if [[ -n "${MODEL}" ]] && [[ -z "${MODEL// }" ]]; then
    echo "--model cannot be empty" >&2
    exit 1
  fi

  # Resolve execution plan path.
  if [[ "${NEW_PLAN}" -eq 1 ]]; then
    local forced_new_plan
    forced_new_plan="$(create_new_plan_from_prompt_interactive || true)"
    if [[ -z "${forced_new_plan}" ]]; then
      echo "--new-plan was requested, but new plan creation was canceled or failed." >&2
      exit 1
    fi
    PLAN_FILE_PATH="${forced_new_plan}"
    echo "${C_CYAN}[session]${C_RESET} Created and selected plan: $(to_rel_path "${PLAN_FILE_PATH}")"
  elif [[ "${PLAN_CLI_SET}" -eq 1 ]]; then
  # If --plan was not explicitly set, auto-select from .ralph/plans/*.json:
  # - 0 plans: fallback to default plan.json path
  # - 1 plan: auto-select it
  # - >1 plans: reuse state last_plan_file when valid, else interactive select (TTY), else first plan
    PLAN_FILE_PATH="$(resolve_plan_file_path "${PLAN_FILE}")"
  else
    local -a plan_candidates=()
    local p
    while IFS= read -r p; do
      [[ -n "${p}" ]] && plan_candidates+=("${p}")
    done < <(list_plan_candidates)

    if [[ "${#plan_candidates[@]}" -eq 0 ]]; then
      PLAN_FILE_PATH="$(resolve_plan_file_path "${PLAN_FILE}")"
    elif [[ "${#plan_candidates[@]}" -eq 1 ]]; then
      PLAN_FILE_PATH="${plan_candidates[0]}"
      echo "${C_CYAN}[session]${C_RESET} Auto-selected plan: $(to_rel_path "${PLAN_FILE_PATH}")"
    else
      local last_plan matched_plan
      last_plan="$(state_get_last_plan)"
      matched_plan=""
      if [[ -n "${last_plan}" ]]; then
        local last_plan_abs
        last_plan_abs="$(state_plan_abs_path "${last_plan}")"
        for p in "${plan_candidates[@]}"; do
          if [[ "${p}" == "${last_plan_abs}" ]]; then
            matched_plan="${p}"
            break
          fi
        done
      fi

      if [[ -n "${matched_plan}" ]]; then
        PLAN_FILE_PATH="${matched_plan}"
        echo "${C_CYAN}[session]${C_RESET} Reusing last selected plan: $(to_rel_path "${PLAN_FILE_PATH}")"
      else
        PLAN_FILE_PATH="$(select_plan_interactive "${plan_candidates[@]}")"
        if [[ "${PLAN_FILE_PATH}" == "__CREATE_NEW_PLAN__" ]]; then
          local new_plan
          new_plan="$(create_new_plan_from_prompt_interactive || true)"
          if [[ -n "${new_plan}" ]]; then
            PLAN_FILE_PATH="${new_plan}"
            echo "${C_CYAN}[session]${C_RESET} Created and selected plan: $(to_rel_path "${PLAN_FILE_PATH}")"
          else
            PLAN_FILE_PATH="${plan_candidates[0]}"
            echo "${C_YELLOW}[session]${C_RESET} Plan creation canceled; using: $(to_rel_path "${PLAN_FILE_PATH}")"
          fi
        else
          echo "${C_CYAN}[session]${C_RESET} Selected plan: $(to_rel_path "${PLAN_FILE_PATH}")"
        fi
      fi
    fi
  fi
  if [[ -f "${PLAN_FILE_PATH}" ]] && ! plan_file_has_structured_steps "${PLAN_FILE_PATH}"; then
    PLAN_CONTEXT_FILE="${PLAN_FILE_PATH}"
    PLAN_FILE_PATH="$(derive_structured_plan_path_from_context "${PLAN_CONTEXT_FILE}")"
    echo "[session] Non-structured --plan used as planning context: $(to_rel_path "${PLAN_CONTEXT_FILE}")"
    echo "[session] Structured plan output will be: $(to_rel_path "${PLAN_FILE_PATH}")"
  fi
  mkdir -p "$(dirname "${PLAN_FILE_PATH}")"
  STATE_FILE_PATH="$(state_file_path)"
  state_set_last_plan "${PLAN_FILE_PATH}"

  # Resolve optional guide file (-G/--guide)
  if [[ -n "${GUIDE_PATH}" ]]; then
    GUIDE_PATH="${GUIDE_PATH/#\~/$HOME}"
    if [[ "${GUIDE_PATH}" != /* ]]; then
      GUIDE_PATH="${CALLER_ROOT}/${GUIDE_PATH}"
    fi
    if [[ ! -f "${GUIDE_PATH}" ]]; then
      echo "warning: --guide file not found, continuing without guide: ${GUIDE_PATH}" >&2
      GUIDE_PATH=""
    elif [[ ! -r "${GUIDE_PATH}" ]]; then
      echo "warning: --guide file is not readable, continuing without guide: ${GUIDE_PATH}" >&2
      GUIDE_PATH=""
    else
      GUIDE_CONTENT="$(cat "${GUIDE_PATH}")"
    fi
  fi

  # Check codex CLI
  if [[ "${DRY_RUN}" -ne 1 ]] && ! command -v codex >/dev/null 2>&1; then
    echo "ERROR: 'codex' is not installed or not available in PATH." >&2
    echo "Install/setup Codex CLI and try again:" >&2
    echo "https://developers.openai.com/codex/cli/" >&2
    exit 1
  fi

  [[ -z "${TIMEOUT_SECONDS}" ]] && TIMEOUT_SECONDS=0 || true
}

reset_selected_plan_if_requested() {
  [[ "${RESET_PLAN}" -eq 1 ]] || return 0

  local plan_file backup_path
  plan_file="$(plan_json_path)"
  if [[ ! -f "${plan_file}" ]]; then
    echo "[session] --reset-plan: plan file not found, skipping: $(to_rel_path "${plan_file}")"
    return 0
  fi

  if ! command -v reset_plan_steps_to_pending >/dev/null 2>&1; then
    echo "[session] --reset-plan: helper missing (reset_plan_steps_to_pending), skipping"
    return 0
  fi

  if backup_path="$(reset_plan_steps_to_pending)"; then
    echo "[session] --reset-plan: all steps reset to pending"
    [[ -n "${backup_path}" ]] && echo "[session] --reset-plan: backup saved: $(to_rel_path "${backup_path}")"
  else
    echo "[session] --reset-plan: failed to reset plan" >&2
    exit 1
  fi
}

# =============================================================================
# Colors
# =============================================================================
setup_colors() {
  if [[ -t 1 ]] && [[ "${NO_COLORS}" -ne 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
  fi
}

# Session/path helpers are loaded from:
# - `.ralph/lib/core/session.sh`

# =============================================================================
# Engine Command
# =============================================================================
# =============================================================================
# AI Engine Execution
# =============================================================================

# Run AI engine via hook or built-in fallback
# Usage: run_ai_engine <prompt_file> <response_file> <engine_log> <step_index>
run_ai_engine() {
  local prompt_file="$1"
  local response_file="$2"
  local engine_log="$3"
  local i="$4"

  # Check for ai hook
  local ai_hook
  ai_hook=$(resolve_hook "ai")

  if [[ -n "${ai_hook}" ]]; then
    # Use ai hook
    run_ai_hook "${ai_hook}" "${prompt_file}" "${response_file}" "${engine_log}" "${i}"
  else
    # Fallback to built-in codex
    run_builtin_codex "${prompt_file}" "${response_file}" "${engine_log}" "${i}"
  fi
}

# Runs an AI command while emitting periodic terminal progress in interactive mode.
run_ai_command_with_indicator() {
  local engine_log="$1"
  shift

  local rc=0
  if [[ -t 1 ]] && [[ "${DRY_RUN}" -ne 1 ]]; then
    set +e
    (
      "$@"
    ) >> "${engine_log}" 2>&1 &
    local pid=$!
    local elapsed=0
    local printed=0
    while kill -0 "${pid}" 2>/dev/null; do
      sleep 1
      elapsed=$((elapsed + 1))
      # Keep progress on one terminal line instead of printing duplicates.
      printf '\r%sworking...%s %ss' "${C_MAGENTA}" "${C_RESET}" "${elapsed}"
      printed=1
    done
    if [[ "${printed}" -eq 1 ]]; then
      # Clear progress line before returning to normal output flow.
      printf '\r\033[K'
    fi
    wait "${pid}"
    rc=$?
    set -e
    return "${rc}"
  fi

  set +e
  (
    "$@"
  ) >> "${engine_log}" 2>&1
  rc=$?
  set -e
  return "${rc}"
}

# Run AI via hook
run_ai_hook() {
  local hook_path="$1"
  local prompt_file="$2"
  local response_file="$3"
  local engine_log="$4"
  local i="$5"
  local hook_depth="${RALPH_HOOK_DEPTH:-0}"

  # Export environment for hook
  export RALPH_PROMPT_FILE="${prompt_file}"
  export RALPH_RESPONSE_FILE="${response_file}"
  export RALPH_ENGINE="${ACTIVE_ENGINE:-${RALPH_ENGINE:-codex}}"
  export RALPH_SESSION_ID="${session_id}"
  export RALPH_SESSION_DIR="${session_dir}"
  export RALPH_WORKSPACE="${ROOT}"
  export RALPH_MODEL="${ACTIVE_MODEL:-${MODEL:-}}"
  export RALPH_TIMEOUT="${TIMEOUT_SECONDS:-0}"
  export RALPH_DRY_RUN="${DRY_RUN}"
  export RALPH_VERBOSE="${VERBOSE}"
  export RALPH_STEP="${i}"
  export RALPH_WORKFLOW_TYPE="${RALPH_WORKFLOW_TYPE:-$(state_get_workflow_type || true)}"
  export RALPH_TASKS_FILE="${TASKS_JSON_PATH:-}"

  # ai.sh handles dry-run internally (uses mock engine)
  if [[ "${TIMEOUT_SECONDS}" -gt 0 ]] && [[ "${DRY_RUN}" -ne 1 ]]; then
    local rc=0
    run_ai_command_with_indicator "${engine_log}" \
      timeout "${TIMEOUT_SECONDS}" \
      env RALPH_HOOK_DEPTH="$((hook_depth + 1))" "${hook_path}" || rc=$?
    [[ "${rc}" -eq 124 ]] && echo "ai hook timed out after ${TIMEOUT_SECONDS}s" >&2
    return "${rc}"
  fi

  run_ai_command_with_indicator "${engine_log}" \
    env RALPH_HOOK_DEPTH="$((hook_depth + 1))" "${hook_path}"
}

# Built-in codex execution (fallback when no ai hook)
run_builtin_codex() {
  local prompt_file="$1"
  local response_file="$2"
  local engine_log="$3"
  local i="$4"

  # Dry-run: generate mock response
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[ai] Engine: mock (built-in dry-run)" >> "${engine_log}"
    echo "[ai] Prompt: ${prompt_file}" >> "${engine_log}"

    local prompt_preview timestamp
    prompt_preview=$(head -c 200 "${prompt_file}" | tr '\n' ' ')
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "${response_file}" <<EOF
##### Mock AI Response (Built-in)

**Generated:** ${timestamp}
**Engine:** mock (built-in fallback)
**Step:** ${i}/${total_steps}

---

##### Summary

This is a simulated response from the built-in mock engine.

**Prompt preview:**
> ${prompt_preview}...

##### Actions Taken

- [mock] Analyzed prompt
- [mock] Simulated processing
- [mock] Generated placeholder response

---

*Generated by built-in mock for dry-run testing.*
EOF

    echo "[ai] Mock response: ${response_file}" >> "${engine_log}"
    echo "dry-run: mock response generated"
    return 0
  fi

  # Real execution
  local skip_flag=""
  [[ "${SKIP_GIT_CHECK}" -eq 1 ]] && skip_flag="--skip-git-repo-check "
  local selected_model="${ACTIVE_MODEL:-${MODEL:-}}"

  local cmd="codex exec --full-auto ${skip_flag}-C ${ROOT} -o ${response_file} - < ${prompt_file}"
  [[ -n "${selected_model}" ]] && cmd="codex exec --full-auto ${skip_flag}-C ${ROOT} --model ${selected_model} -o ${response_file} - < ${prompt_file}"

  if [[ "${TIMEOUT_SECONDS}" -gt 0 ]]; then
    set +e
    timeout "${TIMEOUT_SECONDS}" bash -lc "${cmd}" >> "${engine_log}" 2>&1
    local rc=$?
    set -e
    [[ "${rc}" -eq 124 ]] && echo "command timed out after ${TIMEOUT_SECONDS}s" >&2
    return "${rc}"
  fi

  eval "${cmd}" >> "${engine_log}" 2>&1
}

# =============================================================================
# Step Functions
# =============================================================================
build_prompt() {
  local i="$1"
  local prompt_file="$2"
  local step_id="${3:-}"
  local step_desc="${4:-}"
  local step_accept="${5:-}"

  {
    echo "You are running iterative self-correction in repository: $(basename "${ROOT}")"
    echo ""

    # If we have a plan step, use it as the focus
    if [[ -n "${step_id}" ]]; then
      local plan_goal
      plan_goal=$(get_plan_goal)
      echo "Overall goal: ${plan_goal:-${GOAL}}"
      echo ""
      echo "Current step: ${step_id}"
      echo "Task: ${step_desc}"
      echo "Acceptance criteria: ${step_accept}"
    else
      echo "Primary objective:"
      echo "${GOAL}"
    fi

    if [[ -n "${GUIDE_PATH}" ]]; then
      echo ""
      echo "Guide file: $(to_rel_path "${GUIDE_PATH}")"
      echo "${GUIDE_CONTENT}"
    fi
    echo ""
    echo "Files that MUST NOT be modified in this step:"
    if [[ "${ALLOW_RALPH_EDITS}" == "1" ]]; then
      echo "- (none; .ralph edits explicitly allowed for this run)"
    else
      echo "- .ralph/** (all files under .ralph are read-only)"
    fi
    if [[ -n "${GUIDE_PATH}" ]]; then
      echo "- $(to_rel_path "${GUIDE_PATH}") (read-only guide input)"
    fi
    echo ""
    echo "Constraints:"
    echo "1. Apply concrete edits directly in repo files when useful."
    if [[ "${ALLOW_RALPH_EDITS}" == "1" ]]; then
      echo "2. .ralph/ edits are allowed for this run."
    else
      echo "2. Only modify files outside .ralph/."
    fi
    echo "3. Keep changes coherent and minimal per step."
    echo "4. Focus ONLY on the current step. Do not work ahead."
    echo "5. At the end of this step, write a summary in English using markdown formatting."
    echo "6. Use headings (##### level), bullet points, and bold text for structure."
    echo ""
    echo "Previous step output (if any):"
    cat "${last_response}"
  } > "${prompt_file}"
}

print_step_header() {
  local i="$1"
  local total="${2:-${MAX_STEPS}}"
  local step_id="${3:-}"
  local display_engine="${4:-${ACTIVE_ENGINE:-${RALPH_ENGINE:-codex}}}"
  local display_model="${5:-${ACTIVE_MODEL:-}}"
  local mode_label mode_value timeout_value

  echo ""
  echo "${C_DIM}================================================================${C_RESET}"
  if [[ -n "${step_id}" ]]; then
    echo "${C_BOLD}${C_CYAN} RALPH STEP ${i}/${total}: ${step_id}${C_RESET}"
  else
    echo "${C_BOLD}${C_CYAN} RALPH ITERATION ${i}/${total}${C_RESET}"
  fi
  echo "${C_DIM}================================================================${C_RESET}"

  if [[ -n "${step_id}" ]]; then
    mode_label="step"
    mode_value="${step_id}"
  else
    mode_label="goal"
    mode_value="${GOAL}"
  fi
  timeout_value="$( [[ "${TIMEOUT_SECONDS}" -gt 0 ]] && echo "${TIMEOUT_SECONDS}s" || echo "disabled" )"

  echo "${C_DIM}+--------------------------------------------------------------+${C_RESET}"
  echo "${C_DIM}|${C_RESET} engine=${display_engine}"
  echo "${C_DIM}|${C_RESET} ${mode_label}=${mode_value}"
  [[ -n "${display_model}" ]] && echo "${C_DIM}|${C_RESET} model=${display_model}"
  echo "${C_DIM}|${C_RESET} plan_file=$(to_rel_path "$(plan_json_path)")"
  [[ -n "${GUIDE_PATH}" ]] && echo "${C_DIM}|${C_RESET} guide_file=$(to_rel_path "${GUIDE_PATH}")"
  echo "${C_DIM}|${C_RESET} timeout=${timeout_value}"
  echo "${C_DIM}+--------------------------------------------------------------+${C_RESET}"

}

check_step_errors() {
  local i="$1"
  local engine_log="$2"

  error_type=""
  error_hint=""

  [[ ! -f "${engine_log}" ]] && return

  if grep -qi "usage limit\|hit your.*limit\|rate limit" "${engine_log}" 2>/dev/null; then
    error_type="usage_limit"
    error_hint="Check your plan or wait for quota reset"
    echo "${C_RED}ERROR: API usage limit reached${C_RESET}" >&2
    echo "${C_YELLOW}${error_hint}${C_RESET}" >&2
  fi

  if grep -qi "unauthorized\|authentication\|auth.*fail\|invalid.*key\|API key" "${engine_log}" 2>/dev/null; then
    error_type="auth_failed"
    error_hint="Run 'codex' interactively to re-authenticate"
    echo "${C_RED}ERROR: Authentication failed${C_RESET}" >&2
    echo "${C_YELLOW}${error_hint}${C_RESET}" >&2
  fi
}


collect_response_stats() {
  local i="$1"
  local engine_log="$2"
  local rc="$3"

  if [[ -s "${last_response}" ]]; then
    response_lines="$(wc -l < "${last_response}" | tr -d ' ')"
    response_words="$(wc -w < "${last_response}" | tr -d ' ')"
    response_chars="$(wc -c < "${last_response}" | tr -d ' ')"
    detected_tokens="$(rg -oN '(total_tokens|output_tokens|input_tokens|tokens)[^0-9]{0,20}[0-9]+' "${last_response}" "${engine_log}" 2>/dev/null | head -n1 || true)"
  else
    response_lines=0
    response_words=0
    response_chars=0
    detected_tokens=""
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    result_label="dry-run"
  elif [[ "${rc}" -eq 124 ]]; then
    result_label="timeout"
  elif [[ "${rc}" -eq 0 ]]; then
    result_label="success"
  else
    result_label="error"
  fi

  tokens_label="${detected_tokens:-n/a}"
}

write_step_details() {
  local i="$1"
  local prompt_file="$2"
  local response_file="$3"
  local engine_log="$4"
  local rc="$5"
  local iter_start_iso="$6"
  local iter_end_iso="$7"
  local iter_duration_sec="$8"
  local total_steps="${9:-?}"

  # Stats row
  echo "| ${i}/${total_steps} | ${iter_start_iso} | ${iter_end_iso} | ${iter_duration_sec} | ${rc} | ${result_label} | ${response_lines} | ${response_words} | ${response_chars} | ${tokens_label} |" >> "${step_stats_rows_file}"

  # Details
  {
    echo ""
    echo "### Step ${i}/${total_steps}"
    echo ""
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| prompt_file | $(to_md_link "${prompt_file}") |"
    echo "| response_file | $(to_md_link "${response_file}") |"
    echo "| engine_file | $(to_md_link "${engine_log}") |"
    echo "| status | ${rc} |"
    echo "| result | ${result_label} |"
    [[ -n "${error_type}" ]] && echo "| error | ${error_type} |"
    [[ -n "${error_hint}" ]] && echo "| hint | ${error_hint} |"

    echo ""
    echo "#### Response"
    echo ""
    if [[ -s "${last_response}" ]]; then
      sed 's/^/> /' "${last_response}"
    elif [[ -n "${error_type}" ]]; then
      echo "> **Error:** ${error_type}"
      echo ">"
      echo "> ${error_hint}"
    else
      echo "> _(empty)_"
    fi
  } >> "${step_details_file}"
}

run_step() {
  local i="$1"
  local step_id="${2:-}"
  local step_desc="${3:-}"
  local step_accept="${4:-}"
  local prompt_file="${session_dir}/prompt_${i}.txt"
  local response_file="${session_dir}/response_${i}.md"
  local engine_log="${session_dir}/engine_${i}.md"
  local step_change_marker="${session_dir}/.step_${i}.start"
  local max_retries=3
  local retry_count=0
  local total_steps="${MAX_STEPS}"
  local change_log_file="${session_dir}/changes_step_${i}.md"

  touch "${step_change_marker}"

  # If plan-driven, show step info in header
  if [[ -n "${step_id}" ]]; then
    total_steps=$(get_step_count)
  elif [[ "${total_steps}" -eq 0 ]]; then
    total_steps="?"  # Unknown total for unlimited step mode
  fi

  resolve_agent_for_step "${step_id}" "${step_desc}"
  print_step_header "${i}" "${total_steps}" "${step_id}" "${ACTIVE_ENGINE}" "${ACTIVE_MODEL}"

  # Mark step as in_progress if plan-driven
  if [[ -n "${step_id}" ]]; then
    update_step_status "${step_id}" "in_progress"
  fi

  # Hook: before-step
  if ! run_required_step_hook "before-step" "${i}" "" "before-step hook failed"; then
    return 1
  fi

  # Retry loop when quality-gate requests another attempt.
  while true; do
    build_prompt "${i}" "${prompt_file}" "${step_id}" "${step_desc}" "${step_accept}"

    # Show what we're about to run
    local engine_name="${ACTIVE_ENGINE:-${RALPH_ENGINE:-codex}}"
    local ai_hook
    ai_hook=$(resolve_hook "ai")
    [[ -n "${ai_hook}" ]] && engine_name="${ACTIVE_ENGINE:-${RALPH_ENGINE:-codex}} (via hook)"

    echo "${C_BLUE}engine${C_RESET}: ${engine_name}"
    echo "${C_BLUE}prompt${C_RESET}: $(to_rel_path "${prompt_file}")"

    # Run AI engine
    local iter_start_epoch iter_start_iso iter_end_epoch iter_end_iso iter_duration_sec rc
    iter_start_epoch="$(date +%s)"
    iter_start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    set +e
    #run_ai_engine "${prompt_file}" "${response_file}" "${engine_log}" "${i}"
    rc=$?
    set -e

    if [[ -f "${response_file}" ]]; then
      last_response="${response_file}"
    fi

    iter_end_epoch="$(date +%s)"
    iter_end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    iter_duration_sec=$((iter_end_epoch - iter_start_epoch))

    # Process results
    check_step_errors "${i}" "${engine_log}"
    collect_response_stats "${i}" "${engine_log}" "${rc}"
    if [[ "${DRY_RUN}" -ne 1 ]] && [[ "${rc}" -eq 0 ]] && [[ "${response_chars}" -eq 0 ]]; then
      echo "${C_RED}[${i}/${total_steps}] ERROR: Empty response from ${ACTIVE_ENGINE:-${RALPH_ENGINE:-unknown}}${C_RESET}" >&2
      run_hook "on-error" "${i}" "${rc}"
      return 1
    fi
    write_step_details "${i}" "${prompt_file}" "${response_file}" "${engine_log}" "${rc}" "${iter_start_iso}" "${iter_end_iso}" "${iter_duration_sec}" "${total_steps}"

    # Print step duration
    echo "${C_BLUE}duration${C_RESET}: ${C_CYAN}${iter_duration_sec}s${C_RESET}"

    if [[ "${rc}" -ne 0 ]]; then
      echo "${C_RED}engine failed with status ${rc}${C_RESET}" >&2
      run_hook "on-error" "${i}" "${rc}"
      return 1
    fi

    local gate_action_rc
    if evaluate_quality_gate_action "${i}" "${rc}" "${retry_count}" "${max_retries}"; then
      gate_action_rc=0
    else
      gate_action_rc=$?
    fi
    case "${gate_action_rc}" in
      0) break ;;
      3)
        ((retry_count++))
        continue
        ;;
      130|143) return 130 ;;
      *) return 1 ;;
    esac
  done

  # Hook: after-step
  local after_step_rc=0
  set +e
  run_required_step_hook "after-step" "${i}" "0" "after-step hook failed"
  after_step_rc=$?
  set -e
  if [[ "${after_step_rc}" -eq 130 || "${after_step_rc}" -eq 143 ]]; then
    return 130
  fi
  if [[ "${after_step_rc}" -ne 0 ]]; then
    return 1
  fi

  if [[ -f "${change_log_file}" ]]; then
    {
      echo ""
      echo "#### Change Log"
      echo ""
      echo "- file: $(to_md_link "${change_log_file}")"
    } >> "${step_details_file}"
  fi

  return 0
}

# finalize_summary and print_completion are loaded from:
# - `.ralph/lib/core/session.sh`

# =============================================================================
# Main
# =============================================================================
main() {
  check_docker_delegation "$@"
  parse_args "$@"
  validate_args
  reset_selected_plan_if_requested
  setup_colors
  print_verbose_runtime_config
  setup_session
  write_summary_header

  # Hook: before-session
  local hook_rc
  set +e
  run_hook "before-session"
  hook_rc=$?
  set -e
  if [[ "${hook_rc}" -eq 1 ]]; then
    echo "${C_RED}[session] before-session hook failed, aborting${C_RESET}" >&2
    finalize_summary
    exit 1
  fi
  if [[ "${hook_rc}" -eq 130 || "${hook_rc}" -eq 143 ]]; then
    echo "${C_YELLOW}[session] before-session interrupted${C_RESET}" >&2
    finalize_summary
    exit 130
  fi

  local session_failed=0
  local session_interrupted=0
  local completed_steps=0

  # Check if plan-driven mode (plan.json exists after before-session)
  if plan_exists; then
    echo "${C_CYAN}[session]${C_RESET} Plan-driven mode: $(plan_json_path)"
    local pending_count
    pending_count=$(get_pending_count)
    echo "${C_CYAN}[session]${C_RESET} Pending steps: ${pending_count}"

    local i=1
    # MAX_STEPS=0 means no limit (run all pending)
    # MAX_STEPS>0 means run up to that many steps
    local step_limit="${MAX_STEPS}"
    local plan_step_limit
    plan_step_limit="$(get_plan_max_steps)"
    if [[ "${plan_step_limit}" =~ ^[0-9]+$ ]] && [[ "${plan_step_limit}" -gt 0 ]]; then
      if [[ "${step_limit}" -eq 0 ]] || [[ "${step_limit}" -gt "${plan_step_limit}" ]]; then
        step_limit="${plan_step_limit}"
      fi
      echo "${C_CYAN}[session]${C_RESET} Plan max_steps applied: ${plan_step_limit}"
    fi
    [[ "${step_limit}" -eq 0 ]] && step_limit=999999  # Effectively unlimited

    while [[ "${i}" -le "${step_limit}" ]]; do
      # Get next pending step
      local step_json step_id step_desc step_accept
      step_json=$(get_current_step)

      # No more pending steps
      if [[ -z "${step_json}" ]]; then
        echo "${C_GREEN}[session]${C_RESET} All plan steps completed"
        break
      fi

      step_id=$(echo "${step_json}" | jq -r '.id')
      step_desc=$(echo "${step_json}" | jq -r '.description')
      step_accept=$(echo "${step_json}" | jq -r '.acceptance')

      local step_rc=0
      set +e
      run_step "${i}" "${step_id}" "${step_desc}" "${step_accept}"
      step_rc=$?
      set -e
      if [[ "${step_rc}" -eq 130 || "${step_rc}" -eq 143 ]]; then
        session_interrupted=1
        break
      fi
      if [[ "${step_rc}" -ne 0 ]]; then
        session_failed=1
        break
      fi

      # Mark step as completed
      update_step_status "${step_id}" "completed"
      ((completed_steps++)) || true
      ((i++))
    done

    # Check if we hit step limit before completing all steps
    pending_count=$(get_pending_count)
    if [[ "${pending_count}" -gt 0 ]] && [[ "${session_failed}" -eq 0 ]] && [[ "${MAX_STEPS}" -gt 0 ]]; then
      echo "${C_YELLOW}[session]${C_RESET} Step limit (${MAX_STEPS}) reached, ${pending_count} steps remaining"
    fi
  else
    # Fallback: step-based mode (no plan)
    # MAX_STEPS=0 defaults to 1 step in this mode
    local num_steps="${MAX_STEPS}"
    [[ "${num_steps}" -eq 0 ]] && num_steps=1

    echo "${C_CYAN}[session]${C_RESET} Step mode: ${num_steps} step(s)"

    for ((i=1; i<=num_steps; i++)); do
      local step_rc=0
      set +e
      run_step "${i}"
      step_rc=$?
      set -e
      if [[ "${step_rc}" -eq 130 || "${step_rc}" -eq 143 ]]; then
        session_interrupted=1
        break
      fi
      if [[ "${step_rc}" -ne 0 ]]; then
        session_failed=1
        break
      fi
      ((completed_steps++)) || true
    done
  fi

  # Hook: after-session
  set +e
  run_hook "after-session"
  set -e

  finalize_summary
  print_completion "${completed_steps}"

  [[ "${session_interrupted}" -eq 1 ]] && exit 130
  [[ "${session_failed}" -eq 1 ]] && exit 1
  exit 0
}

main "$@"
