#!/usr/bin/env bash
# Verifies install.sh installs to a clean directory and the installed CLI runs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

HOME_DIR="${TMP_BASE}/home"
mkdir -p "${HOME_DIR}"
TARGET_HOME="${TMP_BASE}/ralph-home"
TARGET_BIN="${TMP_BASE}/bin"

HOME="${HOME_DIR}" "${ROOT_DIR}/install.sh" --target-home "${TARGET_HOME}" --target-bin "${TARGET_BIN}"

assert_file_exists "${TARGET_HOME}/ralph.sh" "ralph.sh was not copied"
assert_file_exists "${TARGET_HOME}/.ralph/lib/setup/install-global.sh" "install-global.sh missing"
assert_file_exists "${TARGET_BIN}/ralph" "CLI symlink missing"
[[ -x "${TARGET_BIN}/ralph" ]] || fail "CLI is not executable"

version_output=$(HOME="${HOME_DIR}" "${TARGET_BIN}/ralph" --version)
assert_contains "${version_output}" "ralph"
