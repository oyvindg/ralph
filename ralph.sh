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
  local ralph_env_lib="${SCRIPT_DIR}/.ralph/lib/runtime/env.sh"
  if [[ -f "${ralph_env_lib}" ]]; then
    # shellcheck disable=SC1090
    source "${ralph_env_lib}"
    init_ralph_env_defaults
  else
    echo "ERROR: missing runtime env helpers: ${ralph_env_lib}" >&2
    exit 1
  fi

  # =============================================================================
  # Global Variables
  # =============================================================================
  CALLER_ROOT="$(pwd)"
  ROOT="${CALLER_ROOT}"
  WORKSPACE=""
  MAX_STEPS=0  # 0 = no limit (run all pending steps); this is an internal counter kept unprefixed.
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
cli_lib="${SCRIPT_DIR}/.ralph/lib/runtime/cli.sh"
if [[ -f "${cli_lib}" ]]; then
  # shellcheck disable=SC1090
  source "${cli_lib}"
else
  echo "ERROR: CLI helper library missing: ${cli_lib}" >&2
  exit 1
fi

# =============================================================================
# Docker Functions (delegated to .ralph/lib/docker.sh)
# =============================================================================
export RALPH_SCRIPT_DIR="${SCRIPT_DIR}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/.ralph/lib/docker.sh"

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
    "runtime/hooks-runtime.sh"
    "runtime/runtime-output.sh"
    "runtime/ai.sh"
    "runtime/step-runtime.sh"
    "runtime/agent-routing.sh"
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

# Plan helpers are loaded from:
# - `.ralph/lib/core/plan.sh`
# Step/runtime helpers are loaded from:
# - `.ralph/lib/runtime/step-runtime.sh`
# - `.ralph/lib/runtime/runtime-output.sh`

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

# CLI helpers (usage/parse/validation) live in .ralph/lib/runtime/cli.sh, sourced at startup.
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

#
#
#
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

  # Hook: bootstrap (validation and environment setup)
  # Runs after arg parsing but before session setup
  run_required_hook "bootstrap"

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
