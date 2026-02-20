#!/usr/bin/env bash
# After session hook - runs once at session end
#
# NOTE: Core functionality moved to tasks.jsonc (session.* tasks)
# This shell hook is kept for backwards compatibility and custom extensions.
#
# To add custom after-session behavior:
# - Option 1: Add tasks to tasks.jsonc and reference from hooks.jsonc
# - Option 2: Uncomment and modify the examples below
#
# See: .ralph/hooks.jsonc -> after-session
# See: .ralph/tasks.jsonc -> session.*

set -euo pipefail

# Example: Send Slack notification
# curl -s -X POST "https://hooks.slack.com/..." \
#   -d "{\"text\":\"Ralph session completed: ${RALPH_SESSION_ID}\"}" || true

# Example: Archive session
# tar -czf "${RALPH_SESSION_DIR}.tar.gz" "${RALPH_SESSION_DIR}"

exit 0
