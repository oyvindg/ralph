#!/usr/bin/env bash
# Ensures testing hook propagates Ctrl+C-style interrupt codes.
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
RALPH_WORKSPACE="${WORKSPACE}" \
RALPH_DRY_RUN=0 \
"${ROOT_DIR}/.ralph/hooks/testing.sh" >/dev/null 2>&1
rc=$?
set -e

assert_eq "130" "${rc}" "testing hook should propagate interrupt exit code"
