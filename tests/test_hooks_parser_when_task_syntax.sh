#!/usr/bin/env bash
# Regression: when expressions should support inline task: syntax.
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
    "conditions": {
      "ok": { "run": "true" },
      "not-ok": { "run": "false" }
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

if json_hook_when_matches "task:conditions.ok && task:conditions.ok" "${TASKS_FILE}" ""; then
  rc_inline_ok=0
else
  rc_inline_ok=$?
fi

if json_hook_when_matches "task:conditions.ok && task:conditions.not-ok" "${TASKS_FILE}" ""; then
  rc_inline_fail=0
else
  rc_inline_fail=$?
fi

if json_hook_when_matches "{task:conditions.ok} && {task:conditions.ok}" "${TASKS_FILE}" ""; then
  rc_braced_legacy=0
else
  rc_braced_legacy=$?
fi

assert_success "${rc_inline_ok}" "inline task: && task: should pass when all pass"
assert_failure "${rc_inline_fail}" "inline task: expression should fail when one condition fails"
assert_failure "${rc_braced_legacy}" "{task:...} legacy placeholder syntax should not be supported"
