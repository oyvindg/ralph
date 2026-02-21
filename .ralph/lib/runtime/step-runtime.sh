#!/usr/bin/env bash
# Step presentation and metrics helpers for Ralph orchestrator.
set -euo pipefail

build_prompt() {
  local i="$1"
  local prompt_file="$2"
  local step_id="${3:-}"
  local step_desc="${4:-}"
  local step_accept="${5:-}"

  {
    echo "You are running iterative self-correction in repository: $(basename "${ROOT}")"
    echo ""

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

  echo "| ${i}/${total_steps} | ${iter_start_iso} | ${iter_end_iso} | ${iter_duration_sec} | ${rc} | ${result_label} | ${response_lines} | ${response_words} | ${response_chars} | ${tokens_label} |" >> "${step_stats_rows_file}"

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
