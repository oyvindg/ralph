#!/usr/bin/env bash
# Shared Git helpers for Ralph hooks.
# Delegates to task:git.* from tasks.jsonc via run_task/task_condition.
set -euo pipefail

GIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load parser for run_task/task_condition helpers
if [[ -f "${GIT_LIB_DIR}/core/parser.sh" ]]; then
  # shellcheck disable=SC1091
  source "${GIT_LIB_DIR}/core/parser.sh"
fi

git_is_repo() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" task_condition "git.is-repo"
}

git_has_changes() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" task_condition "git.has-changes"
}

git_branch() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "git.branch"
}

git_head_short() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "git.head-short"
}

git_status_short() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "git.status-short"
}

git_diff_stat() {
  local workspace="${1:-${RALPH_WORKSPACE:-.}}"
  RALPH_WORKSPACE="${workspace}" run_task "git.diff-stat"
}
