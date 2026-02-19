#!/usr/bin/env bash
# Test suite entrypoint.
# Discovers and runs all top-level `test_*.sh` scripts in sorted order.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/tests"

if ! command -v bash >/dev/null 2>&1; then
  echo "bash is required" >&2
  exit 1
fi

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
fi

mapfile -t TEST_FILES < <(find "${TEST_DIR}" -maxdepth 1 -type f -name 'test_*.sh' | sort)

if [[ "${#TEST_FILES[@]}" -eq 0 ]]; then
  echo "No tests found in ${TEST_DIR}" >&2
  exit 1
fi

failed=0
passed=0
suite_start="$(date +%s)"

echo "${C_BOLD}Running test suite${C_RESET}"
echo "${C_DIM}Discovered ${#TEST_FILES[@]} test file(s) in ${TEST_DIR}${C_RESET}"
echo

for t in "${TEST_FILES[@]}"; do
  test_name="$(basename "${t}")"
  test_start="$(date +%s)"

  echo "${C_CYAN}[TEST]${C_RESET} ${test_name}"
  if "${t}"; then
    test_duration="$(( $(date +%s) - test_start ))"
    echo "${C_GREEN}[PASS]${C_RESET} ${test_name} ${C_DIM}(${test_duration}s)${C_RESET}"
    passed=$((passed + 1))
  else
    test_duration="$(( $(date +%s) - test_start ))"
    echo "${C_RED}[FAIL]${C_RESET} ${test_name} ${C_DIM}(${test_duration}s)${C_RESET}"
    failed=$((failed + 1))
  fi
  echo
done

suite_duration="$(( $(date +%s) - suite_start ))"

if [[ "${failed}" -ne 0 ]]; then
  echo "${C_BOLD}${C_RED}Test suite failed${C_RESET}"
  echo "Passed: ${C_GREEN}${passed}${C_RESET}"
  echo "Failed: ${C_RED}${failed}${C_RESET}"
  echo "Total : ${#TEST_FILES[@]}"
  echo "Time  : ${suite_duration}s"
  exit 1
fi

echo "${C_BOLD}${C_GREEN}Test suite passed${C_RESET}"
echo "Passed: ${C_GREEN}${passed}${C_RESET}"
echo "Failed: ${failed}"
echo "Total : ${#TEST_FILES[@]}"
echo "Time  : ${suite_duration}s"
