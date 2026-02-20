#!/usr/bin/env bash
# Regression: task expansion must preserve '&' in commands (e.g. >&2).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/.ralph"
cat > "${TMP_DIR}/.ralph/tasks.jsonc" <<'JSONC'
{
  "tasks": {
    "validate": {
      "workspace-exists": {
        "run": "test -d \"${RALPH_WORKSPACE:-.}\" || { echo \"ERROR\" >&2; exit 1; }"
      }
    }
  }
}
JSONC

ROOT="${TMP_DIR}"
SCRIPT_DIR="${ROOT_DIR}"
DRY_RUN=0
C_RESET="" C_DIM="" C_YELLOW="" C_MAGENTA=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/json.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/parser.sh"

TASKS_FILE="${TMP_DIR}/merged-tasks.json"
build_merged_tasks_json "${TMP_DIR}/.ralph/tasks.jsonc" "${TASKS_FILE}"

expanded="$(json_hook_expand_run_placeholders "task:validate.workspace-exists" "${TASKS_FILE}")"
assert_contains "${expanded}" ">&2" "expanded command should preserve stderr redirect"
assert_contains "${expanded}" "ERROR" "expanded command should include original body"
assert_eq "0" "$(grep -c 'task:validate.workspace-exists' <<< "${expanded}" || true)" "task token must not leak back into expansion"
