#!/usr/bin/env bash
# Regression: lang:key syntax should resolve via language files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/.ralph/lang"
cat > "${TMP_DIR}/.ralph/lang/en.json" <<'JSON'
{
  "deploy.confirm": "Deploy now?"
}
JSON

export ROOT="${TMP_DIR}"
export RALPH_LANG="en"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/parser.sh"

resolved="$(json_hook_localize "lang:deploy.confirm" "lang:deploy.confirm")"
assert_eq "Deploy now?" "${resolved}" "lang:key should resolve from language file"

fallback="$(json_hook_localize "lang:missing.key" "lang:missing.key")"
assert_eq "missing.key" "${fallback}" "missing lang:key should fallback to key name"
