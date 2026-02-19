#!/usr/bin/env bash
# Validates shared JSON/JSONC normalization helpers.
# Ensures JSONC comments are stripped and resulting payload remains valid JSON.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/json.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/sample.jsonc" <<'JSONC'
{
  // line comment
  "a": 1,
  /* block comment */
  "b": "ok"
}
JSONC

norm="$(json_like_to_temp_file "${TMP_DIR}/sample.jsonc")"
assert_file_exists "${norm}" "normalized JSON temp file not created"
val_a="$(jq -r '.a' "${norm}")"
val_b="$(jq -r '.b' "${norm}")"
assert_eq "1" "${val_a}" "jsonc normalize a"
assert_eq "ok" "${val_b}" "jsonc normalize b"
rm -f "${norm}"
