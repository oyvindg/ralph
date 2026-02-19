#!/usr/bin/env bash
# Before session hook - runs once at session start
#
# Responsibilities:
# - Run planning hook to ensure plan exists
# - Setup, validation, notifications
#
# Exit codes:
#   0 = success, continue
#   1 = abort session

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_SESSION_APPROVED=0

## Loads shared logging helpers, with local fallback no-op implementations.
setup_logging() {
  if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOOKS_DIR}/../lib/log.sh"
  else
    ralph_log() { echo "[$2] $3"; }
    ralph_event() { :; }
  fi
}

setup_ui() {
  if [[ -f "${HOOKS_DIR}/../lib/ui.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOOKS_DIR}/../lib/ui.sh"
  fi
}

## Loads source-control helpers for branch/session policy checks.
setup_source_control() {
  if [[ -f "${HOOKS_DIR}/../lib/source-control.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOOKS_DIR}/../lib/source-control.sh"
  fi
}

## Loads checkpoint helpers used for filesystem rollback safety.
setup_checkpoint() {
  if [[ -f "${HOOKS_DIR}/../lib/checkpoint.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOOKS_DIR}/../lib/checkpoint.sh"
  fi
}

setup_colors() {
  C_RESET=""
  C_DIM=""
  C_YELLOW=""
  C_GREEN=""
  C_RED=""
  C_CYAN=""
  if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
  fi
}

## Logs high-level session context before any checks/hooks run.
log_session_start() {
  ralph_log "INFO" "before-session" "Session ${RALPH_SESSION_ID} starting"
  ralph_log "INFO" "before-session" "Workspace: ${RALPH_WORKSPACE}"
  if [[ "${RALPH_STEPS}" -eq 0 ]]; then
    ralph_log "INFO" "before-session" "Max steps: unlimited"
  else
    ralph_log "INFO" "before-session" "Max steps: ${RALPH_STEPS}"
  fi
}

## Resolves the human-gate hook path (project-local preferred, then global).
find_human_gate_hook() {
  if [[ -x "${HOOKS_DIR}/human-gate.sh" ]]; then
    printf '%s' "${HOOKS_DIR}/human-gate.sh"
  elif [[ -x "${HOME}/.ralph/hooks/human-gate.sh" ]]; then
    printf '%s' "${HOME}/.ralph/hooks/human-gate.sh"
  fi
}

## Resolves the planning hook path (project-local preferred, then global).
find_planning_hook() {
  if [[ -x "${HOOKS_DIR}/planning.sh" ]]; then
    printf '%s' "${HOOKS_DIR}/planning.sh"
  elif [[ -n "${RALPH_PROJECT_DIR:-}" ]] && [[ -x "${RALPH_PROJECT_DIR}/hooks/planning.sh" ]]; then
    printf '%s' "${RALPH_PROJECT_DIR}/hooks/planning.sh"
  elif [[ -x "${HOME}/.ralph/hooks/planning.sh" ]]; then
    printf '%s' "${HOME}/.ralph/hooks/planning.sh"
  fi
}

## Resolves the optional issues hook path (project-local preferred, then global).
find_issues_hook() {
  if [[ -x "${HOOKS_DIR}/issues.sh" ]]; then
    printf '%s' "${HOOKS_DIR}/issues.sh"
  elif [[ -x "${HOME}/.ralph/hooks/issues.sh" ]]; then
    printf '%s' "${HOME}/.ralph/hooks/issues.sh"
  fi
}

## Returns success when workspace is already a Git repository.
is_git_repo() {
  git -C "${RALPH_WORKSPACE}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

## Initializes a Git repository in the workspace and logs outcome.
init_git_repo() {
  if git -C "${RALPH_WORKSPACE}" init >/dev/null 2>&1; then
    ralph_log "INFO" "before-session" "Initialized git repository"
    return 0
  fi

  ralph_log "ERROR" "before-session" "Failed to initialize git repository"
  return 1
}

## Ensures version control exists, optionally prompting user for git init.
bootstrap_git_if_needed() {
  if is_git_repo; then
    return 0
  fi

  ralph_log "WARN" "before-session" "No git repository detected in workspace"

  if [[ "${RALPH_HUMAN_GUARD_ASSUME_YES:-0}" == "1" ]]; then
    if init_git_repo; then
      ralph_event "git_bootstrap" "ok" "initialized via assume-yes"
    else
      ralph_event "git_bootstrap" "failed" "git init failed (assume-yes)"
    fi
    return 0
  fi

  if [[ ! -t 0 ]]; then
    ralph_log "INFO" "before-session" "Non-interactive shell; skipping git bootstrap prompt"
    ralph_event "git_bootstrap" "skipped" "non-interactive shell"
    return 0
  fi

  read -r -p "No git repo found in ${RALPH_WORKSPACE}. Initialize now? [y/N]: " git_answer
  case "${git_answer}" in
    y|Y|yes|YES)
      if init_git_repo; then
        ralph_event "git_bootstrap" "ok" "initialized via human prompt"
      else
        ralph_event "git_bootstrap" "failed" "git init failed after prompt"
      fi
      ;;
    *)
      ralph_log "INFO" "before-session" "Git bootstrap skipped by user"
      ralph_event "git_bootstrap" "skipped" "user declined"
      ;;
  esac
}

## Runs optional issue adapter hook (jira/git/none) to enrich session context.
run_issues_hook() {
  local issues_hook
  issues_hook="$(find_issues_hook)"
  [[ -z "${issues_hook}" ]] && return 0

  ralph_log "INFO" "before-session" "Running issues hook"
  if ! RALPH_HOOK_DEPTH="$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))" "${issues_hook}"; then
    ralph_log "WARN" "before-session" "Issues hook failed; continuing without issue context"
    ralph_event "issues" "failed" "issues hook returned non-zero"
    return 0
  fi
  ralph_event "issues" "ok" "issues hook completed"
  return 0
}

## Applies source-control policy for this session (branch-per-session etc.).
run_source_control_policy() {
  local enabled backend configured_backend branch_per_session require_ticket template
  local created_branch

  if ! command -v sc_is_true >/dev/null 2>&1 || ! command -v sc_effective_backend >/dev/null 2>&1; then
    ralph_log "INFO" "before-session" "Source-control helpers unavailable; skipping policy"
    return 0
  fi

  enabled="${RALPH_SOURCE_CONTROL_ENABLED:-1}"
  configured_backend="${RALPH_SOURCE_CONTROL_BACKEND:-auto}"
  branch_per_session="${RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION:-0}"
  require_ticket="${RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH:-0}"
  template="${RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE:-ralph/{ticket}/{goal_slug}/{session_id}}"

  if ! sc_is_true "${enabled}"; then
    ralph_log "INFO" "before-session" "Source-control policy disabled"
    return 0
  fi

  backend="$(sc_effective_backend "${RALPH_WORKSPACE}" "${configured_backend}")"
  if [[ "${backend}" != "git" ]]; then
    ralph_log "INFO" "before-session" "Source-control backend=${backend}; skipping git branch policy"
    return 0
  fi

  if ! sc_is_true "${branch_per_session}"; then
    return 0
  fi

  if [[ "${RALPH_DRY_RUN:-0}" == "1" ]]; then
    ralph_log "INFO" "before-session" "DRY-RUN: would apply branch-per-session policy"
    return 0
  fi

  created_branch="$(sc_apply_branch_policy \
    "${RALPH_WORKSPACE}" \
    "${RALPH_SESSION_ID:-session}" \
    "${RALPH_GOAL:-}" \
    "${RALPH_TICKET:-}" \
    "${require_ticket}" \
    "${template}" || true)"

  if [[ "${created_branch}" == "missing-ticket" ]]; then
    ralph_log "WARN" "before-session" "Branch policy requires ticket but none provided (--ticket)"
    ralph_event "source_control" "blocked" "missing ticket for branch policy"
    return 1
  fi

  if [[ -n "${created_branch}" ]]; then
    ralph_log "INFO" "before-session" "Using session branch: ${created_branch}"
    ralph_event "source_control" "ok" "session branch=${created_branch}"
  fi
  return 0
}

## Creates a pre-session checkpoint in the current session directory.
create_pre_session_checkpoint() {
  if [[ "${RALPH_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi

  if [[ "${RALPH_CHECKPOINT_ENABLED:-1}" != "1" ]]; then
    return 0
  fi

  if ! command -v checkpoint_create >/dev/null 2>&1; then
    ralph_log "INFO" "before-session" "Checkpoint helpers unavailable; skipping"
    return 0
  fi

  local cp_path
  cp_path="$(checkpoint_create \
    "${RALPH_WORKSPACE}" \
    "${RALPH_SESSION_DIR}" \
    "pre" \
    "" \
    "${RALPH_PLAN_FILE:-}" \
    "${RALPH_TICKET:-}" || true)"
  if [[ -n "${cp_path}" ]]; then
    ralph_log "INFO" "before-session" "Checkpoint created: ${cp_path}"
    ralph_event "checkpoint" "ok" "pre-session checkpoint created"
  fi
}

## Runs session-level human approval gate when enabled for current scope.
run_human_gate() {
  local human_gate_hook scope
  human_gate_hook="$(find_human_gate_hook)"
  [[ -z "${human_gate_hook}" ]] && return 0

  scope="${RALPH_HUMAN_GUARD_SCOPE:-both}"
  if [[ "${scope}" != "both" && "${scope}" != "session" ]]; then
    ralph_log "INFO" "before-session" "Human guard skipped at session stage (scope=${scope})"
    return 0
  fi
  if [[ "${PLAN_SESSION_APPROVED}" -eq 1 ]]; then
    ralph_log "INFO" "before-session" "Session guard auto-approved from plan approval"
    ralph_event "session_guard" "approved" "approved via plan gate"
    return 0
  fi

  export RALPH_HUMAN_GUARD_STAGE="session"
  if ! RALPH_HOOK_DEPTH="$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))" "${human_gate_hook}"; then
    ralph_log "WARN" "before-session" "Session rejected by human gate"
    ralph_event "session_guard" "rejected" "human gate rejected session start"
    return 1
  fi

  ralph_event "session_guard" "approved" "session start approved"
  return 0
}

## Executes planning hook if available; fails session on planning failure.
run_planning_hook() {
  local planning_hook
  planning_hook="$(find_planning_hook)"
  [[ -z "${planning_hook}" ]] && return 0

  ralph_log "INFO" "before-session" "Running planning hook"
  if ! RALPH_HOOK_DEPTH="$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))" "${planning_hook}"; then
    ralph_log "ERROR" "before-session" "Planning failed"
    ralph_event "planning" "failed" "planning hook returned non-zero"
    return 1
  fi

  ralph_event "planning" "ok" "planning hook completed"
  return 0
}

## Regenerates plan with explicit human feedback about missing details.
regenerate_plan_with_feedback() {
  local feedback planning_hook
  planning_hook="$(find_planning_hook)"
  [[ -z "${planning_hook}" ]] && return 1

  read -r -p "Describe what is missing in the plan: " feedback
  if [[ -z "${feedback}" ]]; then
    ralph_log "INFO" "before-session" "No feedback provided; keeping current plan"
    return 0
  fi

  ralph_log "INFO" "before-session" "Regenerating plan from feedback"
  if ! RALPH_PLAN_FORCE_REGENERATE=1 RALPH_PLAN_FEEDBACK="${feedback}" RALPH_HOOK_DEPTH="$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))" "${planning_hook}"; then
    ralph_log "ERROR" "before-session" "Plan regeneration failed"
    ralph_event "plan_guard" "failed" "regeneration failed after feedback"
    return 1
  fi

  ralph_event "plan_guard" "replanned" "human feedback submitted"
  return 0
}

## Resolves approval identity: git user.name -> git user.email -> OS user.
resolve_approver_identity() {
  local identity=""
  if command -v git >/dev/null 2>&1; then
    identity="$(git -C "${RALPH_WORKSPACE}" config --get user.name 2>/dev/null || true)"
    [[ -z "${identity}" ]] && identity="$(git -C "${RALPH_WORKSPACE}" config --get user.email 2>/dev/null || true)"
  fi
  [[ -z "${identity}" ]] && identity="${USER:-$(id -un 2>/dev/null || echo unknown)}"
  printf '%s\n' "${identity}"
}

## Writes plan approval metadata to plan.json.
write_plan_approval_metadata() {
  local source="$1"
  local plan_file approver approved_at tmp
  plan_file="${RALPH_PLAN_FILE:-${RALPH_WORKSPACE}/.ralph/plans/plan.json}"
  [[ -f "${plan_file}" ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    ralph_log "WARN" "before-session" "jq not found; skipping plan approval metadata write"
    return 0
  fi

  approver="$(resolve_approver_identity)"
  approved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="${plan_file}.tmp"

  jq --arg by "${approver}" --arg at "${approved_at}" --arg source "${source}" '
    .approved_by = $by
    | .approved_at = $at
    | .approval_source = $source
    | .updated_at = $at
  ' "${plan_file}" > "${tmp}" && mv "${tmp}" "${plan_file}"
}

## Logs summarized plan status (total/pending steps) when plan exists.
log_plan_status() {
  local plan_file step_count pending_count
  plan_file="${RALPH_PLAN_FILE:-${RALPH_WORKSPACE}/.ralph/plans/plan.json}"
  [[ -f "${plan_file}" ]] || return 0

  step_count=$(jq '.steps | length' "${plan_file}" 2>/dev/null || echo "?")
  pending_count=$(jq '[.steps[] | select(.status == "pending")] | length' "${plan_file}" 2>/dev/null || echo "?")
  ralph_log "INFO" "before-session" "Plan: ${step_count} steps (${pending_count} pending)"
}

## Renders plan review inside a simple ASCII box for readability.
render_plan_preview_box() {
  local plan_file="$1"
  local box_width=76
  local border="+------------------------------------------------------------------------------+"
  local total_steps="?"
  local completed_steps="?"
  local pending_steps="?"
  local step_limit="${RALPH_STEPS:-0}"
  local pending_seen=0

  if command -v jq >/dev/null 2>&1; then
    total_steps="$(jq '[.steps[]] | length' "${plan_file}" 2>/dev/null || echo "?")"
    completed_steps="$(jq '[.steps[] | select(.status == "completed")] | length' "${plan_file}" 2>/dev/null || echo "?")"
    pending_steps="$(jq '[.steps[] | select(.status == "pending")] | length' "${plan_file}" 2>/dev/null || echo "?")"
  fi

  if command -v ui_box_border >/dev/null 2>&1; then
    ui_box_border "${box_width}"
    ui_box_line " PLAN REVIEW" "${box_width}"
    ui_box_line " Status: ${completed_steps} completed / ${pending_steps} pending / ${total_steps} total" "${box_width}"
  else
    echo "${border}"
    printf '| %-76s |\n' " PLAN REVIEW"
    printf '| %-76s |\n' " Status: ${completed_steps} completed / ${pending_steps} pending / ${total_steps} total"
  fi
  if [[ "${step_limit}" =~ ^[0-9]+$ ]] && [[ "${step_limit}" -gt 0 ]]; then
    if command -v ui_box_line >/dev/null 2>&1; then
      ui_box_line " Session step limit: ${step_limit} (non-run pending steps are dimmed)" "${box_width}"
    else
      printf '| %-76s |\n' " Session step limit: ${step_limit} (non-run pending steps are dimmed)"
    fi
  fi
  if command -v ui_box_border >/dev/null 2>&1; then
    ui_box_border "${box_width}"
  else
    echo "${border}"
  fi

  if command -v jq >/dev/null 2>&1; then
    local step_index=0
    while IFS=$'\t' read -r status id description; do
      ((step_index++)) || true
      local step_no
      step_no="$(printf '%02d' "${step_index}")"
      local dim_line=0
      if [[ "${step_limit}" =~ ^[0-9]+$ ]] && [[ "${step_limit}" -gt 0 ]] && [[ "${status}" == "pending" ]]; then
        ((pending_seen++)) || true
        if [[ "${pending_seen}" -gt "${step_limit}" ]]; then
          dim_line=1
        fi
      fi
      local tag tag_color
      tag="[${status}]"
      tag_color=""
      case "${status}" in
        completed|done)
          tag="[done]"
          tag_color="${C_GREEN}"
          ;;
        pending)
          tag="[pending]"
          tag_color="${C_YELLOW}"
          ;;
        in_progress)
          tag="[in_progress]"
          tag_color="${C_CYAN}"
          ;;
        *)
          tag_color="${C_RED}"
          ;;
      esac
      local text_prefix="" text_suffix=""
      if [[ "${dim_line}" -eq 1 ]]; then
        text_prefix="${C_DIM}"
        text_suffix="${C_RESET}"
      fi
      if [[ -n "${tag_color}" ]]; then
        echo "| ${text_prefix}${step_no}.${text_suffix} ${text_prefix}${tag_color}${tag}${C_RESET}${text_suffix} ${text_prefix}${id}: ${description}${text_suffix}"
      else
        echo "| ${text_prefix}${step_no}.${text_suffix} ${text_prefix}${tag} ${id}: ${description}${text_suffix}"
      fi
    done < <(jq -r '.steps[] | [.status, .id, .description] | @tsv' "${plan_file}" 2>/dev/null || true)
  else
    while IFS= read -r line; do
      echo "| ${line}"
    done < "${plan_file}"
  fi

  if command -v ui_box_border >/dev/null 2>&1; then
    ui_box_border "${box_width}"
  else
    echo "${border}"
  fi
}

## Interactive action selector with arrow keys (fallback: 1/2/3).
prompt_plan_action_arrow() {
  if command -v ui_prompt_menu_arrow >/dev/null 2>&1; then
    ui_prompt_menu_arrow "Select action (use ↑/↓ + Enter, or 1/2/3):" \
      "Approve and continue" \
      "Reject and stop" \
      "Provide feedback and regenerate plan"
    return 0
  fi

  local -a options=(
    "Approve and continue"
    "Reject and stop"
    "Provide feedback and regenerate plan"
  )
  local selected=0
  local key key2 key3
  local option_count="${#options[@]}"
  local use_alt_screen=0

  if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    if tput smcup >/dev/null 2>&1; then
      use_alt_screen=1
      tput smcup >&2
    fi
  fi

  while true; do
    if [[ "${use_alt_screen}" -eq 1 ]]; then
      printf '\033[H\033[J' >&2
    fi

    echo "Select action (use ↑/↓ + Enter, or 1/2/3):" >&2
    local i
    for ((i=0; i<option_count; i++)); do
      if [[ "${i}" -eq "${selected}" ]]; then
        echo "  > $((i + 1))) ${options[i]}" >&2
      else
        echo "    $((i + 1))) ${options[i]}" >&2
      fi
    done

    IFS= read -rsn1 key
    case "${key}" in
      "")
        # Some terminals return empty on Enter.
        [[ "${use_alt_screen}" -eq 1 ]] && tput rmcup >&2
        echo $((selected + 1))
        return 0
        ;;
      $'\n'|$'\r')
        [[ "${use_alt_screen}" -eq 1 ]] && tput rmcup >&2
        echo $((selected + 1))
        return 0
        ;;
      1|2|3)
        [[ "${use_alt_screen}" -eq 1 ]] && tput rmcup >&2
        echo "${key}"
        return 0
        ;;
      $'\x1b')
        IFS= read -rsn1 -t 0.02 key2 || true
        if [[ "${key2}" == "[" ]]; then
          IFS= read -rsn1 -t 0.02 key3 || true
          case "${key3}" in
            A) # Up
              selected=$(( (selected - 1 + option_count) % option_count ))
              ;;
            B) # Down
              selected=$(( (selected + 1) % option_count ))
              ;;
          esac
        fi
        ;;
    esac
  done
}

## Prints plan steps in terminal and asks for explicit human approval.
run_plan_approval_gate() {
  local plan_file scope answer pending_steps
  plan_file="${RALPH_PLAN_FILE:-${RALPH_WORKSPACE}/.ralph/plans/plan.json}"
  scope="${RALPH_HUMAN_GUARD_SCOPE:-both}"

  [[ -f "${plan_file}" ]] || return 0
  [[ "${RALPH_HUMAN_GUARD:-0}" == "1" ]] || return 0
  [[ "${scope}" == "both" || "${scope}" == "session" ]] || return 0

  pending_steps="$(jq '[.steps[] | select(.status == "pending")] | length' "${plan_file}" 2>/dev/null || echo "")"
  if [[ "${pending_steps}" == "0" ]]; then
    ralph_log "INFO" "before-session" "Plan has no pending steps; skipping plan approval"
    PLAN_SESSION_APPROVED=1
    ralph_event "plan_guard" "skipped" "plan already completed"
    return 0
  fi

  if [[ "${RALPH_HUMAN_GUARD_ASSUME_YES:-0}" == "1" ]]; then
    ralph_log "INFO" "before-session" "Plan auto-approved (assume-yes)"
    PLAN_SESSION_APPROVED=1
    write_plan_approval_metadata "assume-yes"
    ralph_event "plan_guard" "approved" "assume-yes"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    ralph_log "WARN" "before-session" "Plan approval requires TTY; rejecting in non-interactive mode"
    ralph_event "plan_guard" "rejected" "non-interactive shell"
    return 1
  fi

  while true; do
    ralph_log "INFO" "before-session" "Plan review:"
    render_plan_preview_box "${plan_file}"
    answer="$(prompt_plan_action_arrow)"

    case "${answer}" in
      1)
        PLAN_SESSION_APPROVED=1
        write_plan_approval_metadata "interactive"
        ralph_event "plan_guard" "approved" "human approved plan"
        if [[ -t 1 ]]; then
          # Clear terminal after approval to reduce noise before step execution.
          printf '\033[2J\033[H'
        fi
        return 0
        ;;
      2)
        ralph_log "WARN" "before-session" "Plan rejected by user"
        ralph_event "plan_guard" "rejected" "user declined"
        return 1
        ;;
      3)
        if ! regenerate_plan_with_feedback; then
          return 1
        fi
        ;;
      *)
        ralph_log "INFO" "before-session" "Invalid choice. Please select 1, 2, or 3."
        ;;
    esac
  done
}

## Orchestrates before-session workflow in deterministic order.
main() {
  setup_logging
  setup_ui
  setup_source_control
  setup_checkpoint
  setup_colors
  log_session_start
  bootstrap_git_if_needed
  run_issues_hook

  if ! run_source_control_policy; then
    exit 1
  fi

  create_pre_session_checkpoint

  if ! run_planning_hook; then
    exit 1
  fi

  if ! run_plan_approval_gate; then
    exit 1
  fi

  if ! run_human_gate; then
    exit 1
  fi

  log_plan_status
  ralph_log "INFO" "before-session" "Ready"
  ralph_event "before_session" "ok" "session initialization completed"
}

main "$@"
exit 0
