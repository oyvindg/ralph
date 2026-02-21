#!/usr/bin/env bash
# CLI helpers for the Ralph orchestrator.
set -euo pipefail

usage() {
  cat <<'USAGE'
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
USAGE
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

  : "${RALPH_SOURCE_CONTROL_ENABLED:=${PROFILE_SOURCE_CONTROL_ENABLED:-1}}"
  : "${RALPH_SOURCE_CONTROL_BACKEND:=${PROFILE_SOURCE_CONTROL_BACKEND:-auto}}"
  : "${RALPH_SOURCE_CONTROL_ALLOW_COMMITS:=${PROFILE_SOURCE_CONTROL_ALLOW_COMMITS:-0}}"
  : "${RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION:=${PROFILE_SOURCE_CONTROL_BRANCH_PER_SESSION:-0}}"
  : "${RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE:=${PROFILE_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE:-ralph/{ticket}/{goal_slug}/{session_id}}}"
  : "${RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH:=${PROFILE_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH:-0}}"
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

  RALPH_SOURCE_CONTROL_BACKEND="$(printf '%s' "${RALPH_SOURCE_CONTROL_BACKEND}" | tr '[:upper:]' '[:lower:]')"
  case "${RALPH_SOURCE_CONTROL_BACKEND}" in
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

  case "${RALPH_SOURCE_CONTROL_ENABLED}" in
    1|true|TRUE|yes|YES) RALPH_SOURCE_CONTROL_ENABLED=1 ;;
    0|false|FALSE|no|NO) RALPH_SOURCE_CONTROL_ENABLED=0 ;;
    *) echo "source_control_enabled must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${RALPH_SOURCE_CONTROL_ALLOW_COMMITS}" in
    1|true|TRUE|yes|YES) RALPH_SOURCE_CONTROL_ALLOW_COMMITS=1 ;;
    0|false|FALSE|no|NO) RALPH_SOURCE_CONTROL_ALLOW_COMMITS=0 ;;
    *) echo "source_control_allow_commits must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION}" in
    1|true|TRUE|yes|YES) RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION=1 ;;
    0|false|FALSE|no|NO) RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION=0 ;;
    *) echo "source_control_branch_per_session must be 0/1 (or true/false)" >&2; exit 1 ;;
  esac
  case "${RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH}" in
    1|true|TRUE|yes|YES) RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=1 ;;
    0|false|FALSE|no|NO) RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH=0 ;;
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
