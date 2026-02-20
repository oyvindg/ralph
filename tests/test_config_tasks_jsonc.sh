#!/usr/bin/env bash
# Validates tasks.jsonc resolution precedence.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_HOME="$(mktemp -d)"
TMP_WS="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}" "${TMP_WS}"' EXIT

mkdir -p "${TMP_WS}/.ralph"

cat > "${TMP_WS}/.ralph/tasks.json" <<'JSON'
{
  "tasks": {}
}
JSON

cat > "${TMP_WS}/.ralph/tasks.jsonc" <<'JSONC'
// jsonc should be preferred when present
{
  "tasks": {}
}
JSONC

HOME="${TMP_HOME}"
ROOT="${TMP_WS}"
SCRIPT_DIR="${ROOT_DIR}"
RALPH_PROJECT_DIR=""
RALPH_GLOBAL_DIR=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/config.sh"

find_ralph_dirs

resolved="$(resolve_tasks_json_path)"
assert_eq "${TMP_WS}/.ralph/tasks.jsonc" "${resolved}" "tasks.jsonc should be preferred"

rm -f "${TMP_WS}/.ralph/tasks.jsonc"
resolved="$(resolve_tasks_json_path)"
assert_eq "${TMP_WS}/.ralph/tasks.json" "${resolved}" "tasks.json should be fallback when jsonc missing"
