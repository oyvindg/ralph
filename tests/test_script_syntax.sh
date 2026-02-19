#!/usr/bin/env bash
# Validates shell syntax (`bash -n`) for every script in the repository.
# This is a fast baseline check and does not execute script runtime logic.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tests/lib/assert.sh"

rc=0
while IFS= read -r script; do
  if ! bash -n "${script}"; then
    echo "syntax error: ${script}" >&2
    rc=1
  fi
done < <(find "${ROOT_DIR}" -type f -name '*.sh' -not -path '*/.git/*' | sort)

assert_success "${rc}" "shell syntax validation failed"
