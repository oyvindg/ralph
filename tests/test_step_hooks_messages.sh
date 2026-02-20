#!/usr/bin/env bash
# Validates actionable failure message when quality-gate returns hard failure.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/step-hooks.sh"

# Color vars are optional in runtime; define empty defaults for this unit test context.
C_RED=""
C_RESET=""
C_YELLOW=""

run_hook() {
  # First call (quality-gate) fails with hard fail. on-error call can be no-op.
  if [[ "${1:-}" == "quality-gate" ]]; then
    return 1
  fi
  return 0
}

set +e
output="$(evaluate_quality_gate_action "1" "0" "0" "3" 2>&1)"
rc=$?
set -e

assert_eq "1" "${rc}" "quality-gate hard fail should return 1"
assert_contains "${output}" "quality-gate failed" "failure output should include quality-gate failed"
assert_contains "${output}" "Check [quality-gate]/[human-gate] lines above" "failure output should include actionable hint"
