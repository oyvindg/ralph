#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Global Variables
# =============================================================================
CALLER_ROOT="$(pwd)"
ROOT="${CALLER_ROOT}"
WORKSPACE=""
ITERATIONS=3
PROMPT=""
PLAN_PATH=""
PLAN_CONTENT=""
DRY_RUN=0
TIMEOUT_SECONDS=""
MODEL=""
NO_COLORS=0
SKIP_GIT_CHECK=0

# Session variables (set in setup_session)
session_dir=""
summary_md=""
last_response=""
prompt_input_file=""
iteration_stats_rows_file=""
iteration_details_file=""
session_id=""
session_start_epoch=""
session_start_iso=""
total_duration_sec=0

# Color variables (set in setup_colors)
C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""

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

  # Parse args to find workspace (-w) and plan (-P) paths for mounting
  declare -A MOUNT_PATHS
  local DOCKER_ARGS=()
  local DOCKER_WORKSPACE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -w|--workspace)
        DOCKER_WORKSPACE="$(cd "${2/#\~/$HOME}" && pwd)"
        MOUNT_PATHS["${DOCKER_WORKSPACE}"]=1
        DOCKER_ARGS+=("$1" "${DOCKER_WORKSPACE}")
        shift 2
        ;;
      -P|--plan)
        local plan_path="${2/#\~/$HOME}"
        plan_path="$(cd "$(dirname "${plan_path}")" && pwd)/$(basename "${plan_path}")"
        MOUNT_PATHS["$(dirname "${plan_path}")"]=1
        DOCKER_ARGS+=("$1" "${plan_path}")
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
# Usage
# =============================================================================
usage() {
  cat <<EOF
Usage:
  ./ralph.sh -i <N> -p "<prompt>" [options]

Required:
  -i, --iterations <N>    Number of iterations (positive integer)
  -p, --prompt "<text>"   Objective passed into each iteration

Options:
  -P, --plan <file>       Guidance file (e.g., AGENTS.md)
  -w, --workspace <path>  Workspace directory (default: current dir)
  -m, --model <name>      Codex model name (default: codex default)
  -t, --timeout <sec>     Timeout per iteration in seconds (0 = disabled)
      --no-colors         Disable ANSI colors in output
      --skip-git-repo-check  Allow running in non-git directories
      --docker            Run in docker container
      --docker-build      Build docker image only
      --docker-rebuild    Run in docker, rebuild image first
  -d, --dry-run           Print commands without executing

Examples:
  ./ralph.sh -i 3 -p "Improve test coverage"
  ./ralph.sh -i 5 -p "Refactor auth module" -P AGENTS.md -m gpt-5.3-codex
  ./ralph.sh -i 2 -p "Debug build" --dry-run
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
      --iterations|-i) ITERATIONS="${2:-}"; shift 2 ;;
      --prompt|-p) PROMPT="${2:-}"; shift 2 ;;
      --plan|-P) PLAN_PATH="${2:-}"; shift 2 ;;
      --workspace|-w) WORKSPACE="${2:-}"; shift 2 ;;
      --model|-m) MODEL="${2:-}"; shift 2 ;;
      --timeout|-t) TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
      --dry-run|-d) DRY_RUN=1; shift ;;
      --no-colors) NO_COLORS=1; shift ;;
      --skip-git-repo-check) SKIP_GIT_CHECK=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
  done
}

validate_args() {
  if ! [[ "${ITERATIONS}" =~ ^[0-9]+$ ]] || [[ "${ITERATIONS}" -lt 1 ]]; then
    echo "--iterations must be a positive integer" >&2
    exit 1
  fi

  if [[ -n "${TIMEOUT_SECONDS}" ]] && { ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${TIMEOUT_SECONDS}" -lt 0 ]]; }; then
    echo "--timeout must be an integer >= 0" >&2
    exit 1
  fi

  if [[ -z "${PROMPT}" ]]; then
    echo "--prompt is required" >&2
    exit 1
  fi

  if [[ -n "${MODEL}" ]] && [[ -z "${MODEL// }" ]]; then
    echo "--model cannot be empty" >&2
    exit 1
  fi

  if [[ -n "${PLAN_PATH}" ]]; then
    if [[ ! -f "${PLAN_PATH}" ]]; then
      echo "warning: --plan file not found, continuing without plan: ${PLAN_PATH}" >&2
      PLAN_PATH=""
    elif [[ ! -r "${PLAN_PATH}" ]]; then
      echo "warning: --plan file is not readable, continuing without plan: ${PLAN_PATH}" >&2
      PLAN_PATH=""
    else
      PLAN_CONTENT="$(cat "${PLAN_PATH}")"
    fi
  fi

  if [[ -n "${WORKSPACE// }" ]]; then
    if [[ ! -d "${WORKSPACE}" ]]; then
      echo "ERROR: --workspace path not found or not a directory: ${WORKSPACE}" >&2
      exit 1
    fi
    ROOT="$(cd "${WORKSPACE}" && pwd)"
  else
    ROOT="${CALLER_ROOT}"
  fi

  if [[ "${DRY_RUN}" -ne 1 ]] && ! command -v codex >/dev/null 2>&1; then
    echo "ERROR: 'codex' is not installed or not available in PATH." >&2
    echo "Install/setup Codex CLI and try again:" >&2
    echo "https://developers.openai.com/codex/cli/" >&2
    exit 1
  fi

  [[ -z "${TIMEOUT_SECONDS}" ]] && TIMEOUT_SECONDS=0
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
    C_CYAN=$'\033[36m'
  fi
}

# =============================================================================
# Path Utilities
# =============================================================================
to_rel_path() {
  local p="$1"
  if [[ "${p}" == "${ROOT}/"* ]]; then
    printf '%s' "${p#${ROOT}/}"
  elif [[ "${p}" == "${HOME}" ]]; then
    printf '%s' "~"
  elif [[ "${p}" == "${HOME}/"* ]]; then
    printf '~/%s' "${p#${HOME}/}"
  else
    printf '%s' "${p}"
  fi
}

to_summary_href() {
  local p="$1"
  if [[ "${p}" == "${session_dir}/"* ]]; then
    printf './%s' "${p#${session_dir}/}"
  elif [[ "${p}" == "${session_dir}" ]]; then
    printf '.'
  else
    printf '%s' "${p}"
  fi
}

to_md_link() {
  local p="$1"
  printf '[%s](%s)' "$(to_rel_path "${p}")" "$(to_summary_href "${p}")"
}

# =============================================================================
# Session Setup
# =============================================================================
setup_session() {
  local sessions_root="${ROOT}/sessions"
  mkdir -p "${sessions_root}"

  session_id="$(date +%Y%m%d_%H%M%S)_$$"
  session_dir="${sessions_root}/${session_id}"
  mkdir -p "${session_dir}"

  last_response="${session_dir}/last_response.md"
  summary_md="${session_dir}/summary.md"
  prompt_input_file="${session_dir}/prompt_input.txt"
  iteration_stats_rows_file="${session_dir}/.iteration_stats_rows.tmp"
  iteration_details_file="${session_dir}/.iteration_details.tmp"
  session_start_epoch="$(date +%s)"
  session_start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  touch "${last_response}" "${iteration_stats_rows_file}" "${iteration_details_file}"
  printf '%s\n' "${PROMPT}" > "${prompt_input_file}"
}

write_summary_header() {
  {
    echo "# Ralph Session Summary"
    echo ""
    echo "## Session Metadata"
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| session_id | ${session_id} |"
    echo "| repository | . |"
    echo "| runner | codex |"
    echo "| model | ${MODEL:-default codex model} |"
    echo "| iterations | ${ITERATIONS} |"
    echo "| prompt_file | $(to_md_link "${prompt_input_file}") |"
    echo "| plan_file | ${PLAN_PATH:+$(to_md_link "${PLAN_PATH}")}${PLAN_PATH:-"(none)"} |"
    echo "| timeout_seconds | $( [[ "${TIMEOUT_SECONDS}" -gt 0 ]] && echo "${TIMEOUT_SECONDS}" || echo "disabled" ) |"
    echo "| session_start_utc | ${session_start_iso} |"
    echo "| session_start_epoch | ${session_start_epoch} |"
    echo ""
    echo "## Prompt"
    echo ""
    echo "${PROMPT}" | sed 's/^/> /'
    echo ""
    if [[ -n "${PLAN_PATH}" ]]; then
      echo "## Plan"
      echo ""
      echo "Source: $(to_md_link "${PLAN_PATH}")"
      echo ""
    fi
  } > "${summary_md}"
}

# =============================================================================
# Engine Command
# =============================================================================
run_engine_command() {
  local cmd="$1"
  local engine_log="$2"
  local i="$3"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ${cmd}" >> "${engine_log}"
    echo "[${i}/${ITERATIONS}] dry-run enabled, skipping execution"
    return 0
  fi

  if [[ "${TIMEOUT_SECONDS}" -gt 0 ]]; then
    set +e
    timeout "${TIMEOUT_SECONDS}" bash -lc "${cmd}" >> "${engine_log}" 2>&1
    local rc=$?
    set -e
    [[ "${rc}" -eq 124 ]] && echo "[${i}/${ITERATIONS}] command timed out after ${TIMEOUT_SECONDS}s" >&2
    return "${rc}"
  fi

  eval "${cmd}" >> "${engine_log}" 2>&1
}

# =============================================================================
# Iteration Functions
# =============================================================================
build_prompt() {
  local i="$1"
  local prompt_file="$2"

  {
    echo "You are running iterative self-correction in repository: ${ROOT}"
    echo ""
    echo "Primary objective:"
    echo "${PROMPT}"
    if [[ -n "${PLAN_PATH}" ]]; then
      echo ""
      echo "Plan file: $(to_rel_path "${PLAN_PATH}")"
      echo "${PLAN_CONTENT}"
    fi
    echo ""
    echo "Constraints:"
    echo "1. Apply concrete edits directly in repo files when useful."
    echo "2. Keep changes coherent and minimal per iteration."
    echo "3. At the end of this iteration, write a summary in English using markdown formatting."
    echo "4. Use headings (##### level), bullet points, and bold text for structure."
    echo ""
    echo "Previous iteration output (if any):"
    cat "${last_response}"
  } > "${prompt_file}"
}

print_iteration_header() {
  local i="$1"

  echo ""
  echo "${C_DIM}================================================================${C_RESET}"
  echo "${C_BOLD}${C_CYAN} RALPH LOOP ITERATION ${i}/${ITERATIONS}${C_RESET}"
  echo "${C_DIM}================================================================${C_RESET}"

  echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} runner=codex"
  echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} prompt=${PROMPT}"
  [[ -n "${MODEL}" ]] && echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} model=${MODEL}"
  [[ -n "${PLAN_PATH}" ]] && echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} plan_file=$(to_rel_path "${PLAN_PATH}")"
  echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} timeout=$( [[ "${TIMEOUT_SECONDS}" -gt 0 ]] && echo "${TIMEOUT_SECONDS}s" || echo "disabled" )"
}

check_iteration_errors() {
  local i="$1"
  local engine_log="$2"

  error_type=""
  error_hint=""

  [[ ! -f "${engine_log}" ]] && return

  if grep -qi "usage limit\|hit your.*limit\|rate limit" "${engine_log}" 2>/dev/null; then
    error_type="usage_limit"
    error_hint="Check your plan or wait for quota reset"
    echo "${C_RED}[${i}/${ITERATIONS}] ERROR: API usage limit reached${C_RESET}" >&2
    echo "${C_YELLOW}[${i}/${ITERATIONS}] ${error_hint}${C_RESET}" >&2
  fi

  if grep -qi "unauthorized\|authentication\|auth.*fail\|invalid.*key\|API key" "${engine_log}" 2>/dev/null; then
    error_type="auth_failed"
    error_hint="Run 'codex' interactively to re-authenticate"
    echo "${C_RED}[${i}/${ITERATIONS}] ERROR: Authentication failed${C_RESET}" >&2
    echo "${C_YELLOW}[${i}/${ITERATIONS}] ${error_hint}${C_RESET}" >&2
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
    if [[ "${DRY_RUN}" -ne 1 ]] && [[ "${rc}" -eq 0 ]]; then
      echo "${C_YELLOW}[${i}/${ITERATIONS}] WARNING: Empty response from codex${C_RESET}" >&2
    fi
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

write_iteration_details() {
  local i="$1"
  local prompt_file="$2"
  local engine_log="$3"
  local rc="$4"
  local iter_start_iso="$5"
  local iter_end_iso="$6"
  local iter_duration_sec="$7"

  # Stats row
  echo "| ${i}/${ITERATIONS} | ${iter_start_iso} | ${iter_end_iso} | ${iter_duration_sec} | ${rc} | ${result_label} | ${response_lines} | ${response_words} | ${response_chars} | ${tokens_label} |" >> "${iteration_stats_rows_file}"

  # Details
  {
    echo ""
    echo "### Iteration ${i}/${ITERATIONS}"
    echo ""
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| prompt_file | $(to_md_link "${prompt_file}") |"
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
  } >> "${iteration_details_file}"
}

run_iteration() {
  local i="$1"
  local prompt_file="${session_dir}/prompt_${i}.txt"
  local engine_log="${session_dir}/engine_${i}.md"

  print_iteration_header "${i}"
  build_prompt "${i}" "${prompt_file}"

  # Build command
  local skip_flag=""
  [[ "${SKIP_GIT_CHECK}" -eq 1 ]] && skip_flag="--skip-git-repo-check "

  local cmd="codex exec --full-auto ${skip_flag}-C ${ROOT} -o ${last_response} - < ${prompt_file}"
  [[ -n "${MODEL}" ]] && cmd="codex exec --full-auto ${skip_flag}-C ${ROOT} --model ${MODEL} -o ${last_response} - < ${prompt_file}"

  local display_cmd="codex exec --full-auto ${skip_flag}-C . -o $(to_rel_path "${last_response}") - < $(to_rel_path "${prompt_file}")"
  [[ -n "${MODEL}" ]] && display_cmd="codex exec --full-auto ${skip_flag}-C . --model ${MODEL} -o $(to_rel_path "${last_response}") - < $(to_rel_path "${prompt_file}")"

  echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} command: ${display_cmd}"

  # Run
  local iter_start_epoch iter_start_iso iter_end_epoch iter_end_iso iter_duration_sec rc
  iter_start_epoch="$(date +%s)"
  iter_start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  set +e
  run_engine_command "${cmd}" "${engine_log}" "${i}"
  rc=$?
  set -e

  iter_end_epoch="$(date +%s)"
  iter_end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  iter_duration_sec=$((iter_end_epoch - iter_start_epoch))

  # Process results
  check_iteration_errors "${i}" "${engine_log}"
  collect_response_stats "${i}" "${engine_log}" "${rc}"
  write_iteration_details "${i}" "${prompt_file}" "${engine_log}" "${rc}" "${iter_start_iso}" "${iter_end_iso}" "${iter_duration_sec}"

  # Print iteration duration
  echo "${C_BLUE}[${i}/${ITERATIONS}]${C_RESET} duration: ${C_CYAN}${iter_duration_sec}s${C_RESET}"

  if [[ "${rc}" -ne 0 ]]; then
    echo "${C_RED}[${i}/${ITERATIONS}] iteration failed with status ${rc}${C_RESET}" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# Finalize
# =============================================================================
finalize_summary() {
  local session_end_epoch session_end_iso
  session_end_epoch="$(date +%s)"
  session_end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  total_duration_sec=$((session_end_epoch - session_start_epoch))

  {
    echo ""
    echo "## Iteration Stats"
    echo "| Iteration | Start (UTC) | End (UTC) | Duration (s) | Status | Result | Lines | Words | Chars | Tokens |"
    echo "|---|---|---|---:|---:|---|---:|---:|---:|---|"
    cat "${iteration_stats_rows_file}"
    echo ""
    echo "## Iteration Details"
    cat "${iteration_details_file}"
    echo ""
    echo "## Session Metrics"
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| session_end_utc | ${session_end_iso} |"
    echo "| session_end_epoch | ${session_end_epoch} |"
    echo "| session_duration_seconds | ${total_duration_sec} |"
  } >> "${summary_md}"

  rm -f "${iteration_stats_rows_file}" "${iteration_details_file}"
}

print_completion() {
  echo ""
  echo "${C_BOLD}${C_GREEN}Ralph loop completed (${ITERATIONS} iterations) in ${C_CYAN}${total_duration_sec}s${C_GREEN}${C_RESET}"
  echo "${C_GREEN}Session files:${C_RESET} $(to_rel_path "${session_dir}")"
  echo "${C_GREEN}Summary file:${C_RESET} $(to_rel_path "${summary_md}")"
}

# =============================================================================
# Main
# =============================================================================
main() {
  check_docker_delegation "$@"
  parse_args "$@"
  validate_args
  setup_colors
  setup_session
  write_summary_header

  for ((i=1; i<=ITERATIONS; i++)); do
    if ! run_iteration "${i}"; then
      break
    fi
  done

  finalize_summary
  print_completion
}

main "$@"
