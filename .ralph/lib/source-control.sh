#!/usr/bin/env bash
# Generic version-control helpers for Ralph hooks.
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git.sh"

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
  input="$(printf '%s' "${input}" | tr '[:upper:]' '[:lower:]')"
  input="$(printf '%s' "${input}" | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  [[ -z "${input}" ]] && input="goal"
  printf '%s\n' "${input}"
}

# Converts a free-form segment into a safe branch segment.
sc_branch_segment() {
  local input="${1:-}"
  input="$(printf '%s' "${input}" | sed 's/[^A-Za-z0-9._/-]/-/g; s/--*/-/g; s#//*#/#g; s#^/##; s#/$##')"
  [[ -z "${input}" ]] && input="none"
  printf '%s\n' "${input}"
}

# Renders a branch name from template tokens.
# Tokens:
#   {ticket}, {goal_slug}, {session_id}, {date}
sc_render_branch_name() {
  local template="${1:-ralph/{ticket}/{goal_slug}/{session_id}}"
  local ticket="${2:-none}"
  local goal="${3:-goal}"
  local session_id="${4:-session}"
  local now_date
  now_date="$(date +%Y%m%d)"

  local value="${template}"
  value="${value//\{ticket\}/$(sc_branch_segment "${ticket}")}"
  value="${value//\{goal_slug\}/$(sc_goal_slug "${goal}")}"
  value="${value//\{session_id\}/$(sc_branch_segment "${session_id}")}"
  value="${value//\{date\}/${now_date}}"
  value="$(sc_branch_segment "${value}")"
  printf '%s\n' "${value}"
}

# Ensures branch name is unique by appending -N suffix when needed.
sc_unique_branch_name() {
  local workspace="${1:-.}"
  local desired="${2:-ralph/session}"
  local candidate="${desired}"
  local n=2
  while git -C "${workspace}" show-ref --verify --quiet "refs/heads/${candidate}" 2>/dev/null; do
    candidate="${desired}-${n}"
    n=$((n + 1))
  done
  printf '%s\n' "${candidate}"
}

# Resolves effective backend policy.
sc_effective_backend() {
  local workspace="${1:-.}"
  local configured="${2:-auto}"
  case "${configured}" in
    git)
      if git_is_repo "${workspace}"; then
        printf '%s\n' "git"
      else
        printf '%s\n' "filesystem-snapshot"
      fi
      ;;
    filesystem)
      printf '%s\n' "filesystem-snapshot"
      ;;
    auto|*)
      vcs_backend "${workspace}"
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

  local current_branch desired_branch final_branch
  current_branch="$(git_branch "${workspace}")"
  desired_branch="$(sc_render_branch_name "${template}" "${ticket:-none}" "${goal}" "${session_id}")"

  if [[ "${current_branch}" == "${desired_branch}" ]]; then
    printf '%s\n' "${current_branch}"
    return 0
  fi

  final_branch="$(sc_unique_branch_name "${workspace}" "${desired_branch}")"
  if git -C "${workspace}" checkout -b "${final_branch}" >/dev/null 2>&1; then
    printf '%s\n' "${final_branch}"
    return 0
  fi

  if git -C "${workspace}" checkout "${desired_branch}" >/dev/null 2>&1; then
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
  git_is_repo "${workspace}" || return 0

  if git -C "${workspace}" diff --quiet && git -C "${workspace}" diff --cached --quiet; then
    return 0
  fi

  git -C "${workspace}" add -A

  local msg="ralph(step ${step}): automated checkpoint"
  [[ -n "${ticket}" ]] && msg="[${ticket}] ${msg}"
  [[ -n "${goal}" ]] && msg="${msg} - ${goal}"
  git -C "${workspace}" commit -m "${msg}" >/dev/null 2>&1 || true
}

vcs_backend() {
  local workspace="${1:-.}"
  if git_is_repo "${workspace}"; then
    echo "git"
  else
    echo "filesystem-snapshot"
  fi
}

vcs_ref() {
  local workspace="${1:-.}"
  if git_is_repo "${workspace}"; then
    echo "$(git_branch "${workspace}")@$(git_head_short "${workspace}")"
  else
    echo "n/a"
  fi
}

vcs_status_title() {
  local backend="${1:-}"
  case "${backend}" in
    git) echo "Git status (short)" ;;
    *) echo "VCS status" ;;
  esac
}

vcs_status_short() {
  local workspace="${1:-.}"
  local backend
  backend="$(vcs_backend "${workspace}")"
  case "${backend}" in
    git) git_status_short "${workspace}" ;;
    *) echo "(not available for ${backend})" ;;
  esac
}

vcs_diff_title() {
  local backend="${1:-}"
  case "${backend}" in
    git) echo "Git diff (stat)" ;;
    *) echo "VCS diff (stat)" ;;
  esac
}

vcs_diff_stat() {
  local workspace="${1:-.}"
  local backend
  backend="$(vcs_backend "${workspace}")"
  case "${backend}" in
    git) git_diff_stat "${workspace}" ;;
    *) echo "(not available for ${backend})" ;;
  esac
}
