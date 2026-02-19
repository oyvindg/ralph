#!/usr/bin/env bash
# Jira issue provider helpers.
#
# TODO: Implement provider-specific integration.
# Suggested approach:
# - Read JIRA_BASE_URL and JIRA_TOKEN from environment
# - Call Jira REST API to fetch summary/status for RALPH_TICKET
# - Return a short markdown/text context string
set -euo pipefail

issues_jira_fetch_context() {
  local ticket="${1:-}"
  if [[ -z "${ticket}" ]]; then
    return 0
  fi

  # Placeholder output keeps core agnostic while showing where integration belongs.
  cat <<EOT
Jira adapter placeholder:
- ticket: ${ticket}
- status: not-fetched
- note: implement API fetch in .ralph/lib/issues-jira.sh
EOT
}
