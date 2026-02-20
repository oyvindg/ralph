#!/usr/bin/env bash
# Ensures testing hook can print full repo test-suite output in dry-run mode.
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
echo "RUN_SUITE_SENTINEL"
EOF
chmod +x "${WORKSPACE}/tests/run.sh"

output="$({
  RALPH_WORKSPACE="${WORKSPACE}" \
  RALPH_DRY_RUN=1 \
  RALPH_DRY_RUN_EXECUTE_TESTS=1 \
  "${ROOT_DIR}/.ralph/hooks/testing.sh"
} 2>&1)"

assert_contains "${output}" "[testing] DRY-RUN: Running tests/run.sh" "dry-run should execute repo suite when enabled"
assert_contains "${output}" "RUN_SUITE_SENTINEL" "dry-run should print full tests/run.sh output"
