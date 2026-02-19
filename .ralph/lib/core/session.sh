#!/usr/bin/env bash
# Session/file presentation helpers for Ralph orchestrator.
set -euo pipefail

# Converts an absolute path to workspace- or home-relative display path.
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

# Converts a path to summary-local href when possible.
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

# Builds markdown link with readable path text.
to_md_link() {
  local p="$1"
  printf '[%s](%s)' "$(to_rel_path "${p}")" "$(to_summary_href "${p}")"
}

# Initializes session output files and metadata.
setup_session() {
  local sessions_root="${ROOT}/.ralph/sessions"
  mkdir -p "${sessions_root}"

  session_id="$(date +%Y%m%d_%H%M%S)_$$"
  session_dir="${sessions_root}/${session_id}"
  mkdir -p "${session_dir}"

  summary_md="${session_dir}/summary.md"
  prompt_input_file="${session_dir}/prompt_input.txt"
  step_stats_rows_file="${session_dir}/.step_stats_rows.tmp"
  step_details_file="${session_dir}/.step_details.tmp"
  session_start_epoch="$(date +%s)"
  session_start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  last_response="${session_dir}/.last_response.tmp"
  touch "${last_response}" "${step_stats_rows_file}" "${step_details_file}"
  printf '%s\n' "${GOAL}" > "${prompt_input_file}"

  # Guide is treated as read-only input. Keep a session snapshot for integrity checks.
  if [[ -n "${GUIDE_PATH:-}" ]] && [[ -f "${GUIDE_PATH}" ]]; then
    cp -a "${GUIDE_PATH}" "${session_dir}/.guide_snapshot"
  fi
}

# Writes summary header metadata before steps begin.
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
    echo "| engine_default | ${RALPH_ENGINE:-codex} |"
    echo "| model | ${MODEL:-default codex model} |"
    echo "| ticket | ${TICKET:-"(none)"} |"
    echo "| issues_providers | ${ISSUES_PROVIDERS} |"
    echo "| source_control_enabled | ${SOURCE_CONTROL_ENABLED} |"
    echo "| source_control_backend | ${SOURCE_CONTROL_BACKEND} |"
    echo "| source_control_allow_commits | ${SOURCE_CONTROL_ALLOW_COMMITS} |"
    echo "| source_control_branch_per_session | ${SOURCE_CONTROL_BRANCH_PER_SESSION} |"
    echo "| source_control_branch_name_template | ${SOURCE_CONTROL_BRANCH_NAME_TEMPLATE} |"
    echo "| source_control_require_ticket_for_branch | ${SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH} |"
    echo "| checkpoint_enabled | ${CHECKPOINT_ENABLED} |"
    echo "| checkpoint_per_step | ${CHECKPOINT_PER_STEP} |"
    echo "| max_steps | $( [[ "${MAX_STEPS}" -eq 0 ]] && echo "unlimited" || echo "${MAX_STEPS}" ) |"
    echo "| prompt_file | $(to_md_link "${prompt_input_file}") |"
    echo "| plan_file | $(to_md_link "$(plan_json_path)") |"
    if [[ -n "${GUIDE_PATH}" ]]; then
      echo "| guide_file | $(to_md_link "${GUIDE_PATH}") |"
    else
      echo "| guide_file | (none) |"
    fi
    echo "| timeout_seconds | $( [[ "${TIMEOUT_SECONDS}" -gt 0 ]] && echo "${TIMEOUT_SECONDS}" || echo "disabled" ) |"
    echo "| human_guard | ${HUMAN_GUARD} |"
    echo "| human_guard_assume_yes | ${HUMAN_GUARD_ASSUME_YES} |"
    echo "| human_guard_scope | ${HUMAN_GUARD_SCOPE} |"
    echo "| session_start_utc | ${session_start_iso} |"
    echo "| session_start_epoch | ${session_start_epoch} |"
    echo ""
    echo "## Goal"
    echo ""
    echo "${GOAL}" | sed 's/^/> /'
    echo ""
    echo "## Plan"
    echo ""
    echo "Source: $(to_md_link "$(plan_json_path)")"
    echo ""
    if [[ -n "${GUIDE_PATH}" ]]; then
      echo "## Guide"
      echo ""
      echo "Source: $(to_md_link "${GUIDE_PATH}")"
      echo ""
    fi
  } > "${summary_md}"
}

# Appends step tables and session timing to summary.
finalize_summary() {
  local session_end_epoch session_end_iso
  session_end_epoch="$(date +%s)"
  session_end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  total_duration_sec=$((session_end_epoch - session_start_epoch))

  {
    echo ""
    echo "## Step Stats"
    echo "| Step | Start (UTC) | End (UTC) | Duration (s) | Status | Result | Lines | Words | Chars | Tokens |"
    echo "|---|---|---|---:|---:|---|---:|---:|---:|---|"
    cat "${step_stats_rows_file}"
    echo ""
    echo "## Step Details"
    cat "${step_details_file}"
    echo ""
    echo "## Session Metrics"
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| session_end_utc | ${session_end_iso} |"
    echo "| session_end_epoch | ${session_end_epoch} |"
    echo "| session_duration_seconds | ${total_duration_sec} |"
  } >> "${summary_md}"

  rm -f "${step_stats_rows_file}" "${step_details_file}"
}

# Prints completion summary to terminal.
print_completion() {
  local completed="${1:-0}"
  echo ""
  if plan_exists; then
    local total pending
    total="$(get_step_count)"
    pending="$(get_pending_count)"
    echo "${C_BOLD}${C_GREEN}Ralph completed (${completed}/${total} steps) in ${C_CYAN}${total_duration_sec}s${C_GREEN}${C_RESET}"
    [[ "${pending}" -gt 0 ]] && echo "${C_YELLOW}Remaining: ${pending} steps pending${C_RESET}"
  else
    echo "${C_BOLD}${C_GREEN}Ralph completed (${completed} step(s)) in ${C_CYAN}${total_duration_sec}s${C_GREEN}${C_RESET}"
  fi
  echo "${C_GREEN}Session files:${C_RESET} $(to_rel_path "${session_dir}")"
  echo "${C_GREEN}Summary file:${C_RESET} $(to_rel_path "${summary_md}")"
}
