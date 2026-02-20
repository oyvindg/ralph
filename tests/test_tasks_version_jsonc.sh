#!/usr/bin/env bash
# Validates version tasks defined in tasks.jsonc.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_REPO="$(mktemp -d)"
trap 'rm -rf "${TMP_REPO}"' EXIT

git -C "${TMP_REPO}" init -q
printf 'hello\n' > "${TMP_REPO}/README.md"
git -C "${TMP_REPO}" add README.md
git -C "${TMP_REPO}" commit -m "init" -q

TASKS_FILE="${ROOT_DIR}/.ralph/tasks.jsonc"

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/parser.sh"

cmd="$(json_hook_when_task_command "version.git-rev-short" "${TASKS_FILE}")"
assert_ne "" "${cmd}" "version.git-rev-short should resolve to a command"

expected_rev="$(git -C "${TMP_REPO}" rev-parse --short HEAD)"
actual_rev="$(
  repo_root="${TMP_REPO}" \
  RALPH_PROJECT_DIR="${ROOT_DIR}/.ralph" \
  RALPH_WORKSPACE="${ROOT_DIR}" \
  bash -lc "${cmd}"
)"
assert_eq "${expected_rev}" "${actual_rev}" "version.git-rev-short should match git rev"

cmd="$(json_hook_when_task_command "version.print" "${TASKS_FILE}")"
assert_ne "" "${cmd}" "version.print should resolve to a command"

output="$(
  repo_root="${TMP_REPO}" \
  RALPH_VERSION="9.9.9" \
  RALPH_PROJECT_DIR="${ROOT_DIR}/.ralph" \
  RALPH_WORKSPACE="${ROOT_DIR}" \
  bash -lc "${cmd}"
)"
assert_eq "ralph 9.9.9 (${expected_rev})" "${output}" "version.print should render version and rev"
