#!/usr/bin/env bash
# Generic version-control helpers for Ralph hooks.
# Delegates to task:vcs.* and task:git.* from tasks.jsonc.
set -euo pipefail

SC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SC_LIB_DIR}/git.sh"

# Load parser for run_task/task_condition helpers
if [[ -f "${SC_LIB_DIR}/core/parser.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SC_LIB_DIR}/core/parser.sh"
fi

# Returns 0 when input value represents true (1/true/yes).
sc_is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Converts goal text to a branch-safe slug.
sc_goal_slug() {
  local input="${1:-goal}"
  RALPH_GOAL="${input}" run_task "branch.goal-slug"
}

# Converts a free-form segment into a safe branch segment.
sc_branch_segment() {
  local input="${1:-}"
  BRANCH_SEGMENT="${input}" run_task "branch.segment"
}

# Renders a branch name from template tokens.
sc_render_branch_name() {
  local template="${1:-ralph/{ticket}/{goal_slug}/{session_id}}"
  local ticket="${2:-none}"
  local goal="${3:-goal}"
  local session_id="${4:-session}"

  BRANCH_TEMPLATE="${template}" \
  RALPH_TICKET="${ticket}" \
  RALPH_GOAL="${goal}" \
  RALPH_SESSION_ID="${session_id}" \
  run_task "branch.render-name"
}

# Ensures branch name is unique by appending -N suffix when needed.
sc_unique_branch_name() {
  local workspace="${1:-.}"
  local desired="${2:-ralph/session}"

  RALPH_WORKSPACE="${workspace}" \
  BRANCH_NAME="${desired}" \
  run_task "branch.find-unique"
}

# Resolves effective backend policy.
sc_effective_backend() {
  local workspace="${1:-.}"
  local configured="${2:-auto}"

  export RALPH_WORKSPACE="${workspace}"

  case "${configured}" in
    git)
      if task_condition "git.is-repo"; then
        echo "git"
      else
        echo "filesystem-snapshot"
      fi
      ;;
    filesystem)
      echo "filesystem-snapshot"
      ;;
    auto|*)
      run_task "vcs.backend"
      ;;
  esac
}

# Applies per-session branch policy for git backend.
# Prints chosen branch name on stdout when branch work is performed.
sc_apply_branch_policy() {
  local workspace="${1:-.}"
  local session_id="${2:-session}"
  local goal="${3:-goal}"
  local ticket="${4:-}"
  local require_ticket="${5:-0}"
  local template="${6:-ralph/{ticket}/{goal_slug}/{session_id}}"

  if sc_is_true "${require_ticket}" && [[ -z "${ticket}" ]]; then
    echo "missing-ticket"
    return 2
  fi

  export RALPH_WORKSPACE="${workspace}"
  export RALPH_SESSION_ID="${session_id}"
  export RALPH_GOAL="${goal}"
  export RALPH_TICKET="${ticket}"

  local current_branch desired_branch final_branch
  current_branch="$(run_task "branch.current")"
  desired_branch="$(BRANCH_TEMPLATE="${template}" run_task "branch.render-name")"

  if [[ "${current_branch}" == "${desired_branch}" ]]; then
    printf '%s\n' "${current_branch}"
    return 0
  fi

  final_branch="$(BRANCH_NAME="${desired_branch}" run_task "branch.find-unique")"

  # Try create new branch
  if BRANCH_NAME="${final_branch}" run_task "branch.checkout-new" 2>/dev/null; then
    printf '%s\n' "${final_branch}"
    return 0
  fi

  # Try checkout existing branch
  if BRANCH_NAME="${desired_branch}" run_task "branch.checkout-existing" 2>/dev/null; then
    printf '%s\n' "${desired_branch}"
    return 0
  fi

  return 1
}

# Creates one commit for current step when enabled and when changes exist.
sc_commit_step_if_enabled() {
  local workspace="${1:-.}"
  local enabled="${2:-0}"
  local step="${3:-?}"
  local goal="${4:-}"
  local ticket="${5:-}"

  sc_is_true "${enabled}" || return 0

  export RALPH_WORKSPACE="${workspace}"
  export RALPH_STEP="${step}"
  export RALPH_TICKET="${ticket}"

  # Uses task:vcs.commit-step which checks git.is-repo and git.has-changes
  run_task "vcs.commit-step" || true
}

vcs_backend() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "vcs.backend"
}

vcs_ref() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "vcs.ref"
}

vcs_status_title() {
  local backend="${1:-}"
  case "${backend}" in
    git) echo "Git status (short)" ;;
    *) echo "VCS status" ;;
  esac
}

vcs_status_short() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "git.status-short"
}

vcs_diff_title() {
  local backend="${1:-}"
  case "${backend}" in
    git) echo "Git diff (stat)" ;;
    *) echo "VCS diff (stat)" ;;
  esac
}

vcs_diff_stat() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "git.diff-stat"
}
