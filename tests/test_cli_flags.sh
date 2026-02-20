#!/usr/bin/env bash
# Smoke-tests CLI flag parsing/handling for all documented flags.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

RALPH="${ROOT_DIR}/ralph.sh"
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

TMP_HOME="${TMP_BASE}/home"
TMP_WS="${TMP_BASE}/workspace"
TMP_SETUP_TARGET="${TMP_BASE}/setup-target"
TMP_BIN="${TMP_BASE}/bin"
TMP_DOCKER_LOG="${TMP_BASE}/docker.log"
mkdir -p "${TMP_HOME}" "${TMP_WS}" "${TMP_BIN}"

run_ok() {
  if ! "$@" >/dev/null 2>&1; then
    fail "command failed: $*"
  fi
}

# --help and --version (direct behavior)
run_ok "${RALPH}" --help
run_ok "${RALPH}" --version

# --list-engines (direct behavior)
run_ok "${RALPH}" --list-engines

# Parse-only smoke checks for flags that should be accepted.
# Use --help as terminator to avoid running a full session.
run_ok "${RALPH}" --goal "smoke" --help
run_ok "${RALPH}" --steps 1 --help
run_ok "${RALPH}" --plan "plan.json" --help
run_ok "${RALPH}" --new-plan --help
run_ok "${RALPH}" --reset-plan --help
run_ok "${RALPH}" --guide "AGENTS.md" --help
run_ok "${RALPH}" --workspace "${TMP_WS}" --help
run_ok "${RALPH}" --model "gpt-5" --help
run_ok "${RALPH}" --engine "codex" --help
run_ok "${RALPH}" --ticket "ABC-123" --help
run_ok "${RALPH}" --timeout 30 --help
run_ok "${RALPH}" --checkpoint all --help
run_ok "${RALPH}" --checkpoint-per-step 1 --help
run_ok "${RALPH}" --dry-run --help
run_ok "${RALPH}" --no-colors --help
run_ok "${RALPH}" --verbose --help
run_ok "${RALPH}" --human-guard 0 --help
run_ok "${RALPH}" --human-guard-assume-yes 1 --help
run_ok "${RALPH}" --human-guard-scope both --help
run_ok "${RALPH}" --skip-git-repo-check --help
run_ok "${RALPH}" --setup-force --help
run_ok "${RALPH}" --setup-target "${TMP_SETUP_TARGET}" --help

# --test is parse-only here to avoid recursive test runner execution.
run_ok "${RALPH}" --test --help

# Real --setup flow in isolated HOME and target folder.
run_ok env HOME="${TMP_HOME}" "${RALPH}" --setup --setup-target "${TMP_SETUP_TARGET}"
assert_file_exists "${TMP_SETUP_TARGET}/profile.jsonc" "setup should install profile"
assert_file_exists "${TMP_SETUP_TARGET}/hooks.jsonc" "setup should install hooks"

# Verify --setup-force path also works.
run_ok env HOME="${TMP_HOME}" "${RALPH}" --setup --setup-force --setup-target "${TMP_SETUP_TARGET}"

# Fake docker binary to test --docker flags without real Docker dependency.
cat > "${TMP_BIN}/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_DOCKER_LOG:-}" ]]; then
  echo "$*" >> "${FAKE_DOCKER_LOG}"
fi

case "${1:-}" in
  build)
    exit 0
    ;;
  image)
    if [[ "${2:-}" == "inspect" ]]; then
      exit 1
    fi
    exit 0
    ;;
  run)
    exit 0
    ;;
esac

exit 0
DOCKER
chmod +x "${TMP_BIN}/docker"

FAKE_PATH="${TMP_BIN}:${PATH}"

run_ok env PATH="${FAKE_PATH}" FAKE_DOCKER_LOG="${TMP_DOCKER_LOG}" HOME="${TMP_HOME}" \
  "${RALPH}" --docker-build
run_ok env PATH="${FAKE_PATH}" FAKE_DOCKER_LOG="${TMP_DOCKER_LOG}" HOME="${TMP_HOME}" \
  "${RALPH}" --docker --goal "smoke" --workspace "${TMP_WS}" --dry-run
run_ok env PATH="${FAKE_PATH}" FAKE_DOCKER_LOG="${TMP_DOCKER_LOG}" HOME="${TMP_HOME}" \
  "${RALPH}" --docker-rebuild --goal "smoke" --workspace "${TMP_WS}" --dry-run

assert_file_exists "${TMP_DOCKER_LOG}" "docker flags should invoke docker"
