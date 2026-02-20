#!/usr/bin/env bash
# Regression: hooks-parser must treat JSON empty-string when as "no condition".
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

export ROOT="${ROOT_DIR}"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/parser.sh"

set +e
json_hook_when_matches "" "" ""
rc_plain_empty=$?
json_hook_when_matches "\"\"" "" ""
rc_json_empty=$?
set -e

assert_success "${rc_plain_empty}" "plain empty when should match"
assert_success "${rc_json_empty}" "JSON empty-string when should match"
