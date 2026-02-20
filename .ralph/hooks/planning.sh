#!/usr/bin/env bash
# =============================================================================
# Planning Hook
# =============================================================================
#
# Generates plan.json via AI engine (uses ai.sh hook).
# Called by: before-session, or when quality-gate returns exit 2
#
# Exit codes:
#   0 = plan exists or was generated successfully
#   1 = failed to generate plan
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PLAN_FILE="${RALPH_PLAN_FILE:-${RALPH_WORKSPACE}/.ralph/plans/plan.json}"
PLAN_CONTEXT_FILE="${RALPH_PLAN_CONTEXT_FILE:-}"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_FORCE_REGENERATE="${RALPH_PLAN_FORCE_REGENERATE:-0}"
PLAN_FEEDBACK="${RALPH_PLAN_FEEDBACK:-}"

indent() {
  local depth="${RALPH_HOOK_DEPTH:-0}"
  local out=""
  local i=0
  while [[ "${i}" -lt "${depth}" ]]; do
    out="${out}  "
    ((i++)) || true
  done
  printf '%s' "${out}"
}

p_log() {
  echo "$(indent)[planning] $1"
}

p_err() {
  echo "$(indent)[planning] ERROR: $1" >&2
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

has_structured_steps() {
  local file="$1"
  command -v jq >/dev/null 2>&1 || return 1
  jq -e '.steps | type == "array"' "${file}" >/dev/null 2>&1
}

# =============================================================================
# Check Existing Plan
# =============================================================================

check_existing_plan() {
  if [[ "${PLAN_FORCE_REGENERATE}" == "1" ]]; then
    p_log "Force regenerate enabled; ignoring existing plan"
    return 1
  fi

  if [[ -f "${PLAN_FILE}" ]]; then
    if has_structured_steps "${PLAN_FILE}"; then
      p_log "Plan exists: ${PLAN_FILE}"
      return 0
    fi
    p_log "Plan file exists but is not structured (.steps missing), regenerating: ${PLAN_FILE}"
    return 1
  fi
  return 1
}

# =============================================================================
# Build Planner Prompt
# =============================================================================

build_planner_prompt() {
  local prompt_file="$1"

  cat > "${prompt_file}" <<'PROMPT'
You are a planning system.

Break the project goal into small deterministic steps.

Rules:
- Each step must be testable
- Steps must be sequential
- Do NOT implement code
- Output ONLY valid JSON, no markdown fences

Schema:
{
  "goal": "the overall objective",
  "max_steps": 0,
  "steps": [
    {
      "id": "step-1",
      "description": "what to do",
      "acceptance": "how to verify it's done",
      "status": "pending",
      "commit": null
    }
  ]
}

PROMPT

  # Add context
  cat >> "${prompt_file}" <<EOF

Project workspace: ${RALPH_WORKSPACE}
User objective: $(cat "${RALPH_PROMPT_FILE}" 2>/dev/null || echo "No prompt specified")
EOF

  if [[ -n "${PLAN_CONTEXT_FILE}" && -f "${PLAN_CONTEXT_FILE}" ]]; then
    cat >> "${prompt_file}" <<EOF

Additional plan context file: ${PLAN_CONTEXT_FILE}
Use this as context only, and output a fresh structured JSON plan.

Context content:
EOF
    sed -n '1,240p' "${PLAN_CONTEXT_FILE}" >> "${prompt_file}" || true
  fi

  if [[ -n "${PLAN_FEEDBACK}" ]]; then
    cat >> "${prompt_file}" <<EOF

Human feedback on missing plan details:
${PLAN_FEEDBACK}
EOF
  fi

  cat >> "${prompt_file}" <<EOF

Generate the plan now:
EOF
}

# =============================================================================
# Create Stub Plan (dry-run)
# =============================================================================

create_stub_plan() {
  mkdir -p "$(dirname "${PLAN_FILE}")"

  cat > "${PLAN_FILE}" <<'STUB'
{
  "goal": "dry-run stub plan with deterministic phases",
  "max_steps": 4,
  "steps": [
    {
      "id": "step-1-scan",
      "description": "Inspect repository structure and identify likely impact area",
      "acceptance": "A short impact-focused analysis is present in the response",
      "status": "pending",
      "commit": null
    },
    {
      "id": "step-2-change",
      "description": "Apply one minimal code or config change tied to the goal",
      "acceptance": "At least one file edit is described with expected impact",
      "status": "pending",
      "commit": null
    },
    {
      "id": "step-3-validate",
      "description": "Run or simulate validation checks",
      "acceptance": "Validation outcome is explicitly reported (pass/fail with reason)",
      "status": "pending",
      "commit": null
    },
    {
      "id": "step-4-report",
      "description": "Summarize changes, tradeoffs, and next recommendation",
      "acceptance": "Summary includes outcomes, risks, and next step proposal",
      "status": "pending",
      "commit": null
    }
  ]
}
STUB

  p_log "Created stub plan (dry-run) with 4 steps"
}

enrich_plan_metadata() {
  if ! command -v jq >/dev/null 2>&1; then
    p_log "jq not found; skipping timestamp enrichment"
    return 0
  fi

  local now tmp
  now="$(now_iso)"
  tmp="${PLAN_FILE}.tmp"

  jq --arg now "${now}" '
    .generated_at = (.generated_at // $now)
    | .updated_at = $now
    | .approved_by = (.approved_by // null)
    | .approved_at = (.approved_at // null)
    | .steps = [
        .steps[] |
        .created_at = (.created_at // $now) |
        .updated_at = $now |
        .completed_at = (.completed_at // null)
      ]
  ' "${PLAN_FILE}" > "${tmp}" && mv "${tmp}" "${PLAN_FILE}"
}

# =============================================================================
# Run AI Engine
# =============================================================================

run_ai() {
  local prompt_file="$1"
  local response_file="$2"

  # Find ai.sh hook
  local ai_hook="${HOOKS_DIR}/ai.sh"

  if [[ ! -x "${ai_hook}" ]]; then
    # Try global
    ai_hook="${HOME}/.ralph/hooks/ai.sh"
  fi

  if [[ ! -x "${ai_hook}" ]]; then
    p_err "ai.sh hook not found"
    return 1
  fi

  # Export environment for ai.sh
  export RALPH_PROMPT_FILE="${prompt_file}"
  export RALPH_RESPONSE_FILE="${response_file}"
  # RALPH_ENGINE, RALPH_MODEL inherited from parent

  p_log "Using AI engine: ${RALPH_ENGINE:-auto}"

  RALPH_HOOK_DEPTH="$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))" "${ai_hook}"
}

# =============================================================================
# Validate Plan
# =============================================================================

validate_plan() {
  if ! jq -e '.steps and (.steps | length > 0)' "${PLAN_FILE}" >/dev/null 2>&1; then
    p_err "Invalid plan format"
    rm -f "${PLAN_FILE}"
    return 1
  fi

  local step_count
  step_count=$(jq '.steps | length' "${PLAN_FILE}")
  p_log "Plan generated: ${step_count} steps"
}

# =============================================================================
# Main
# =============================================================================

main() {
  p_log "Checking for plan..."

  # If plan exists, nothing to do
  if check_existing_plan; then
    exit 0
  fi

  p_log "No plan found, generating via AI..."
  mkdir -p "$(dirname "${PLAN_FILE}")"

  # Dry-run mode
  if [[ "${RALPH_DRY_RUN:-0}" == "1" ]]; then
    create_stub_plan
    enrich_plan_metadata
    exit 0
  fi

  # Create temp files
  local prompt_file response_file
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  trap "rm -f '${prompt_file}' '${response_file}'" EXIT

  # Build prompt
  build_planner_prompt "${prompt_file}"

  # Run AI
  if ! run_ai "${prompt_file}" "${response_file}"; then
    p_err "AI generation failed"
    exit 1
  fi

  # Move response to plan file
  mv "${response_file}" "${PLAN_FILE}"

  # Normalize metadata/timestamps
  enrich_plan_metadata

  # Validate
  if ! validate_plan; then
    exit 1
  fi

  exit 0
}

main "$@"
