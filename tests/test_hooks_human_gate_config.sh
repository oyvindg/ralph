#!/usr/bin/env bash
# Ensures the active project hooks config defines required human-gate select.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/json.sh"

hooks_file="${ROOT_DIR}/.ralph/hooks.jsonc"
assert_file_exists "${hooks_file}" "hooks.jsonc must exist"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required for hooks config test"
fi

norm_hooks="$(json_like_to_temp_file "${hooks_file}")"
trap 'rm -f "${norm_hooks}"' EXIT

if ! jq -e '
  .["human-gate-confirm"]?.system as $node
  | if $node == null then false
    elif ($node|type) == "array" then ($node|length) > 0
    elif ($node|type) == "object" then (($node.commands // [])|length) > 0
    else false end
' "${norm_hooks}" >/dev/null 2>&1; then
  fail "hooks.jsonc must define human-gate-confirm.system"
fi

if ! jq -e '
  .["human-gate-confirm"].system
  | (if type == "array" then . else (.commands // []) end)
  | map(.select.options // [])
  | flatten
  | map(.code)
  | (index("approve") != null and index("reject") != null)
' "${norm_hooks}" >/dev/null 2>&1; then
  fail "human-gate-confirm.system must include approve/reject options"
fi
