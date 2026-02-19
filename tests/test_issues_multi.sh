#!/usr/bin/env bash
# Validates multi-provider issue adapter behavior.
# Uses local stubs to test provider order, explicit ticket precedence, and merged context.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/issues.sh"

issues_git_infer_ticket() {
  local workspace="$1"
  [[ -n "${workspace}" ]] || return 1
  printf 'GIT-42\n'
}

issues_jira_fetch_context() {
  local ticket="$1"
  printf 'Jira context for %s\n' "${ticket}"
}

t1="$(issues_resolve_ticket_multi "git,jira" "" ".")"
assert_eq "GIT-42" "${t1}" "should resolve ticket from first provider with value"

t2="$(issues_resolve_ticket_multi "git,jira" "EXPLICIT-1" ".")"
assert_eq "EXPLICIT-1" "${t2}" "explicit ticket should win"

ctx="$(issues_fetch_context_multi "git,jira" "ABC-1")"
assert_contains "${ctx}" "Provider: git" "should include git context"
assert_contains "${ctx}" "Provider: jira" "should include jira context"
assert_contains "${ctx}" "Jira context for ABC-1" "should include jira details"
