#!/usr/bin/env bash
# Shared JSON/JSONC helpers for Ralph config parsing.
#
# Note:
# - JSONC support assumes comments are placed on dedicated lines
#   (`// ...` or `/* ... */` blocks).
#
# This file is intended to be sourced by other scripts.

# Emits normalized JSON content from JSON/JSONC file to stdout.
json_like_emit() {
  local file="$1"
  case "${file}" in
    *.jsonc)
      awk '
        BEGIN { in_block = 0 }
        {
          line = $0
          if (in_block == 1) {
            if (line ~ /\*\//) {
              sub(/^.*\*\//, "", line)
              in_block = 0
            } else {
              next
            }
          }
          if (line ~ /^[[:space:]]*\/\*/) {
            if (line !~ /\*\//) {
              in_block = 1
            }
            next
          }
          if (line ~ /^[[:space:]]*\/\//) next
          print line
        }
      ' "${file}"
      ;;
    *)
      cat "${file}"
      ;;
  esac
}

# Writes normalized JSON to a temporary file and prints the file path.
json_like_to_temp_file() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if ! json_like_emit "${file}" > "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  printf '%s\n' "${tmp}"
}
