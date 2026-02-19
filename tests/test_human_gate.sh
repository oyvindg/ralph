#!/usr/bin/env bash
# Validates core human-gate behavior without interactive input.
# Covers disabled gate, assume-yes mode, and non-interactive rejection path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

# Disabled gate -> success
set +e
RALPH_HUMAN_GUARD=0 "${ROOT_DIR}/.ralph/hooks/human-gate.sh" >/dev/null 2>&1
rc=$?
set -e
assert_success "${rc}" "disabled human gate should pass"

# Enabled + assume yes -> success
set +e
RALPH_HUMAN_GUARD=1 RALPH_HUMAN_GUARD_ASSUME_YES=1 "${ROOT_DIR}/.ralph/hooks/human-gate.sh" >/dev/null 2>&1
rc=$?
set -e
assert_success "${rc}" "assume-yes human gate should pass"

# Enabled + non-interactive + no assume yes -> reject
set +e
RALPH_HUMAN_GUARD=1 RALPH_HUMAN_GUARD_ASSUME_YES=0 "${ROOT_DIR}/.ralph/hooks/human-gate.sh" >/dev/null 2>&1
rc=$?
set -e
assert_failure "${rc}" "non-interactive human gate should reject"
