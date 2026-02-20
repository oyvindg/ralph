#!/usr/bin/env bash
# Regression: hooks-parser must not fail when DRY_RUN is unset.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

export ROOT="${ROOT_DIR}"
unset DRY_RUN || true

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/parser.sh"

set +e
run_json_hook_command_entry \
  "test-event" \
  ":" \
  "" \
  "0" \
  "" \
  "0" \
  "0" \
  "" \
  "0" \
  "true" \
  "" \
  "" \
  ""
rc=$?
set -e

assert_success "${rc}" "run_json_hook_command_entry should handle unset DRY_RUN"
