#!/usr/bin/env bash
# Validates profile loading from JSONC.
# Verifies project profile overrides global profile and route/provider normalization.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

TMP_HOME="$(mktemp -d)"
TMP_WS="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}" "${TMP_WS}"' EXIT

mkdir -p "${TMP_HOME}/.ralph"
cat > "${TMP_HOME}/.ralph/profile.jsonc" <<'JSON'
{
  "defaults": {
    "engine": "codex",
    "model": "global-model",
    "issues_providers": ["jira"],
    "agent_routes": [
      { "match": "default", "engine": "codex", "model": "global-default" }
    ]
  },
  "hooks": { "disabled": ["on-error"] }
}
JSON

mkdir -p "${TMP_WS}/.ralph"
cat > "${TMP_WS}/.ralph/profile.jsonc" <<'JSON'
{
  "defaults": {
    "engine": "claude",
    "model": "project-model",
    "issues_providers": ["git","jira"],
    "agent_routes": [
      { "match": "test", "engine": "claude", "model": "sonnet" },
      { "match": "default", "engine": "codex", "model": "gpt-5.3-codex" }
    ]
  },
  "hooks": { "disabled": ["ai"] }
}
JSON

HOME="${TMP_HOME}"
ROOT="${TMP_WS}"
SCRIPT_DIR="${ROOT_DIR}"
RALPH_PROJECT_DIR=""
RALPH_GLOBAL_DIR=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/.ralph/lib/core/config.sh"

find_ralph_dirs
load_profile

assert_eq "claude" "${PROFILE_ENGINE}" "project engine should override global"
assert_eq "project-model" "${PROFILE_MODEL}" "project model should override global"
assert_eq "git,jira" "${PROFILE_ISSUES_PROVIDERS}" "issues providers should be csv"
assert_contains "${PROFILE_AGENT_ROUTES}" "test|claude|sonnet" "object route should be normalized"
assert_contains "${PROFILE_AGENT_ROUTES}" "default|codex|gpt-5.3-codex" "default route should be normalized"
assert_contains "${PROFILE_DISABLED_HOOKS}" "ai" "project disabled hooks should apply"
