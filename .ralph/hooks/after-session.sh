#!/usr/bin/env bash
# After session hook - runs once at session end
#
# Use for: reports, notifications, cleanup

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${HOOKS_DIR}/../lib/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/log.sh"
else
  ralph_log() { echo "[$2] $3"; }
  ralph_event() { :; }
fi

ralph_log "INFO" "after-session" "Session ${RALPH_SESSION_ID} completed"
ralph_log "INFO" "after-session" "Summary: ${RALPH_SESSION_DIR}/summary.md"
ralph_event "session" "completed" "summary=${RALPH_SESSION_DIR}/summary.md"

# Example: Send summary notification
# curl -s -X POST "https://hooks.slack.com/..." \
#   -d "{\"text\":\"Ralph session completed: ${RALPH_SESSION_ID}\"}" || true

# Example: Archive session
# tar -czf "${RALPH_SESSION_DIR}.tar.gz" "${RALPH_SESSION_DIR}"

exit 0
