#!/usr/bin/env bash
# Optional issues hook.
#
# Responsibilities:
# - Resolve ticket/work-item id from configured provider
# - Persist issue context in session artifacts for traceability
#
# This hook is intentionally non-blocking by default.
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/log.sh"
else
  ralph_log() { echo "[$2] $3"; }
  ralph_event() { :; }
fi
if [[ -f "${HOOKS_DIR}/../lib/issues.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/issues.sh"
fi

WORKSPACE="${RALPH_WORKSPACE:-.}"
SESSION_DIR="${RALPH_SESSION_DIR:-}"
PROVIDERS="${RALPH_ISSUES_PROVIDERS:-none}"
EXPLICIT_TICKET="${RALPH_TICKET:-}"

main() {
  command -v issues_resolve_ticket_multi >/dev/null 2>&1 || exit 0

  local ticket context context_file
  ticket="$(issues_resolve_ticket_multi "${PROVIDERS}" "${EXPLICIT_TICKET}" "${WORKSPACE}" || true)"
  context="$(issues_fetch_context_multi "${PROVIDERS}" "${ticket}" || true)"

  if [[ -n "${SESSION_DIR}" ]]; then
    context_file="${SESSION_DIR}/issue_context.md"
    {
      echo "# Issue Context"
      echo ""
      echo "- providers: ${PROVIDERS}"
      echo "- ticket: ${ticket:-none}"
      if [[ -n "${context}" ]]; then
        echo ""
        echo "## Details"
        echo ""
        printf '%s\n' "${context}"
      fi
    } > "${context_file}"
    ralph_log "INFO" "issues" "Wrote issue context: ${context_file}"
  fi

  if [[ -n "${ticket}" ]]; then
    ralph_event "issues" "ok" "providers=${PROVIDERS} ticket=${ticket}"
  else
    ralph_event "issues" "ok" "providers=${PROVIDERS} ticket=none"
  fi
}

main "$@"
