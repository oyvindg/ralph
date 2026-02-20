#!/usr/bin/env bash
# Ensures --reset-plan backups are stored under .ralph/plans/.backups.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

WS="${TMP_BASE}/workspace"
PLAN_DIR="${WS}/.ralph/plans"
PLAN_FILE="${PLAN_DIR}/demo.plan.json"
mkdir -p "${PLAN_DIR}"

cat > "${PLAN_FILE}" <<'EOF'
{
  "goal": "demo",
  "steps": [
    { "id": "s1", "description": "x", "acceptance": "y", "status": "completed" }
  ]
}
EOF

export ROOT="${WS}"
export PLAN_FILE_PATH="${PLAN_FILE}"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/plan.sh"

backup_path="$(reset_plan_steps_to_pending)"
assert_file_exists "${backup_path}" "backup should be created"

case "${backup_path}" in
  "${PLAN_DIR}/.backups/"*) ;;
  *)
    fail "backup should be in ${PLAN_DIR}/.backups, got: ${backup_path}"
    ;;
esac

legacy_count="$(find "${PLAN_DIR}" -maxdepth 1 -type f -name '*.bak.*' | wc -l | tr -d ' ')"
assert_eq "0" "${legacy_count}" "backup files should not be written in plan dir root"
