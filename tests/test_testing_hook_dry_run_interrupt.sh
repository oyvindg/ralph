#!/usr/bin/env bash
# Ensures testing hook propagates interrupt from tests/run.sh in dry-run mode.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

WORKSPACE="${TMP_BASE}/ws"
mkdir -p "${WORKSPACE}/tests"

cat > "${WORKSPACE}/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 130
EOF
chmod +x "${WORKSPACE}/tests/run.sh"

set +e
output="$({
  RALPH_WORKSPACE="${WORKSPACE}" \
  RALPH_DRY_RUN=1 \
  RALPH_DRY_RUN_EXECUTE_TESTS=1 \
  "${ROOT_DIR}/.ralph/hooks/testing.sh"
} 2>&1)"
rc=$?
set -e

assert_eq "130" "${rc}" "testing hook dry-run should propagate interrupt"
assert_contains "${output}" "DRY-RUN: tests/run.sh interrupted" "output should explain interrupt reason"
