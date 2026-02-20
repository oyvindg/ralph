#!/usr/bin/env bash
# Ensures testing hook does not pass active Ralph session vars into repo tests.
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
if [[ -n "${RALPH_SESSION_DIR:-}" ]]; then
  echo "RALPH_SESSION_DIR leaked into test runner" >&2
  exit 42
fi
exit 0
EOF
chmod +x "${WORKSPACE}/tests/run.sh"

set +e
RALPH_WORKSPACE="${WORKSPACE}" \
RALPH_DRY_RUN=0 \
RALPH_SESSION_DIR="${TMP_BASE}/session" \
"${ROOT_DIR}/.ralph/hooks/testing.sh" >/dev/null 2>&1
rc=$?
set -e

assert_success "${rc}" "testing hook should isolate session vars for repo test runner"
