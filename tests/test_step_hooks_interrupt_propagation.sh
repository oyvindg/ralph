#!/usr/bin/env bash
# Ensures step-hooks propagate quality-gate interrupt codes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

export C_RED=""
export C_YELLOW=""
export C_RESET=""
export session_dir=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/step-hooks.sh"

run_hook() {
  local hook_name="${1:-}"
  if [[ "${hook_name}" == "quality-gate" ]]; then
    return 130
  fi
  return 0
}

if evaluate_quality_gate_action "1" "0" "0" "3"; then
  rc=0
else
  rc=$?
fi

assert_eq "130" "${rc}" "evaluate_quality_gate_action should propagate interrupt"
