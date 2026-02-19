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

# Resolves ticket by trying providers in order until one returns a non-empty ticket.
issues_resolve_ticket_multi() {
  local providers_csv="${1:-none}"
  local explicit_ticket="${2:-}"
  local workspace="${3:-.}"
  local provider ticket

  if [[ -n "${explicit_ticket}" ]]; then
    printf '%s\n' "${explicit_ticket}"
    return 0
  fi

  for provider in ${providers_csv//,/ }; do
    [[ -z "${provider}" ]] && continue
    ticket="$(issues_resolve_ticket "${provider}" "" "${workspace}" || true)"
    if [[ -n "${ticket}" ]]; then
      printf '%s\n' "${ticket}"
      return 0
    fi
  done
  return 0
}

# Fetches and concatenates context from all configured providers.
issues_fetch_context_multi() {
  local providers_csv="${1:-none}"
  local ticket="${2:-}"
  local provider ctx out=""

  [[ -z "${ticket}" ]] && return 0

  for provider in ${providers_csv//,/ }; do
    [[ -z "${provider}" || "${provider}" == "none" ]] && continue
    ctx="$(issues_fetch_context "${provider}" "${ticket}" || true)"
    [[ -z "${ctx}" ]] && continue
    if [[ -n "${out}" ]]; then
      out+=$'\n\n'
    fi
    out+="Provider: ${provider}"$'\n'"${ctx}"
  done

  printf '%s\n' "${out}"
}
