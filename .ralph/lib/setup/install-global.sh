#!/usr/bin/env bash
# Installs Ralph global baseline files into ~/.ralph (or custom target).
# Source of truth is this repository's `.ralph` directory.
set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_RALPH_DIR="$(cd "${SETUP_DIR}/../.." && pwd)"
MANIFEST_FILE="${SETUP_DIR}/manifest.txt"
TARGET_DIR="${HOME}/.ralph"
FORCE=0

usage() {
  cat <<EOF
Usage:
  ${0} [--target <dir>] [--force]

Options:
  --target <dir>  Install target directory (default: ~/.ralph)
  --force         Overwrite existing files/directories in target
EOF
}

log() {
  printf '[setup] %s\n' "$*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        TARGET_DIR="${2:-}"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

read_manifest() {
  [[ -f "${MANIFEST_FILE}" ]] || {
    echo "Manifest not found: ${MANIFEST_FILE}" >&2
    exit 1
  }

  mapfile -t MANIFEST_ITEMS < <(grep -vE '^[[:space:]]*(#|$)' "${MANIFEST_FILE}" | sed 's/[[:space:]]*$//')
  [[ "${#MANIFEST_ITEMS[@]}" -gt 0 ]] || {
    echo "Manifest is empty: ${MANIFEST_FILE}" >&2
    exit 1
  }
}

install_item() {
  local raw_rel="$1"
  local expect_dir=0
  local rel="${raw_rel}"
  [[ "${raw_rel}" == */ ]] && expect_dir=1
  rel="${rel%/}"

  local src="${SOURCE_RALPH_DIR}/${rel}"
  local dst="${TARGET_DIR}/${rel}"

  if [[ ! -e "${src}" ]]; then
    log "skip missing source: ${raw_rel}"
    return 0
  fi
  if [[ "${expect_dir}" -eq 1 && ! -d "${src}" ]]; then
    echo "Manifest expects directory but found non-directory: ${raw_rel}" >&2
    exit 1
  fi
  if [[ "${expect_dir}" -eq 0 && -d "${src}" ]]; then
    log "warning: directory listed without trailing '/': ${raw_rel}"
  fi

  if [[ -e "${dst}" && "${FORCE}" -ne 1 ]]; then
    log "keep existing: ${raw_rel}"
    return 0
  fi

  mkdir -p "$(dirname "${dst}")"
  rm -rf "${dst}"
  cp -a "${src}" "${dst}"
  log "installed: ${raw_rel}"
}

main() {
  parse_args "$@"
  TARGET_DIR="${TARGET_DIR/#\~/${HOME}}"
  mkdir -p "${TARGET_DIR}"

  read_manifest
  log "source: ${SOURCE_RALPH_DIR}"
  log "target: ${TARGET_DIR}"
  [[ "${FORCE}" -eq 1 ]] && log "mode: force overwrite" || log "mode: keep existing"

  local item
  for item in "${MANIFEST_ITEMS[@]}"; do
    install_item "${item}"
  done

  log "done"
}

main "$@"
