#!/usr/bin/env bash
# Tests inline task chaining in run expressions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Setup test environment
ROOT="${TMP_DIR}"
SCRIPT_DIR="${ROOT_DIR}"
DRY_RUN=0
C_RESET="" C_DIM="" C_YELLOW="" C_MAGENTA=""

# Create tasks.jsonc with test tasks
mkdir -p "${TMP_DIR}/.ralph"
cat > "${TMP_DIR}/.ralph/tasks.jsonc" <<'JSONC'
{
  "tasks": {
    "utils": {
      "step1": { "run": "echo STEP1" },
      "step2": { "run": "echo STEP2" }
    },
    "conditions": {
      "always-true": { "run": "true" }
    }
  }
}
JSONC

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/json.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/parser.sh"

# Stub functions
state_record_choice() { :; }

# Build merged tasks file
TASKS_FILE="${TMP_DIR}/merged-tasks.json"
build_merged_tasks_json "${TMP_DIR}/.ralph/tasks.jsonc" "${TASKS_FILE}"

# Test 1: Full task reference (existing behavior)
result="$(json_hook_expand_run_placeholders "task:utils.step1" "${TASKS_FILE}")"
assert_contains "${result}" "echo STEP1" "Full task:ref should expand"

# Test 2: Inline chaining with task: prefix
result="$(json_hook_expand_run_placeholders "task:utils.step1 && task:utils.step2" "${TASKS_FILE}")"
assert_contains "${result}" "STEP1" "First task in chain should expand"
assert_contains "${result}" "STEP2" "Second task in chain should expand"
assert_contains "${result}" "&&" "Chain operator should be preserved"

# Test 3: Mixed inline chaining
result="$(json_hook_expand_run_placeholders "task:utils.step1 && echo MIDDLE && task:utils.step2" "${TASKS_FILE}")"
assert_contains "${result}" "STEP1" "First task should expand"
assert_contains "${result}" "MIDDLE" "Shell command should be preserved"
assert_contains "${result}" "STEP2" "Second task should expand"

# Test 4: task: after pipe
result="$(json_hook_expand_run_placeholders "echo START | task:utils.step1" "${TASKS_FILE}")"
assert_contains "${result}" "START" "Pipe source should be preserved"
assert_contains "${result}" "STEP1" "Task after pipe should expand"

# Test 5: task: after semicolon
result="$(json_hook_expand_run_placeholders "echo A; task:utils.step1" "${TASKS_FILE}")"
assert_contains "${result}" "STEP1" "Task after semicolon should expand"

# Test 6: legacy placeholder syntax should not expand
result="$(json_hook_expand_run_placeholders "{tasks.utils.step1}" "${TASKS_FILE}")"
assert_contains "${result}" "{tasks.utils.step1}" "Legacy placeholder must remain untouched"

# Test 7: task: inside command substitution
result="$(json_hook_expand_run_placeholders "echo \"\$(task:utils.step1)-\$(task:utils.step2)\"" "${TASKS_FILE}")"
assert_contains "${result}" "\$( echo STEP1 )-\$( echo STEP2 )" "task in command substitution should expand"

echo "All inline task chaining tests passed"
