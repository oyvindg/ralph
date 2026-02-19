#!/usr/bin/env bash
# Step hook control helpers for Ralph orchestrator.
set -euo pipefail

# Runs a required step hook and handles fatal hook failures consistently.
# Returns 0 when hook is accepted, 1 when the step must fail.
run_required_step_hook() {
  local hook_name="$1"
  local step="$2"
  local step_exit_code="${3:-}"
  local fail_message="$4"
  local hook_rc

  set +e
  run_hook "${hook_name}" "${step}" "${step_exit_code}"
  hook_rc=$?
  set -e

  if [[ "${hook_rc}" -eq 1 ]]; then
    echo "${C_RED}${fail_message}${C_RESET}" >&2
    run_hook "on-error" "${step}" "${hook_rc}"
    return 1
  fi
  return 0
}

# Evaluates quality-gate result and returns next action:
# - 0: proceed
# - 3: retry current step
# - 1: fail step
evaluate_quality_gate_action() {
  local step="$1"
  local step_exit_code="$2"
  local retry_count="$3"
  local max_retries="$4"
  local hook_rc next_retry

  set +e
  run_hook "quality-gate" "${step}" "${step_exit_code}"
  hook_rc=$?
  set -e

  case "${hook_rc}" in
    0)
      return 0
      ;;
    1)
      echo "${C_RED}quality-gate failed${C_RESET}" >&2
      run_hook "on-error" "${step}" "${hook_rc}"
      return 1
      ;;
    2)
      # Replan flow is not implemented yet, so this is treated as hard failure.
      echo "${C_YELLOW}quality-gate requested replan (not implemented, treating as failure)${C_RESET}" >&2
      run_hook "on-error" "${step}" "${hook_rc}"
      return 1
      ;;
    3)
      next_retry=$((retry_count + 1))
      if [[ "${next_retry}" -ge "${max_retries}" ]]; then
        echo "${C_RED}quality-gate retry limit reached (${max_retries})${C_RESET}" >&2
        run_hook "on-error" "${step}" "${hook_rc}"
        return 1
      fi
      echo "${C_YELLOW}quality-gate requested retry (${next_retry}/${max_retries})${C_RESET}"
      return 3
      ;;
    *)
      echo "${C_RED}quality-gate returned unknown exit code ${hook_rc}${C_RESET}" >&2
      run_hook "on-error" "${step}" "${hook_rc}"
      return 1
      ;;
  esac
}
