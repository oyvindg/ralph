#!/usr/bin/env bash
# Shared Git helpers for Ralph hooks.
set -euo pipefail

git_is_repo() {
  local workspace="${1:-.}"
  git -C "${workspace}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

git_branch() {
  local workspace="${1:-.}"
  local branch
  branch="$(git -C "${workspace}" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "${branch}" ]]; then
    branch="detached"
  fi
  printf '%s\n' "${branch}"
}

git_head_short() {
  local workspace="${1:-.}"
  git -C "${workspace}" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

git_status_short() {
  local workspace="${1:-.}"
  git -C "${workspace}" status --short 2>/dev/null || true
}

git_diff_stat() {
  local workspace="${1:-.}"
  git -C "${workspace}" diff --stat 2>/dev/null || true
}
