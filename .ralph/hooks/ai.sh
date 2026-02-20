#!/usr/bin/env bash
# =============================================================================
# AI Engine Hook
# =============================================================================
#
# Executes AI model based on RALPH_ENGINE environment variable.
# Engine definitions are loaded from tasks.jsonc (engines array).
#
# Environment variables:
#   RALPH_ENGINE        Engine to use (default: auto-detect)
#   RALPH_PROMPT_FILE   Path to prompt file
#   RALPH_RESPONSE_FILE Path to write response
#   RALPH_MODEL         Model override (optional)
#   RALPH_WORKSPACE     Working directory
#   RALPH_DRY_RUN       "1" for dry-run mode (uses mock engine)
#
# Special modes:
#   RALPH_ENGINE=list   List available engines and exit
#
# Exit codes:
#   0 = success
#   1 = failure
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

ENGINE="${RALPH_ENGINE:-}"
PROMPT_FILE="${RALPH_PROMPT_FILE:-}"
RESPONSE_FILE="${RALPH_RESPONSE_FILE:-}"
MODEL="${RALPH_MODEL:-}"
WORKSPACE="${RALPH_WORKSPACE:-.}"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="${RALPH_TASKS_FILE:-${WORKSPACE}/.ralph/tasks.jsonc}"

# Load parser for task helpers
if [[ -f "${HOOKS_DIR}/../lib/core/parser.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOOKS_DIR}/../lib/core/parser.sh"
fi

# =============================================================================
# Engine Discovery (from tasks.jsonc)
# =============================================================================

# Get normalized tasks JSON
get_tasks_json() {
  local norm
  norm="$(json_like_to_temp_file "${TASKS_FILE}" 2>/dev/null || true)"
  if [[ -n "${norm}" && -f "${norm}" ]]; then
    echo "${norm}"
  fi
}

# List all engine codes from tasks.jsonc
get_engine_codes() {
  local tasks_json
  tasks_json="$(get_tasks_json)"
  [[ -n "${tasks_json}" ]] || return 1
  jq -r '.engines[]? | .code' "${tasks_json}" 2>/dev/null
  rm -f "${tasks_json}"
}

# Get engine property by code
get_engine_prop() {
  local code="$1"
  local prop="$2"
  local tasks_json
  tasks_json="$(get_tasks_json)"
  [[ -n "${tasks_json}" ]] || return 1
  local val
  val="$(jq -r --arg code "${code}" --arg prop "${prop}" \
    '.engines[]? | select(.code == $code) | .[$prop] // empty' "${tasks_json}" 2>/dev/null)"
  rm -f "${tasks_json}"
  echo "${val}"
}

# Check if engine is available
engine_available() {
  local code="$1"
  local detect_cmd
  detect_cmd="$(get_engine_prop "${code}" "detect")"
  [[ -n "${detect_cmd}" ]] || return 1
  bash -c "${detect_cmd}" >/dev/null 2>&1
}

# Run engine
run_engine() {
  local code="$1"
  local run_cmd
  run_cmd="$(get_engine_prop "${code}" "run")"
  [[ -n "${run_cmd}" ]] || { echo "[ai] ERROR: No run command for engine: ${code}" >&2; return 1; }

  # Expand task references if present
  if [[ "${run_cmd}" == task:* ]]; then
    run_task "${run_cmd#task:}"
  else
    bash -c "${run_cmd}"
  fi
}

# =============================================================================
# List Available Engines
# =============================================================================

list_engines() {
  echo "Available AI engines:"
  echo ""

  local tasks_json code label detect_cmd
  tasks_json="$(get_tasks_json)"
  [[ -n "${tasks_json}" ]] || { echo "  (no engines defined in tasks.jsonc)"; return 0; }

  while IFS=$'\t' read -r code label; do
    [[ -n "${code}" ]] || continue
    if engine_available "${code}"; then
      echo "  [x] ${code} - ${label}"
    else
      echo "  [ ] ${code} - ${label} (not available)"
    fi
  done < <(jq -r '.engines[]? | [.code, .label] | @tsv' "${tasks_json}" 2>/dev/null)

  rm -f "${tasks_json}"
  echo ""
}

# =============================================================================
# Auto-detect Best Engine
# =============================================================================

auto_detect_engine() {
  local tasks_json code
  tasks_json="$(get_tasks_json)"
  [[ -n "${tasks_json}" ]] || return 1

  # Iterate engines sorted by priority
  while IFS= read -r code; do
    [[ -n "${code}" ]] || continue
    if engine_available "${code}"; then
      rm -f "${tasks_json}"
      echo "${code}"
      return 0
    fi
  done < <(jq -r '.engines | sort_by(.priority)[]? | .code' "${tasks_json}" 2>/dev/null)

  rm -f "${tasks_json}"
  return 1
}

# =============================================================================
# Validation
# =============================================================================

validate_inputs() {
  if [[ -z "${PROMPT_FILE}" ]]; then
    echo "[ai] ERROR: RALPH_PROMPT_FILE not set" >&2
    exit 1
  fi

  if [[ ! -f "${PROMPT_FILE}" ]]; then
    echo "[ai] ERROR: Prompt file not found: ${PROMPT_FILE}" >&2
    exit 1
  fi

  if [[ -z "${RESPONSE_FILE}" ]]; then
    echo "[ai] ERROR: RALPH_RESPONSE_FILE not set" >&2
    exit 1
  fi
}

# Validates model/engine compatibility using model_pattern from tasks.jsonc
validate_engine_model_compatibility() {
  [[ -n "${MODEL}" ]] || return 0

  local pattern
  pattern="$(get_engine_prop "${ENGINE}" "model_pattern")"
  [[ -n "${pattern}" ]] || return 0

  local model_lower
  model_lower="$(printf '%s' "${MODEL}" | tr '[:upper:]' '[:lower:]')"

  if ! [[ "${model_lower}" =~ ${pattern} ]]; then
    echo "[ai] WARNING: model '${MODEL}' may not be compatible with engine '${ENGINE}'" >&2
    echo "[ai] Expected pattern: ${pattern}" >&2
  fi
}

# =============================================================================
# Verify Response
# =============================================================================

verify_response() {
  if [[ ! -s "${RESPONSE_FILE}" ]]; then
    echo "[ai] WARNING: Empty response from ${ENGINE}" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
  # Special mode: list engines
  if [[ "${ENGINE}" == "list" ]]; then
    list_engines
    exit 0
  fi

  # Dry-run mode: force mock engine
  if [[ "${RALPH_DRY_RUN:-0}" == "1" ]]; then
    ENGINE="mock"
    echo "[ai] Dry-run mode: using mock engine"
  fi

  # Auto-detect engine if not specified
  if [[ -z "${ENGINE}" ]]; then
    ENGINE="$(auto_detect_engine || true)"
    if [[ -z "${ENGINE}" ]]; then
      echo "[ai] ERROR: No AI engine available" >&2
      echo "[ai] Run with RALPH_ENGINE=list to see options" >&2
      exit 1
    fi
    echo "[ai] Auto-detected: ${ENGINE}"
  fi

  # Verify engine exists
  if [[ -z "$(get_engine_prop "${ENGINE}" "run")" ]]; then
    echo "[ai] ERROR: Unknown engine: ${ENGINE}" >&2
    echo "[ai] Run with RALPH_ENGINE=list to see available engines" >&2
    exit 1
  fi

  validate_inputs
  validate_engine_model_compatibility

  echo "[ai] Engine: ${ENGINE}"
  [[ -n "${MODEL}" ]] && echo "[ai] Model: ${MODEL}"
  echo "[ai] Prompt: ${PROMPT_FILE}"

  # Run the engine
  if ! run_engine "${ENGINE}"; then
    echo "[ai] ERROR: Engine '${ENGINE}' failed" >&2
    exit 1
  fi

  # Verify output
  verify_response

  echo "[ai] Response: ${RESPONSE_FILE}"
  exit 0
}

main "$@"
