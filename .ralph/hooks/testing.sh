#!/usr/bin/env bash
# =============================================================================
# Testing Hook
# =============================================================================
#
# Runs project tests. Called by quality-gate or directly.
# Auto-detects test runner based on project files.
#
# Exit codes:
#   0 = tests passed (or no tests found)
#   1 = tests failed
#
# Environment variables:
#   RALPH_WORKSPACE     Working directory
#   RALPH_DRY_RUN       "1" for dry-run mode
#
# =============================================================================

set -euo pipefail

WORKSPACE="${RALPH_WORKSPACE:-.}"
DRY_RUN="${RALPH_DRY_RUN:-0}"
SESSION_DIR="${RALPH_SESSION_DIR:-}"
STEP="${RALPH_STEP:-0}"
ASSUME_YES="${RALPH_HUMAN_GUARD_ASSUME_YES:-0}"
TEMP_SUITE_ON_NO_TESTS="${RALPH_TEMP_TEST_SUITE_ON_NO_TESTS:-1}"

# Failure simulation
MOCK_FAIL="${RALPH_MOCK_FAIL_TEST:-0}"
MOCK_FAIL_RATE="${RALPH_MOCK_FAIL_TEST_RATE:-}"

indent() {
  local depth="${RALPH_HOOK_DEPTH:-0}"
  local out=""
  local i=0
  while [[ "${i}" -lt "${depth}" ]]; do
    out="${out}  "
    ((i++)) || true
  done
  printf '%s' "${out}"
}

t_log() {
  echo "$(indent)[testing] $1"
}

should_run_temp_suite() {
  [[ "${TEMP_SUITE_ON_NO_TESTS}" == "1" ]] || return 1

  if [[ "${ASSUME_YES}" == "1" ]]; then
    t_log "No tests found; auto-approving temporary test suite (assume-yes)"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    t_log "No tests found; non-interactive shell, skipping temporary test suite prompt"
    return 1
  fi

  local answer
  read -r -p "$(indent)[testing] No tests found. Create temporary test suite for this run? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_temp_suite() {
  local suite_dir suite_file
  if [[ -n "${SESSION_DIR}" ]]; then
    suite_dir="${SESSION_DIR}"
  else
    suite_dir="${WORKSPACE}/.ralph/tmp"
  fi
  mkdir -p "${suite_dir}"
  suite_file="${suite_dir}/temp_test_suite_step_${STEP}.sh"

  cat > "${suite_file}" <<'SUITE'
#!/usr/bin/env bash
set -euo pipefail

workspace="${1:-.}"
echo "[temp-test] Running temporary sanity suite in: ${workspace}"

if [[ ! -d "${workspace}" ]]; then
  echo "[temp-test] FAIL: workspace is not a directory"
  exit 1
fi

file_count="$(find "${workspace}" -maxdepth 3 -type f ! -path "${workspace}/.git/*" | wc -l | tr -d ' ')"
if [[ "${file_count}" -eq 0 ]]; then
  echo "[temp-test] FAIL: no files found in workspace"
  exit 1
fi
echo "[temp-test] PASS: workspace contains ${file_count} file(s)"

if command -v git >/dev/null 2>&1 && git -C "${workspace}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${workspace}" status --porcelain >/dev/null
  echo "[temp-test] PASS: git repository status is readable"
fi

echo "[temp-test] PASS: temporary sanity suite completed"
SUITE

  chmod +x "${suite_file}"
  t_log "Running temporary test suite: ${suite_file}"
  "${suite_file}" "${WORKSPACE}"
}

# =============================================================================
# Test Runner Detection
# =============================================================================

detect_make() {
  [[ -f "${WORKSPACE}/Makefile" ]] && grep -q "^test:" "${WORKSPACE}/Makefile" 2>/dev/null
}

detect_npm() {
  [[ -f "${WORKSPACE}/package.json" ]] && \
    grep -q '"test"' "${WORKSPACE}/package.json" 2>/dev/null
}

detect_pytest() {
  [[ -f "${WORKSPACE}/pytest.ini" ]] || \
    [[ -f "${WORKSPACE}/setup.py" ]] || \
    [[ -d "${WORKSPACE}/tests" ]]
}

detect_go() {
  [[ -f "${WORKSPACE}/go.mod" ]]
}

detect_cargo() {
  [[ -f "${WORKSPACE}/Cargo.toml" ]]
}

# =============================================================================
# Test Runners
# =============================================================================

run_make_test() {
  t_log "Running: make test"
  make -C "${WORKSPACE}" test
}

run_npm_test() {
  t_log "Running: npm test"
  npm --prefix "${WORKSPACE}" test
}

run_pytest() {
  t_log "Running: pytest"
  (cd "${WORKSPACE}" && pytest)
}

run_go_test() {
  t_log "Running: go test"
  (cd "${WORKSPACE}" && go test ./...)
}

run_cargo_test() {
  t_log "Running: cargo test"
  (cd "${WORKSPACE}" && cargo test)
}

# =============================================================================
# List Available Runners
# =============================================================================

list_runners() {
  t_log "Available test runners:"

  detect_make   && echo "  [x] make test" || echo "  [ ] make test"
  detect_npm    && echo "  [x] npm test"  || echo "  [ ] npm test"
  detect_pytest && echo "  [x] pytest"    || echo "  [ ] pytest"
  detect_go     && echo "  [x] go test"   || echo "  [ ] go test"
  detect_cargo  && echo "  [x] cargo test"|| echo "  [ ] cargo test"
}

# =============================================================================
# Dry-Run
# =============================================================================

run_dry() {
  t_log "=== DRY-RUN ==="

  # Check for forced failure simulation
  if [[ "${MOCK_FAIL}" == "1" ]]; then
    t_log "MOCK: Simulating test failure"
    t_log "FAILED: Simulated test failure for testing"
    return 1
  fi

  # Check for random failure
  if [[ -n "${MOCK_FAIL_RATE}" ]]; then
    local rand=$((RANDOM % 100))
    if [[ "${rand}" -lt "${MOCK_FAIL_RATE}" ]]; then
      t_log "MOCK: Random test failure (${rand} < ${MOCK_FAIL_RATE}%)"
      t_log "FAILED: Random simulated failure"
      return 1
    fi
  fi

  list_runners

  local count=0
  detect_make   && ((count++)) || true
  detect_npm    && ((count++)) || true
  detect_pytest && ((count++)) || true
  detect_go     && ((count++)) || true
  detect_cargo  && ((count++)) || true

  echo ""
  if [[ "${count}" -eq 0 ]]; then
    t_log "No test runners detected"
    if [[ "${TEMP_SUITE_ON_NO_TESTS}" == "1" ]]; then
      if [[ "${ASSUME_YES}" == "1" ]]; then
        t_log "Would auto-run temporary test suite (assume-yes)"
      else
        t_log "Would prompt to run temporary test suite"
      fi
    else
      t_log "Temporary test suite fallback disabled"
    fi
  else
    t_log "Would run ${count} test suite(s)"
  fi

  t_log "DRY-RUN: Simulated pass"
  return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
  t_log "Workspace: ${WORKSPACE}"

  # Dry-run mode
  if [[ "${DRY_RUN}" == "1" ]]; then
    run_dry
    exit 0
  fi

  local ran=0
  local failed=0

  # Run all detected test suites
  if detect_make; then
    ((ran++)) || true
    run_make_test || ((failed++)) || true
  fi

  if detect_npm; then
    ((ran++)) || true
    run_npm_test || ((failed++)) || true
  fi

  if detect_pytest; then
    ((ran++)) || true
    run_pytest || ((failed++)) || true
  fi

  if detect_go; then
    ((ran++)) || true
    run_go_test || ((failed++)) || true
  fi

  if detect_cargo; then
    ((ran++)) || true
    run_cargo_test || ((failed++)) || true
  fi

  # Report results
  if [[ "${ran}" -eq 0 ]]; then
    t_log "No test runners found"
    if should_run_temp_suite; then
      if run_temp_suite; then
        t_log "PASSED: temporary test suite"
        exit 0
      fi
      t_log "FAILED: temporary test suite"
      exit 1
    fi

    t_log "Skipping temporary test suite; continuing without tests"
    exit 0
  fi

  if [[ "${failed}" -gt 0 ]]; then
    t_log "FAILED: ${failed}/${ran} test suite(s) failed"
    exit 1
  fi

  t_log "PASSED: ${ran} test suite(s)"
  exit 0
}

main "$@"
