#!/usr/bin/env bash
# Git issue provider helpers.
#
# This adapter is intentionally generic: it only tries to infer a ticket-like id
# from the current branch name. It has no dependency on Jira/GitHub-specific APIs.
set -euo pipefail

issues_git_branch_name() {
  local workspace="${1:-.}"
  git -C "${workspace}" symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

issues_git_infer_ticket() {
  local workspace="${1:-.}"
  local branch
  branch="$(issues_git_branch_name "${workspace}")"
  [[ -z "${branch}" ]] && return 0

  # Generic ticket pattern, e.g. ABC-123
  printf '%s' "${branch}" | grep -Eo '[A-Z][A-Z0-9]+-[0-9]+' | head -n1 || true
}
