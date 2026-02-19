#!/usr/bin/env bash
# Plan selection helpers for Ralph orchestrator.
set -euo pipefail

# Lists readable JSON plans under workspace plan directory.
list_plan_candidates() {
  local plans_dir="${ROOT}/.ralph/plans"
  [[ -d "${plans_dir}" ]] || return 0
  find "${plans_dir}" -maxdepth 1 -type f -name '*.json' -readable | sort
}

# Prompts user to select one plan with a paged UI list.
select_plan_interactive() {
  local -a candidates=("$@")
  local i choice
  local -a labels=()
  for ((i=0; i<${#candidates[@]}; i++)); do
    labels+=("$(to_rel_path "${candidates[i]}")")
  done
  labels+=("Create new plan from prompt...")

  if command -v ui_prompt_menu_window >/dev/null 2>&1 && [[ -t 0 ]]; then
    choice="$(ui_prompt_menu_window 4 "Select plan file:" "${labels[@]}")"
    if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -eq $(( ${#candidates[@]} + 1 )) ]]; then
      printf '%s\n' "__CREATE_NEW_PLAN__"
      return 0
    fi
    if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le ${#candidates[@]} ]]; then
      printf '%s\n' "${candidates[$((choice - 1))]}"
      return 0
    fi
  fi

  printf '%s\n' "${candidates[0]}"
}

# Creates a minimal new JSON plan from interactive user input.
create_new_plan_from_prompt_interactive() {
  [[ -t 0 ]] || return 1

  local default_name plan_name goal_prompt plan_path now max_steps
  default_name="plan-$(date +%Y%m%d_%H%M%S).json"

  read -r -p "New plan file name (.ralph/plans, default: ${default_name}): " plan_name
  [[ -z "${plan_name}" ]] && plan_name="${default_name}"
  plan_name="$(basename "${plan_name}")"
  [[ "${plan_name}" == *.json ]] || plan_name="${plan_name}.json"
  plan_path="${ROOT}/.ralph/plans/${plan_name}"
  mkdir -p "$(dirname "${plan_path}")"

  if [[ -f "${plan_path}" ]]; then
    if ! confirm_plan_overwrite "${plan_path}" "${plan_name}"; then
      return 1
    fi
  fi

  read -r -p "Plan goal/prompt (default: ${GOAL}): " goal_prompt
  [[ -z "${goal_prompt}" ]] && goal_prompt="${GOAL}"
  read -r -p "Plan max steps per session (0=unlimited, default: 0): " max_steps
  [[ -z "${max_steps}" ]] && max_steps="0"
  if ! [[ "${max_steps}" =~ ^[0-9]+$ ]]; then
    echo "Invalid max steps value. Must be a non-negative integer." >&2
    return 1
  fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if command -v jq >/dev/null 2>&1; then
    jq -n --arg goal "${goal_prompt}" --arg now "${now}" --argjson max_steps "${max_steps}" '
      {
        goal: $goal,
        max_steps: $max_steps,
        steps: [
          {
            id: "step-1-scan",
            description: "Scan current state and identify most important improvement area",
            acceptance: "One concrete improvement target is identified",
            status: "pending",
            commit: null,
            created_at: $now,
            updated_at: $now,
            completed_at: null
          },
          {
            id: "step-2-change",
            description: "Apply one focused change",
            acceptance: "At least one file is changed with clear rationale",
            status: "pending",
            commit: null,
            created_at: $now,
            updated_at: $now,
            completed_at: null
          },
          {
            id: "step-3-validate",
            description: "Validate outcome with tests or checks",
            acceptance: "Validation result is explicitly reported",
            status: "pending",
            commit: null,
            created_at: $now,
            updated_at: $now,
            completed_at: null
          },
          {
            id: "step-4-report",
            description: "Summarize changes and next step hypothesis",
            acceptance: "Summary includes what changed and proposed next step",
            status: "pending",
            commit: null,
            created_at: $now,
            updated_at: $now,
            completed_at: null
          }
        ],
        generated_at: $now,
        updated_at: $now,
        approved_by: null,
        approved_at: null,
        approval_source: null
      }' > "${plan_path}"
  else
    cat > "${plan_path}" <<JSON
{
  "goal": "${goal_prompt}",
  "steps": [],
  "generated_at": "${now}",
  "updated_at": "${now}",
  "approved_by": null,
  "approved_at": null,
  "approval_source": null
}
JSON
  fi

  printf '%s\n' "${plan_path}"
}

# Confirms overwrite via hooks.json event `before-session.plan-overwrite-confirm`.
# Returns 0 when overwrite is approved, 1 otherwise.
confirm_plan_overwrite() {
  local plan_path="$1"
  local plan_name="$2"

  if ! command -v run_json_hook_commands >/dev/null 2>&1; then
    echo "Plan overwrite confirmation requires hooks parser (run_json_hook_commands missing)." >&2
    return 1
  fi
  if [[ -z "${HOOKS_JSON_PATH:-}" || ! -f "${HOOKS_JSON_PATH}" ]]; then
    echo "Plan overwrite confirmation requires hooks.json (HOOKS_JSON_PATH missing)." >&2
    return 1
  fi

  if ! jq -e '
    .["before-session"]?["plan-overwrite-confirm"] as $node
    | if $node == null then false
      elif ($node|type) == "array" then ($node|length) > 0
      elif ($node|type) == "object" then (($node.commands // [])|length) > 0
      else false end
  ' "${HOOKS_JSON_PATH}" >/dev/null 2>&1; then
    echo "hooks.json must define before-session.plan-overwrite-confirm." >&2
    return 1
  fi

  export RALPH_PLAN_SELECT_MODE="overwrite"
  export RALPH_PLAN_CANDIDATE="${plan_path}"
  export RALPH_PLAN_CANDIDATE_NAME="${plan_name}"
  run_json_hook_commands "before-session" "plan-overwrite-confirm" "" ""
}
