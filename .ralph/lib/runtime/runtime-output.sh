#!/usr/bin/env bash
# Shared runtime UI helpers for Ralph orchestrator.
set -euo pipefail

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

verbose_log() {
  [[ "${VERBOSE}" -eq 1 ]] || return 0
  echo "${C_DIM}[debug]${C_RESET} $*"
}

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
