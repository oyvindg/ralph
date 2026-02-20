#!/usr/bin/env bash
# Ensures agent prompt explicitly lists files that must not be modified.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

RALPH="${ROOT_DIR}/ralph.sh"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

TMP_HOME="${TMP_BASE}/home"
TMP_WS="${TMP_BASE}/workspace"
TMP_GUIDE="${TMP_WS}/AGENTS.md"
mkdir -p "${TMP_HOME}" "${TMP_WS}"

cat > "${TMP_GUIDE}" <<'EOF'
# Guide
Do not modify this file.
EOF

if ! env HOME="${TMP_HOME}" \
  "${RALPH}" \
  --workspace "${TMP_WS}" \
  --goal "prompt immutable files smoke test" \
  --steps 1 \
  --dry-run \
  --human-guard 0 \
  --guide "${TMP_GUIDE}" >/dev/null 2>&1; then
  fail "default ralph run failed while generating prompt"
fi

prompt_file="$(find "${TMP_WS}/.ralph/sessions" -type f -name 'prompt_1.txt' | sort | tail -n 1)"
assert_file_exists "${prompt_file}" "prompt_1.txt should exist"

prompt_content="$(cat "${prompt_file}")"
assert_contains "${prompt_content}" "Files that MUST NOT be modified in this step:" "prompt should declare immutable files section"
assert_contains "${prompt_content}" "- .ralph/** (all files under .ralph are read-only)" "prompt should lock .ralph files"
assert_contains "${prompt_content}" "- AGENTS.md (read-only guide input)" "prompt should list guide file as immutable"
assert_contains "${prompt_content}" "2. Only modify files outside .ralph/." "prompt should enforce outside-.ralph edits only"

if ! env HOME="${TMP_HOME}" \
  "${RALPH}" \
  --workspace "${TMP_WS}" \
  --goal "prompt immutable files smoke test allow ralph edits" \
  --steps 1 \
  --dry-run \
  --human-guard 0 \
  --allow-ralph-edits 1 \
  --guide "${TMP_GUIDE}" >/dev/null 2>&1; then
  fail "allow-ralph-edits run failed while generating prompt"
fi

prompt_file="$(find "${TMP_WS}/.ralph/sessions" -type f -name 'prompt_1.txt' | sort | tail -n 1)"
assert_file_exists "${prompt_file}" "prompt_1.txt should exist for allow-ralph-edits run"

prompt_content="$(cat "${prompt_file}")"
assert_contains "${prompt_content}" "- (none; .ralph edits explicitly allowed for this run)" "prompt should allow .ralph edits when enabled"
assert_contains "${prompt_content}" "2. .ralph/ edits are allowed for this run." "constraints should reflect allow-ralph-edits mode"
