#!/usr/bin/env bash
# Workspace checkpoint helpers for non-git rollback safety.
set -euo pipefail

# Copy workspace into checkpoint directory while excluding volatile state.
checkpoint_copy_workspace() {
  local workspace="${1:-.}"
  local destination="${2:?destination required}"

  mkdir -p "${destination}"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.git/' \
      --exclude '.ralph/sessions/' \
      --exclude '.ralph/checkpoints/' \
      "${workspace}/" "${destination}/"
    return 0
  fi

  # Fallback when rsync is unavailable.
  (cd "${workspace}" && tar --exclude='.git' --exclude='.ralph/sessions' --exclude='.ralph/checkpoints' -cf - .) | \
    (cd "${destination}" && tar -xf -)
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

  local meta_file="${destination}/.checkpoint.meta"
  {
    echo "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "label=${label}"
    echo "session_id=${session_id}"
    echo "workspace=${workspace}"
    echo "step=${step}"
    echo "plan_file=${plan_file}"
    echo "ticket=${ticket}"
    if [[ -n "${plan_file}" ]] && [[ -f "${plan_file}" ]] && command -v sha256sum >/dev/null 2>&1; then
      echo "plan_sha256=$(sha256sum "${plan_file}" | awk '{print $1}')"
    fi
  } > "${meta_file}"
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
