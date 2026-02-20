#!/usr/bin/env bash
# Validates core human-gate behavior without interactive input.
# Covers disabled gate, assume-yes mode, and non-interactive rejection path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

run_gate_isolated() {
  env \
    -u RALPH_SESSION_DIR \
    -u RALPH_SESSION_ID \
    -u RALPH_STEP \
    -u RALPH_STEPS \
    "$@"
}

# Disabled gate -> success
set +e
run_gate_isolated RALPH_HUMAN_GUARD=0 "${ROOT_DIR}/.ralph/hooks/human-gate.sh" >/dev/null 2>&1
rc=$?
set -e
assert_success "${rc}" "disabled human gate should pass"

# Enabled + assume yes -> success
set +e
run_gate_isolated RALPH_HUMAN_GUARD=1 RALPH_HUMAN_GUARD_ASSUME_YES=1 "${ROOT_DIR}/.ralph/hooks/human-gate.sh" >/dev/null 2>&1
rc=$?
set -e
assert_success "${rc}" "assume-yes human gate should pass"

# Enabled + non-interactive + no assume yes -> reject (use --dry-run or assume-yes for CI).
set +e
output="$(run_gate_isolated \
  RALPH_HUMAN_GUARD=1 \
  RALPH_HUMAN_GUARD_ASSUME_YES=0 \
  RALPH_DRY_RUN=0 \
  RALPH_WORKSPACE="${ROOT_DIR}" \
  RALPH_HOOKS_FILE="${ROOT_DIR}/.ralph/hooks.jsonc" \
  "${ROOT_DIR}/.ralph/hooks/human-gate.sh" </dev/null 2>&1)"
rc=$?
set -e
assert_failure "${rc}" "non-interactive human gate should reject without dry-run"

# Missing hooks config should produce explicit missing-config guidance.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
hooks_file="${tmp_dir}/hooks.jsonc"
echo '{}' > "${hooks_file}"

set +e
output="$(run_gate_isolated \
  RALPH_HUMAN_GUARD=1 \
  RALPH_HUMAN_GUARD_ASSUME_YES=0 \
  RALPH_HOOKS_FILE="${hooks_file}" \
  "${ROOT_DIR}/.ralph/hooks/human-gate.sh" 2>&1)"
rc=$?
set -e

assert_failure "${rc}" "missing hooks config should reject"
assert_contains "${output}" "missing hooks select config: human-gate-confirm.system" "missing-config message should be explicit"
assert_contains "${output}" "hooks file:" "missing-config message should include active hooks file"
