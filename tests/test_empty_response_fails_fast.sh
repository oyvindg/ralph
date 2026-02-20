#!/usr/bin/env bash
# Ensures an empty successful AI response hard-fails the step/session.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

RALPH="${ROOT_DIR}/ralph.sh"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

TMP_HOME="${TMP_BASE}/home"
TMP_WS="${TMP_BASE}/workspace"
TMP_BIN="${TMP_BASE}/bin"
PLAN_DIR="${TMP_WS}/.ralph/plans"
mkdir -p "${TMP_HOME}" "${TMP_WS}" "${TMP_BIN}" "${PLAN_DIR}"

# Satisfy codex CLI preflight in non-dry runs.
cat > "${TMP_BIN}/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP_BIN}/codex"

cat > "${PLAN_DIR}/plan.json" <<'EOF'
{
  "goal": "empty response should fail",
  "updated_at": "2026-02-20T00:00:00Z",
  "steps": [
    {
      "id": "step-1",
      "description": "trigger one step run",
      "acceptance": "step completes",
      "status": "pending",
      "updated_at": "2026-02-20T00:00:00Z"
    }
  ]
}
EOF

set +e
output="$(env \
  PATH="${TMP_BIN}:${PATH}" \
  HOME="${TMP_HOME}" \
  RALPH_MOCK_EMPTY=1 \
  "${RALPH}" \
  --workspace "${TMP_WS}" \
  --goal "empty response should fail" \
  --steps 1 \
  --engine mock \
  --human-guard 0 2>&1)"
rc=$?
set -e

assert_failure "${rc}" "session should fail when AI response is empty"
assert_contains "${output}" "ERROR: Empty response from mock" "empty response should be a hard error"
