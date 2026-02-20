#!/usr/bin/env bash
# Ensures --version uses tasks.jsonc when available.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/tasks.jsonc" <<'JSONC'
{
  "tasks": {
    "version": {
      "print": {
        "run": "echo \"task-version\""
      }
    }
  }
}
JSONC

output="$(
  RALPH_TASKS_JSON="${TMP_DIR}/tasks.jsonc" \
  "${ROOT_DIR}/ralph.sh" --version
)"

assert_eq "task-version" "${output}" "--version should execute version.print task"
