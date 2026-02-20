#!/usr/bin/env bash
# Test suite entrypoint.
# Discovers and runs all top-level `test_*.sh` scripts in sorted order.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/tests"
UI_LIB="${ROOT_DIR}/.ralph/lib/ui.sh"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-90}"

if ! command -v bash >/dev/null 2>&1; then
  echo "bash is required" >&2
  exit 1
fi

if [[ -f "${UI_LIB}" ]]; then
  # shellcheck disable=SC1090
  source "${UI_LIB}"
fi

box_border() {
  if command -v ui_box_border >/dev/null 2>&1; then
    ui_box_border "$@"
  else
    local width="${1:-76}"
    printf '+'
    printf '%*s' "$((width + 2))" '' | tr ' ' '-'
    printf '+\n'
  fi
}

box_line() {
  if command -v ui_box_line >/dev/null 2>&1; then
    ui_box_line "$@"
  else
    local text="${1:-}"
    local width="${2:-76}"
    printf '| %-*s |\n' "${width}" "${text}"
  fi
}

box_line_fit() {
  local text="${1:-}"
  local width="${2:-76}"
  local clipped="${text}"
  if [[ "${#clipped}" -gt "${width}" ]]; then
    clipped="${clipped:0:$((width - 3))}..."
  fi
  box_line "${clipped}" "${width}"
}

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
interrupted=0

on_interrupt() {
  interrupted=1
  echo
  box_border 76
  box_line_fit "Test suite interrupted" 76
  box_line_fit "Passed: ${passed}" 76
  box_line_fit "Failed: ${failed}" 76
  box_line_fit "Total : ${#TEST_FILES[@]}" 76
  box_line_fit "Time  : $(( $(date +%s) - suite_start ))s" 76
  box_border 76
  exit 130
}
trap on_interrupt INT TERM

box_border 76
box_line_fit "Running test suite" 76
box_line_fit "Discovered ${#TEST_FILES[@]} test file(s) in ${TEST_DIR}" 76
box_border 76

for t in "${TEST_FILES[@]}"; do
  if [[ "${interrupted}" -eq 1 ]]; then
    box_line_fit "[INT ] interrupted by signal" 76
    break
  fi

  test_name="$(basename "${t}")"
  test_start="$(date +%s)"
  test_log="$(mktemp)"
  box_line_fit "[RUN ] ${test_name}" 76

  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${TEST_TIMEOUT_SECONDS}" "${t}" >"${test_log}" 2>&1
  else
    "${t}" >"${test_log}" 2>&1
  fi
  test_rc=$?

  if [[ "${test_rc}" -eq 0 ]]; then
    test_duration="$(( $(date +%s) - test_start ))"
    box_line_fit "[PASS] ${test_name} (${test_duration}s)" 76
    passed=$((passed + 1))
  else
    test_duration="$(( $(date +%s) - test_start ))"
    if [[ "${test_rc}" -eq 130 || "${test_rc}" -eq 143 ]]; then
      box_line_fit "[INT ] ${test_name} (${test_duration}s)" 76
      interrupted=1
      rm -f "${test_log}"
      break
    fi
    if [[ "${test_rc}" -eq 124 ]]; then
      box_line_fit "[FAIL] ${test_name} (${test_duration}s, timeout ${TEST_TIMEOUT_SECONDS}s)" 76
    else
      box_line_fit "[FAIL] ${test_name} (${test_duration}s)" 76
    fi
    while IFS= read -r log_line; do
      box_line_fit "  ${log_line}" 76
    done < <(sed -n '1,3p' "${test_log}")
    failed=$((failed + 1))
  fi
  rm -f "${test_log}"
done

suite_duration="$(( $(date +%s) - suite_start ))"
box_border 76

if [[ "${interrupted}" -eq 1 ]]; then
  echo
  box_border 76
  box_line_fit "Test suite interrupted" 76
  box_line_fit "Passed: ${passed}" 76
  box_line_fit "Failed: ${failed}" 76
  box_line_fit "Total : ${#TEST_FILES[@]}" 76
  box_line_fit "Time  : ${suite_duration}s" 76
  box_border 76
  exit 130
fi

if [[ "${failed}" -ne 0 ]]; then
  echo
  box_border 76
  box_line_fit "Test suite failed" 76
  box_line_fit "Passed: ${passed}" 76
  box_line_fit "Failed: ${failed}" 76
  box_line_fit "Total : ${#TEST_FILES[@]}" 76
  box_line_fit "Time  : ${suite_duration}s" 76
  box_border 76
  exit 1
fi

echo
box_border 76
box_line_fit "Test suite passed" 76
box_line_fit "Passed: ${passed}" 76
box_line_fit "Failed: ${failed}" 76
box_line_fit "Total : ${#TEST_FILES[@]}" 76
box_line_fit "Time  : ${suite_duration}s" 76
box_border 76
