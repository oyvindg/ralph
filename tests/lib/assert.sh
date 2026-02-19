#!/usr/bin/env bash
# Minimal assertion helpers shared by all test scripts.
set -euo pipefail

# Fails the current test with a readable message.
fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

# Asserts string equality.
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assert_eq failed}"
  [[ "${expected}" == "${actual}" ]] || fail "${msg}: expected='${expected}' actual='${actual}'"
}

# Asserts string inequality.
assert_ne() {
  local not_expected="$1"
  local actual="$2"
  local msg="${3:-assert_ne failed}"
  [[ "${not_expected}" != "${actual}" ]] || fail "${msg}: value='${actual}'"
}

# Asserts that a substring exists.
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-assert_contains failed}"
  [[ "${haystack}" == *"${needle}"* ]] || fail "${msg}: missing '${needle}'"
}

# Asserts that a regular file exists.
assert_file_exists() {
  local path="$1"
  local msg="${2:-assert_file_exists failed}"
  [[ -f "${path}" ]] || fail "${msg}: ${path}"
}

# Asserts that a command exit code is success (0).
assert_success() {
  local rc="$1"
  local msg="${2:-expected success}"
  [[ "${rc}" -eq 0 ]] || fail "${msg}: rc=${rc}"
}

# Asserts that a command exit code is non-zero.
assert_failure() {
  local rc="$1"
  local msg="${2:-expected failure}"
  [[ "${rc}" -ne 0 ]] || fail "${msg}: rc=${rc}"
}
