#!/usr/bin/env bash
# Ralph installer for GitHub release archives.
# Installs Ralph runtime under ~/.local/share/ralph and creates ~/.local/bin/ralph.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}/.local/share/ralph"
TARGET_BIN_DIR="${HOME}/.local/bin"
TARGET_BIN_LINK="${TARGET_BIN_DIR}/ralph"
FORCE=0
SKIP_SETUP=0
SETUP_FORCE=0

usage() {
  cat <<EOF
Usage:
  ./install.sh [options]

Options:
  --target-home <dir>  Install Ralph files to this directory (default: ~/.local/share/ralph)
  --target-bin <dir>   Install CLI symlink in this bin dir (default: ~/.local/bin)
  --force              Overwrite existing Ralph home directory
  --skip-setup         Skip global baseline setup (~/.ralph)
  --setup-force        Pass --setup-force when running 'ralph --setup'
  -h, --help           Show this help
EOF
}

log() {
  printf '[install] %s\n' "$*"
}

require_source_layout() {
  if [[ ! -f "${SOURCE_DIR}/ralph.sh" ]]; then
    echo "Missing source file: ${SOURCE_DIR}/ralph.sh" >&2
    exit 1
  fi
  if [[ ! -d "${SOURCE_DIR}/.ralph" ]]; then
    echo "Missing source directory: ${SOURCE_DIR}/.ralph" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-home)
        TARGET_HOME="${2:-}"
        shift 2
        ;;
      --target-bin)
        TARGET_BIN_DIR="${2:-}"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --skip-setup)
        SKIP_SETUP=1
        shift
        ;;
      --setup-force)
        SETUP_FORCE=1
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

install_files() {
  TARGET_HOME="${TARGET_HOME/#\~/${HOME}}"
  TARGET_BIN_DIR="${TARGET_BIN_DIR/#\~/${HOME}}"
  TARGET_BIN_LINK="${TARGET_BIN_DIR}/ralph"

  if [[ -e "${TARGET_HOME}" && "${FORCE}" -ne 1 ]]; then
    echo "Target already exists: ${TARGET_HOME} (use --force to overwrite)" >&2
    exit 1
  fi

  mkdir -p "${TARGET_BIN_DIR}"
  rm -rf "${TARGET_HOME}"
  mkdir -p "${TARGET_HOME}"

  cp -a "${SOURCE_DIR}/ralph.sh" "${TARGET_HOME}/ralph.sh"
  cp -a "${SOURCE_DIR}/.ralph" "${TARGET_HOME}/.ralph"
  chmod +x "${TARGET_HOME}/ralph.sh"

  ln -sfn "${TARGET_HOME}/ralph.sh" "${TARGET_BIN_LINK}"

  log "installed home: ${TARGET_HOME}"
  log "installed cli : ${TARGET_BIN_LINK}"
}

run_global_setup() {
  [[ "${SKIP_SETUP}" -eq 1 ]] && return 0

  local -a args=(--setup)
  [[ "${SETUP_FORCE}" -eq 1 ]] && args+=(--setup-force)

  log "running global setup (~/.ralph)"
  "${TARGET_BIN_LINK}" "${args[@]}"
}

print_next_steps() {
  local path_hint=""
  case ":${PATH}:" in
    *":${TARGET_BIN_DIR}:"*) ;;
    *) path_hint="export PATH=\"${TARGET_BIN_DIR}:\$PATH\"" ;;
  esac

  echo
  log "done"
  log "try: ralph --version"
  if [[ -n "${path_hint}" ]]; then
    echo "PATH hint: ${path_hint}"
  fi
}

main() {
  parse_args "$@"
  require_source_layout
  install_files
  run_global_setup
  print_next_steps
}

main "$@"
