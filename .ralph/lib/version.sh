#!/usr/bin/env bash
# Shared version helpers for Ralph.
set -euo pipefail

RALPH_VERSION="${RALPH_VERSION:-0.1.0}"

ralph_version_git_rev() {
  local repo_root="${1:-.}"
  if command -v git >/dev/null 2>&1; then
    git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || true
  fi
}

ralph_print_version() {
  local repo_root="${1:-.}"
  local git_rev
  git_rev="$(ralph_version_git_rev "${repo_root}")"
  if [[ -n "${git_rev}" ]]; then
    echo "ralph ${RALPH_VERSION} (${git_rev})"
  else
    echo "ralph ${RALPH_VERSION}"
  fi
}
