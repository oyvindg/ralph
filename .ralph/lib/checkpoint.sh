#!/usr/bin/env bash
# Workspace checkpoint helpers for non-git rollback safety.
# Delegates to task:checkpoint.* and task:has.* from tasks.jsonc.
set -euo pipefail

CHECKPOINT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load parser for run_task/task_condition helpers
if [[ -f "${CHECKPOINT_LIB_DIR}/core/parser.sh" ]]; then
  # shellcheck disable=SC1091
  source "${CHECKPOINT_LIB_DIR}/core/parser.sh"
fi

# Copy workspace into checkpoint directory while excluding volatile state.
checkpoint_copy_workspace() {
  local workspace="${1:-.}"
  local destination="${2:?destination required}"

  mkdir -p "${destination}"

  export RALPH_WORKSPACE="${workspace}"
  export CHECKPOINT_DEST="${destination}"

  if task_condition "has.rsync"; then
    run_task "checkpoint.copy-rsync"
  else
    run_task "checkpoint.copy-tar"
  fi
}

# Write simple metadata beside each checkpoint snapshot.
checkpoint_write_metadata() {
  local destination="${1:?destination required}"
  local label="${2:-unknown}"
  local workspace="${3:-.}"
  local session_id="${4:-session}"
  local step="${5:-}"
  local plan_file="${6:-}"
  local ticket="${7:-}"

  export CHECKPOINT_DEST="${destination}"
  export CHECKPOINT_LABEL="${label}"
  export RALPH_WORKSPACE="${workspace}"
  export RALPH_SESSION_ID="${session_id}"
  export RALPH_STEP="${step}"
  export RALPH_PLAN_FILE="${plan_file}"
  export RALPH_TICKET="${ticket}"

  run_task "checkpoint.write-metadata"
}

# Create one checkpoint folder under current session.
checkpoint_create() {
  local workspace="${1:-.}"
  local session_dir="${2:?session dir required}"
  local label="${3:?label required}"
  local step="${4:-}"
  local plan_file="${5:-}"
  local ticket="${6:-}"

  local checkpoints_root="${session_dir}/checkpoints"
  local destination="${checkpoints_root}/${label}"
  mkdir -p "${checkpoints_root}"

  checkpoint_copy_workspace "${workspace}" "${destination}"
  checkpoint_write_metadata "${destination}" "${label}" "${workspace}" "$(basename "${session_dir}")" "${step}" "${plan_file}" "${ticket}"
  printf '%s\n' "${destination}"
}
