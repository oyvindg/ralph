#!/usr/bin/env bash
# Ensures AI adapter rejects known invalid model/engine combinations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT
PROMPT_FILE="${TMP_BASE}/prompt.txt"
RESPONSE_FILE="${TMP_BASE}/response.txt"
echo "compat check" > "${PROMPT_FILE}"

run_ai_fail() {
  local engine="$1"
  local model="$2"
  set +e
  output="$(
    RALPH_ENGINE="${engine}" \
    RALPH_MODEL="${model}" \
    RALPH_PROMPT_FILE="${PROMPT_FILE}" \
    RALPH_RESPONSE_FILE="${RESPONSE_FILE}" \
    "${ROOT_DIR}/.ralph/hooks/ai.sh" 2>&1
  )"
  rc=$?
  set -e
  assert_failure "${rc}" "ai adapter should reject engine=${engine} model=${model}"
  assert_contains "${output}" "invalid model/engine combination" "error should explain incompatibility"
}

run_ai_fail "codex" "claude"
run_ai_fail "claude" "gpt-5.3-codex"
