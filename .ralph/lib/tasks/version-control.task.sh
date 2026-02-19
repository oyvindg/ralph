#!/usr/bin/env bash
# Task wrapper for version-control step logging.
# Keeps task execution logic in shell, while tasks.json stays declarative.
# This task is the canonical implementation for step change logging.
set -euo pipefail

TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${TASK_DIR}/.." && pwd)"

if [[ -f "${LIB_DIR}/log.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/log.sh"
else
  ralph_log() { echo "[$2] $3"; }
  ralph_event() { :; }
fi

if [[ -f "${LIB_DIR}/source-control.sh" ]]; then
  # shellcheck disable=SC1091
  source "${LIB_DIR}/source-control.sh"
else
  vcs_backend() { echo "filesystem-snapshot"; }
  vcs_ref() { echo "n/a"; }
  vcs_status_title() { echo "VCS status"; }
  vcs_status_short() { echo "(not available)"; }
  vcs_diff_title() { echo "VCS diff (stat)"; }
  vcs_diff_stat() { echo "(not available)"; }
  sc_commit_step_if_enabled() { :; }
fi

WORKSPACE="${RALPH_WORKSPACE:-.}"
STEP="${RALPH_STEP:-?}"
STEP_MARKER="${RALPH_STEP_MARKER:-}"
CHANGE_LOG_FILE="${RALPH_CHANGE_LOG_FILE:-}"
GOAL="${RALPH_GOAL:-}"
TICKET="${RALPH_TICKET:-}"
ALLOW_COMMITS="${RALPH_SOURCE_CONTROL_ALLOW_COMMITS:-0}"

# Lists files changed after step marker, excluding VCS internals and session artifacts.
list_changed_files_since_marker() {
  local marker_file="$1"
  find "${WORKSPACE}" -type f -newer "${marker_file}" \
    ! -path "${WORKSPACE}/.git/*" \
    ! -path "${WORKSPACE}/.ralph/sessions/*" \
    -print | sed "s#^${WORKSPACE}/##" | sort
}

main() {
  if [[ -z "${CHANGE_LOG_FILE}" ]]; then
    ralph_log "WARN" "task.version-control" "RALPH_CHANGE_LOG_FILE not set; skipping"
    exit 0
  fi

  mkdir -p "$(dirname "${CHANGE_LOG_FILE}")"
  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    echo "# Step ${STEP} Change Log"
    echo ""
    echo "- generated_utc: ${generated_at}"
    local backend
    backend="$(vcs_backend "${WORKSPACE}")"
    if [[ "${backend}" == "git" ]]; then
      echo "- source: ${backend}"
      echo "- source_control_backend: ${backend}"
      echo "- source_control_ref: $(vcs_ref "${WORKSPACE}")"
    else
      echo "- source: ${backend}"
      echo "- source_control_backend: ${backend}"
      echo "- source_control_ref: n/a"
      echo "- note: no VCS backend detected; listing files modified after step start marker."
    fi
    echo ""
    echo "## Files changed during step"
    echo ""
    if [[ -n "${STEP_MARKER}" ]] && [[ -f "${STEP_MARKER}" ]]; then
      local changed_files
      changed_files="$(list_changed_files_since_marker "${STEP_MARKER}" || true)"
      if [[ -n "${changed_files}" ]]; then
        while IFS= read -r file; do
          [[ -n "${file}" ]] && echo "- ${file}"
        done <<< "${changed_files}"
      else
        echo "- (none detected)"
      fi
    else
      echo "- (step marker missing: cannot compute file snapshot diff)"
    fi

    if [[ "${backend}" != "filesystem-snapshot" ]]; then
      echo ""
      echo "## $(vcs_status_title "${backend}")"
      echo ""
      echo '```text'
      vcs_status_short "${WORKSPACE}"
      echo '```'
      echo ""
      echo "## $(vcs_diff_title "${backend}")"
      echo ""
      echo '```text'
      vcs_diff_stat "${WORKSPACE}"
      echo '```'
    fi
  } > "${CHANGE_LOG_FILE}"

  # Optional git checkpoint commit (policy-controlled).
  sc_commit_step_if_enabled "${WORKSPACE}" "${ALLOW_COMMITS}" "${STEP}" "${GOAL}" "${TICKET}" || true

  ralph_log "INFO" "task.version-control" "Wrote change log: ${CHANGE_LOG_FILE}"
  ralph_event "task_version_control" "ok" "change log generated"
}

main "$@"
