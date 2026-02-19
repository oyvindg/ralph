#!/usr/bin/env bash
# Bootstrap helpers used by before-session hook.
set -euo pipefail

# Returns success when a command exists in PATH.
bootstrap_has_command() {
  command -v "${1:-}" >/dev/null 2>&1
}

# Returns success when workspace is already a Git repository.
bootstrap_is_git_repo() {
  git -C "${RALPH_WORKSPACE}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Initializes a Git repository in workspace and logs outcome.
bootstrap_init_git_repo() {
  if git -C "${RALPH_WORKSPACE}" init >/dev/null 2>&1; then
    ralph_log "INFO" "before-session" "Initialized git repository"
    return 0
  fi

  ralph_log "ERROR" "before-session" "Failed to initialize git repository"
  return 1
}

# Prints short install guidance for known CLI dependencies.
bootstrap_print_install_hint() {
  local dep="${1:-}"
  case "${dep}" in
    git)
      echo "Install hint (Ubuntu): sudo apt update && sudo apt install -y git"
      ;;
    jq)
      echo "Install hint (Ubuntu): sudo apt update && sudo apt install -y jq"
      ;;
    *)
      echo "Install hint: install '${dep}' via your package manager."
      ;;
  esac
}

# Prompts human about missing dependency and logs choice.
bootstrap_prompt_missing_dependency() {
  local dep="${1:-}"
  local reason="${2:-required by Ralph hooks}"
  [[ -n "${dep}" ]] || return 0

  ralph_log "WARN" "before-session" "Missing dependency: ${dep} (${reason})"

  if [[ "${RALPH_HUMAN_GUARD_ASSUME_YES:-0}" == "1" ]]; then
    bootstrap_print_install_hint "${dep}"
    command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "${dep}-install-hint" "assume-yes"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "${dep}-install-skipped" "non-interactive"
    return 0
  fi

  local answer
  read -r -p "Dependency '${dep}' is missing. Show install hint? [Y/n]: " answer
  case "${answer}" in
    n|N|no|NO)
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "${dep}-install-hint-no" "interactive"
      ;;
    *)
      bootstrap_print_install_hint "${dep}"
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "${dep}-install-hint-yes" "interactive"
      ;;
  esac
}

# Runs bootstrap dependency checks used by setup wizard flows.
bootstrap_run_prereq_checks() {
  if ! bootstrap_has_command git; then
    bootstrap_prompt_missing_dependency "git" "needed for repository initialization and git-based source control"
    ralph_event "bootstrap" "warn" "git missing"
  fi

  if ! bootstrap_has_command jq; then
    bootstrap_prompt_missing_dependency "jq" "needed for hooks.json/tasks.json/state processing"
    ralph_event "bootstrap" "warn" "jq missing"
  fi
}

# Ensures version control exists, optionally prompting user for git init.
bootstrap_git_if_needed() {
  if ! bootstrap_has_command git; then
    ralph_log "INFO" "before-session" "Skipping git bootstrap (git is not installed)"
    return 0
  fi

  if bootstrap_is_git_repo; then
    return 0
  fi

  ralph_log "WARN" "before-session" "No git repository detected in workspace"

  if [[ "${RALPH_HUMAN_GUARD_ASSUME_YES:-0}" == "1" ]]; then
    if bootstrap_init_git_repo; then
      ralph_event "git_bootstrap" "ok" "initialized via assume-yes"
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "git-init-yes" "assume-yes"
    else
      ralph_event "git_bootstrap" "failed" "git init failed (assume-yes)"
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "git-init-failed" "assume-yes"
    fi
    return 0
  fi

  if [[ ! -t 0 ]]; then
    ralph_log "INFO" "before-session" "Non-interactive shell; skipping git bootstrap prompt"
    ralph_event "git_bootstrap" "skipped" "non-interactive shell"
    command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "git-init-skipped" "non-interactive"
    return 0
  fi

  read -r -p "No git repo found in ${RALPH_WORKSPACE}. Initialize now? [y/N]: " git_answer
  case "${git_answer}" in
    y|Y|yes|YES)
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "git-init-yes" "interactive"
      if bootstrap_init_git_repo; then
        ralph_event "git_bootstrap" "ok" "initialized via human prompt"
      else
        ralph_event "git_bootstrap" "failed" "git init failed after prompt"
      fi
      ;;
    *)
      ralph_log "INFO" "before-session" "Git bootstrap skipped by user"
      ralph_event "git_bootstrap" "skipped" "user declined"
      command -v ralph_state_choice >/dev/null 2>&1 && ralph_state_choice "before-session" "git-init-no" "interactive"
      ;;
  esac
}
