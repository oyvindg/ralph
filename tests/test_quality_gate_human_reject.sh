#!/usr/bin/env bash
# Ensures quality-gate fails hard (no retry) when human-gate rejects a step.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

WORKSPACE="${TMP_BASE}/workspace"
SESSION_DIR="${TMP_BASE}/session"
RESPONSE_FILE="${SESSION_DIR}/response.md"
mkdir -p "${WORKSPACE}" "${SESSION_DIR}"

cat > "${RESPONSE_FILE}" <<'EOF'
Mock response content for quality-gate.
EOF

# Non-interactive shell + enabled human guard + no assume-yes => human-gate rejects.
set +e
RALPH_WORKSPACE="${WORKSPACE}" \
RALPH_SESSION_DIR="${SESSION_DIR}" \
RALPH_RESPONSE_FILE="${RESPONSE_FILE}" \
RALPH_STEP=1 \
RALPH_STEPS=1 \
RALPH_DRY_RUN=0 \
RALPH_HUMAN_GUARD=1 \
RALPH_HUMAN_GUARD_ASSUME_YES=0 \
RALPH_HUMAN_GUARD_SCOPE=step \
RALPH_TEMP_TEST_SUITE_ON_NO_TESTS=0 \
"${ROOT_DIR}/.ralph/hooks/quality-gate.sh" >/dev/null 2>&1
rc=$?
set -e

assert_eq "1" "${rc}" "quality-gate should hard-fail when human gate rejects"
