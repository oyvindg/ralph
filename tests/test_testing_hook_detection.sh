#!/usr/bin/env bash
# Verifies testing hook detects repo-local tests/run.sh runner.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

output="$({
  RALPH_WORKSPACE="${ROOT_DIR}" \
  RALPH_DRY_RUN=1 \
  RALPH_HOOK_DEPTH=0 \
  "${ROOT_DIR}/.ralph/hooks/testing.sh"
} 2>&1)"

assert_contains "${output}" "[x] tests/run.sh" "expected tests/run.sh runner to be detected"
assert_contains "${output}" "[ ] pytest" "pytest should not be auto-detected for this repo"
