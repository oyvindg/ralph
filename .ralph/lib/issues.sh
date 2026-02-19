#!/usr/bin/env bash
# Generic issue adapter dispatcher for Ralph.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${LIB_DIR}/issues-git.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/issues-git.sh"
fi
if [[ -f "${LIB_DIR}/issues-jira.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/issues-jira.sh"
fi

issues_resolve_ticket() {
  local provider="${1:-none}"
  local explicit_ticket="${2:-}"
  local workspace="${3:-.}"

  if [[ -n "${explicit_ticket}" ]]; then
    printf '%s\n' "${explicit_ticket}"
    return 0
  fi

  case "${provider}" in
    git)
      if command -v issues_git_infer_ticket >/dev/null 2>&1; then
        issues_git_infer_ticket "${workspace}"
      fi
      ;;
    jira|none|*)
      # No auto-resolution by default for provider=jira.
      ;;
  esac
}

issues_fetch_context() {
  local provider="${1:-none}"
  local ticket="${2:-}"

  [[ -z "${ticket}" ]] && return 0

  case "${provider}" in
    jira)
      if command -v issues_jira_fetch_context >/dev/null 2>&1; then
        issues_jira_fetch_context "${ticket}"
      fi
      ;;
    git)
      cat <<EOT
Git adapter context:
- ticket: ${ticket}
- source: branch-name inference or --ticket
EOT
      ;;
    *)
      ;;
  esac
}
