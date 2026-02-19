#!/usr/bin/env bash
# Restore workspace files from a Ralph session checkpoint.
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  ./.ralph/lib/checkpoint/restore-checkpoint.sh --session-id <id> [options]

Options:
  --session-id <id>        Session id to restore from (required)
  --checkpoint <label>     Checkpoint label (default: pre)
  --workspace <path>       Workspace path (default: current directory)
  --force                  Skip confirmation prompt
  -h, --help               Show help
USAGE
}

SESSION_ID=""
CHECKPOINT_LABEL="pre"
WORKSPACE="$(pwd)"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id) SESSION_ID="${2:-}"; shift 2 ;;
    --checkpoint) CHECKPOINT_LABEL="${2:-}"; shift 2 ;;
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${SESSION_ID}" ]]; then
  echo "--session-id is required" >&2
  usage
  exit 1
fi

WORKSPACE="${WORKSPACE/#\~/$HOME}"
WORKSPACE="$(cd "${WORKSPACE}" && pwd)"
CHECKPOINT_DIR="${WORKSPACE}/.ralph/sessions/${SESSION_ID}/checkpoints/${CHECKPOINT_LABEL}"

if [[ ! -d "${CHECKPOINT_DIR}" ]]; then
  echo "Checkpoint not found: ${CHECKPOINT_DIR}" >&2
  exit 1
fi

if [[ "${FORCE}" -ne 1 ]]; then
  echo "Restore workspace '${WORKSPACE}' from checkpoint '${CHECKPOINT_LABEL}' in session '${SESSION_ID}'?"
  echo "This will overwrite current files (excluding .git and .ralph/sessions)."
  read -r -p "Continue? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git/' \
    --exclude '.ralph/sessions/' \
    "${CHECKPOINT_DIR}/" "${WORKSPACE}/"
else
  echo "warning: rsync not found; using non-destructive overlay restore" >&2
  (cd "${CHECKPOINT_DIR}" && tar -cf - .) | (cd "${WORKSPACE}" && tar -xf -)
fi

echo "Restore complete: ${CHECKPOINT_DIR} -> ${WORKSPACE}"
