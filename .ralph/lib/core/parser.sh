#!/usr/bin/env bash
# hooks.json command runner with optional human-in-the-loop gates.
set -euo pipefail

# Loads shared JSON/JSONC helpers.
HOOKS_PARSER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_LIB_PATH="${HOOKS_PARSER_DIR}/../json.sh"
if [[ -f "${JSON_LIB_PATH}" ]]; then
  # shellcheck disable=SC1090
  source "${JSON_LIB_PATH}"
else
  echo "Missing JSON helper library: ${JSON_LIB_PATH}" >&2
  return 1 2>/dev/null || exit 1
fi

# Color defaults for early-stage execution (before setup_colors).
: "${C_RESET:=}"
: "${C_DIM:=}"
: "${C_YELLOW:=}"
: "${C_MAGENTA:=}"
# Runtime defaults when sourced outside full CLI bootstrap.
: "${DRY_RUN:=0}"

# Resolves language file path by precedence: project -> global -> bundled.
json_hook_lang_file_path() {
  local lang_code="${1:-en}"

  if [[ -f "${ROOT}/.ralph/lang/${lang_code}.json" ]]; then
    printf '%s\n' "${ROOT}/.ralph/lang/${lang_code}.json"
    return 0
  fi
  if [[ -n "${RALPH_PROJECT_DIR:-}" ]] && [[ -f "${RALPH_PROJECT_DIR}/lang/${lang_code}.json" ]]; then
    printf '%s\n' "${RALPH_PROJECT_DIR}/lang/${lang_code}.json"
    return 0
  fi
  if [[ -n "${RALPH_GLOBAL_DIR:-}" ]] && [[ -f "${RALPH_GLOBAL_DIR}/lang/${lang_code}.json" ]]; then
    printf '%s\n' "${RALPH_GLOBAL_DIR}/lang/${lang_code}.json"
    return 0
  fi
  if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/.ralph/lang/${lang_code}.json" ]]; then
    printf '%s\n' "${SCRIPT_DIR}/.ralph/lang/${lang_code}.json"
    return 0
  fi
  return 1
}

# Returns localized text when key exists; otherwise returns fallback text.
json_hook_localize() {
  local key="${1:-}"
  local fallback="${2:-}"
  local lang_code="${RALPH_LANG:-en}"
  local selected_file fallback_file value=""
  local lookup_key="${key}"
  local fallback_text="${fallback}"

  # Support grouped key syntax: {my.grouped.label}
  if [[ "${lookup_key}" =~ ^\{(.+)\}$ ]]; then
    lookup_key="${BASH_REMATCH[1]}"
    [[ -z "${fallback_text}" || "${fallback_text}" == "${key}" ]] && fallback_text="${lookup_key}"
  fi

  [[ -n "${lookup_key}" ]] || { printf '%s\n' "${fallback_text}"; return 0; }
  command -v jq >/dev/null 2>&1 || { printf '%s\n' "${fallback_text}"; return 0; }

  selected_file="$(json_hook_lang_file_path "${lang_code}" || true)"
  fallback_file="$(json_hook_lang_file_path "en" || true)"

  if [[ -n "${selected_file}" ]]; then
    value="$(jq -r --arg key "${lookup_key}" '.[$key] // empty' "${selected_file}" 2>/dev/null || true)"
  fi
  if [[ -z "${value}" && -n "${fallback_file}" ]]; then
    value="$(jq -r --arg key "${lookup_key}" '.[$key] // empty' "${fallback_file}" 2>/dev/null || true)"
  fi

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${fallback_text}"
  fi
}

# Prompts the user to approve one hooks.json command.
json_hook_human_approve() {
  local event="$1"
  local command_text="$2"
  local prompt_text="$3"
  local default_yes="${4:-0}"

  [[ -t 0 ]] || return 1

  local prompt
  if [[ -n "${prompt_text}" ]]; then
    prompt="${prompt_text}"
  else
    prompt="Run hooks.json command for ${event}? ${command_text}"
  fi

  local suffix="[y/N]"
  [[ "${default_yes}" == "1" ]] && suffix="[Y/n]"
  local answer
  read -r -p "${prompt} ${suffix}: " answer

  if [[ "${default_yes}" == "1" ]]; then
    case "${answer}" in
      n|N|no|NO) return 1 ;;
      *) return 0 ;;
    esac
  fi

  case "${answer}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Prompts for one numeric option (single-select).
json_hook_prompt_single() {
  local prompt="$1"
  shift
  local -a labels=("$@")
  local choice=""

  [[ "${#labels[@]}" -gt 0 ]] || return 1
  [[ -t 0 ]] || return 1

  if command -v ui_prompt_menu_arrow >/dev/null 2>&1; then
    choice="$(ui_prompt_menu_arrow "${prompt}" "${labels[@]}")"
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${choice}"
    return 0
  fi

  echo "${prompt}"
  local i
  for ((i=0; i<${#labels[@]}; i++)); do
    echo "  $((i + 1))) ${labels[i]}"
  done
  read -r -p "Choice [1-${#labels[@]}]: " choice
  [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "${choice}"
}

# Prompts for comma-separated numeric options (multi-select).
json_hook_prompt_multi() {
  local prompt="$1"
  shift
  local -a labels=("$@")
  local raw=""

  [[ "${#labels[@]}" -gt 0 ]] || return 1
  [[ -t 0 ]] || return 1

  echo "${prompt}"
  local i
  for ((i=0; i<${#labels[@]}; i++)); do
    echo "  $((i + 1))) ${labels[i]}"
  done
  read -r -p "Choices (comma-separated, e.g. 1,3): " raw
  printf '%s\n' "${raw}"
}

# Executes one concrete command entry from hooks.json.
run_json_hook_command_entry() {
  local event="$1"
  local cmd="$2"
  local when_expr="$3"
  local human_gate="$4"
  local prompt_text="$5"
  local default_yes="$6"
  local allow_failure="$7"
  local cwd_rel="$8"
  local run_in_dry_run="$9"
  local stop_on_error="${10}"
  local step="${11:-}"
  local step_exit_code="${12:-}"
  local tasks_file="${13:-}"

  local cwd_abs rc

  if [[ -z "${cmd}" ]]; then
    echo "${C_YELLOW}[hooks.json]${C_RESET} ${event}: empty command; skipping"
    return 0
  fi

  # Expand task references in run expression:
  # - Full reference: "task:my.task" or "{tasks.my.task}"
  # - Inline chaining: "task:a && task:b && ./script.sh"
  # - Mixed: "{tasks.cleanup} && task:deploy.staging"
  if [[ "${cmd}" == *task:* || "${cmd}" == *{tasks.* || "${cmd}" == *{conditions.* ]]; then
    local expanded_cmd
    expanded_cmd="$(json_hook_expand_run_placeholders "${cmd}" "${tasks_file}")"
    if [[ -z "${expanded_cmd}" ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} ${event}: run task expansion failed: ${cmd}"
      return 0
    fi
    cmd="${expanded_cmd}"
  fi

  if ! json_hook_when_matches "${when_expr}" "${tasks_file}" "${cwd_rel}"; then
    echo "${C_DIM}[hooks.json]${C_RESET} ${event}: condition not met, skipping: ${cmd}"
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 && "${run_in_dry_run}" != "1" ]]; then
    echo "${C_DIM}[hooks.json]${C_RESET} ${event}: skipped in dry-run: ${cmd}"
    return 0
  fi

  if [[ "${human_gate}" == "1" ]]; then
    prompt_text="$(json_hook_localize "${prompt_text}" "${prompt_text}")"
    if [[ "${RALPH_HUMAN_GUARD_ASSUME_YES:-0}" == "1" ]]; then
      echo "${C_DIM}[hooks.json]${C_RESET} ${event}: auto-approved (assume-yes): ${cmd}"
      state_record_choice "hooks.json" "${event}" "approved" "assume-yes: ${cmd}" || true
    else
      if ! json_hook_human_approve "${event}" "${cmd}" "${prompt_text}" "${default_yes}"; then
        echo "${C_YELLOW}[hooks.json]${C_RESET} ${event}: rejected by human: ${cmd}"
        state_record_choice "hooks.json" "${event}" "rejected" "${cmd}" || true
        if [[ "${allow_failure}" != "1" && "${stop_on_error}" == "true" ]]; then
          return 1
        fi
        return 0
      fi
      state_record_choice "hooks.json" "${event}" "approved" "${cmd}" || true
    fi
  fi

  cwd_abs="${ROOT}"
  if [[ -n "${cwd_rel}" ]]; then
    if [[ "${cwd_rel}" == /* ]]; then
      cwd_abs="${cwd_rel}"
    else
      cwd_abs="${ROOT}/${cwd_rel}"
    fi
  fi
  if [[ ! -d "${cwd_abs}" ]]; then
    echo "${C_YELLOW}[hooks.json]${C_RESET} ${event}: cwd not found, skipping: ${cwd_abs}"
    if [[ "${allow_failure}" != "1" && "${stop_on_error}" == "true" ]]; then
      return 1
    fi
    return 0
  fi

  echo "${C_MAGENTA}[hooks.json]${C_RESET} ${event}: ${cmd}"
  set +e
  (
    cd "${cwd_abs}"
    export RALPH_STEP="${step}"
    export RALPH_STEP_EXIT_CODE="${step_exit_code}"
    bash -lc "${cmd}"
  )
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    echo "${C_YELLOW}[hooks.json]${C_RESET} ${event}: command failed (${rc})"
    if [[ "${allow_failure}" != "1" && "${stop_on_error}" == "true" ]]; then
      return "${rc}"
    fi
  fi
  return 0
}

# Resolves runnable condition command from a task reference.
json_hook_when_task_command() {
  local task_ref="$1"
  local tasks_file="$2"
  local payload=""
  local normalized_ref=""

  normalized_ref="$(json_hook_normalize_task_ref "${task_ref}")"
  [[ -n "${normalized_ref}" ]] || return 1
  payload="$(expand_json_hook_task "{\"task\":\"${normalized_ref}\"}" "${tasks_file}")"
  local cmd=""
  cmd="$(printf '%s' "${payload}" | jq -r '.run // .cmd // empty' 2>/dev/null || true)"
  if [[ -n "${cmd}" && -n "${tasks_file}" ]]; then
    local expanded
    expanded="$(json_hook_expand_run_placeholders "${cmd}" "${tasks_file}" || true)"
    [[ -n "${expanded}" ]] && cmd="${expanded}"
  fi
  printf '%s' "${cmd}"
}

# Expands {task.ref} placeholders in when-expression to runnable shell clauses.
# Example:
#   "{conditions.a} && {conditions.b}" -> "( <cmd-a> ) && ( <cmd-b> )"
json_hook_expand_when_placeholders() {
  local expr="$1"
  local tasks_file="$2"
  local out="${expr}"
  local guard=0

  while [[ "${out}" =~ (^|[^$])(\{([^{}]+)\}) ]]; do
    ((guard++)) || true
    if [[ "${guard}" -gt 64 ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} when placeholder expansion limit reached" >&2
      return 1
    fi

    local prefix="${BASH_REMATCH[1]}"
    local token="${BASH_REMATCH[2]}"
    local ref="${BASH_REMATCH[3]}"
    local cmd
    cmd="$(json_hook_when_task_command "${ref}" "${tasks_file}")"
    if [[ -z "${cmd}" ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} when task not found: ${ref}" >&2
      return 1
    fi

    out="${out/${prefix}${token}/${prefix}( ${cmd} )}"
  done

  printf '%s\n' "${out}"
}

# Expands task references in run-expression to actual shell commands.
# Supports:
#   - {tasks.my.task} placeholder syntax
#   - task:my.task prefix syntax (standalone or inline)
# Example:
#   "task:utils.cleanup && ./deploy.sh" -> "( rm -rf tmp ) && ./deploy.sh"
#   "{tasks.a} && {tasks.b}" -> "( cmd-a ) && ( cmd-b )"
json_hook_expand_run_placeholders() {
  local expr="$1"
  local tasks_file="$2"
  local out="${expr}"
  local guard=0

  # Expand {tasks.ref} placeholders
  while [[ "${out}" =~ (^|[^$])(\{([^{}]+)\}) ]]; do
    ((guard++)) || true
    if [[ "${guard}" -gt 64 ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} run placeholder expansion limit reached" >&2
      return 1
    fi

    local prefix="${BASH_REMATCH[1]}"
    local token="${BASH_REMATCH[2]}"
    local ref="${BASH_REMATCH[3]}"
    local cmd
    cmd="$(json_hook_when_task_command "${ref}" "${tasks_file}")"
    if [[ -z "${cmd}" ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} run task not found: ${ref}" >&2
      return 1
    fi

    out="${out/${prefix}${token}/${prefix}( ${cmd} )}"
  done

  # Expand task:ref patterns (word boundary aware)
  # Matches: task:name.path at start, after space, or after shell operators
  guard=0
  while [[ "${out}" =~ (^|[[:space:]]|[;\&\|])task:([a-zA-Z0-9._-]+) ]]; do
    ((guard++)) || true
    if [[ "${guard}" -gt 64 ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} run task: expansion limit reached" >&2
      return 1
    fi

    local prefix="${BASH_REMATCH[1]}"
    local ref="${BASH_REMATCH[2]}"
    local pattern="${prefix}task:${ref}"
    local cmd
    cmd="$(json_hook_when_task_command "${ref}" "${tasks_file}")"
    if [[ -z "${cmd}" ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} run task not found: ${ref}" >&2
      return 1
    fi

    out="${out/${pattern}/${prefix}( ${cmd} )}"
  done

  printf '%s\n' "${out}"
}

# Evaluates one hooks.json when-clause.
# Supported formats:
# - "<shell expression>"
# - "task:<task-name>"
# - { "task": "<task-name>" }
# - { "run": "<shell expression>" }
json_hook_when_matches() {
  local when_expr="$1"
  local tasks_file="${2:-}"
  local cwd_rel="${3:-}"
  local cwd_abs="${ROOT}"
  local raw="${when_expr}"
  local cmd=""
  local raw_type=""

  [[ -z "${raw}" ]] && return 0

  # Accept both raw shell strings and JSON-encoded values.
  raw_type="$(printf '%s' "${raw}" | jq -r 'type' 2>/dev/null || true)"
  case "${raw_type}" in
    null)
      return 0
      ;;
    string)
      raw="$(printf '%s' "${raw}" | jq -r '.' 2>/dev/null || printf '%s' "${raw}")"
      ;;
    object)
      raw="$(printf '%s' "${raw}" | jq -c '.' 2>/dev/null || printf '%s' "${raw}")"
      ;;
  esac

  # Empty JSON strings (e.g. when: "") mean "no condition".
  [[ -z "${raw}" ]] && return 0

  if [[ -n "${cwd_rel}" ]]; then
    if [[ "${cwd_rel}" == /* ]]; then
      cwd_abs="${cwd_rel}"
    else
      cwd_abs="${ROOT}/${cwd_rel}"
    fi
  fi
  [[ -d "${cwd_abs}" ]] || return 1

  if [[ "${raw}" == \{* ]] && printf '%s' "${raw}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    local task_ref
    task_ref="$(printf '%s' "${raw}" | jq -r '.task // empty' 2>/dev/null || true)"
    if [[ -n "${task_ref}" ]]; then
      cmd="$(json_hook_when_task_command "${task_ref}" "${tasks_file}")"
    else
      cmd="$(printf '%s' "${raw}" | jq -r '.run // .cmd // empty' 2>/dev/null || true)"
    fi
  elif [[ "${raw}" == task:* ]]; then
    cmd="$(json_hook_when_task_command "${raw#task:}" "${tasks_file}")"
  else
    cmd="$(json_hook_expand_when_placeholders "${raw}" "${tasks_file}" || true)"
    [[ -z "${cmd}" ]] && cmd="${raw}"
  fi

  [[ -n "${cmd}" ]] || return 1

  set +e
  (
    cd "${cwd_abs}"
    bash -lc "${cmd}" >/dev/null 2>&1
  )
  local rc=$?
  set -e
  [[ "${rc}" -eq 0 ]]
}

# Executes one select entry from hooks.json.
run_json_hook_select_entry() {
  local event="$1"
  local payload="$2"
  local stop_on_error="$3"
  local step="${4:-}"
  local step_exit_code="${5:-}"
  local tasks_file="${6:-}"

  local select_json mode prompt
  local -a option_payloads=()
  local -a option_labels=()
  local p line

  select_json="$(printf '%s' "${payload}" | jq -c '.select // empty')"
  [[ -n "${select_json}" ]] || return 0

  mode="$(printf '%s' "${select_json}" | jq -r '.mode // "single"')"
  prompt="$(printf '%s' "${select_json}" | jq -r '.prompt // "Select actions:"')"
  prompt="$(json_hook_localize "${prompt}" "${prompt}")"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    option_payloads+=("${line}")
    local raw_label fallback_label
    raw_label="$(printf '%s' "${line}" | base64 -d 2>/dev/null | jq -r '.label // empty')"
    fallback_label="$(printf '%s' "${line}" | base64 -d 2>/dev/null | jq -r '.code // .run // "option"')"
    if [[ -n "${raw_label}" ]]; then
      option_labels+=("$(json_hook_localize "${raw_label}" "${raw_label}")")
    else
      option_labels+=("${fallback_label}")
    fi
  done < <(
    printf '%s' "${select_json}" | jq -r '
      (.options // [])
      | .[]
      | {
          code: (.code // ""),
          label: (.label // .code // .run // "option"),
          run: (.run // .cmd // ""),
          when: (.when // ""),
          human_gate: (
            if (.human_gate|type) == "boolean" then .human_gate
            elif (.human_gate|type) == "object" then true
            else false end
          ),
          prompt: (
            .prompt // (
              if (.human_gate|type) == "object"
              then (.human_gate.prompt // "")
              else ""
              end
            )
          ),
          default_yes: (
            if (.human_gate|type) == "object" then
              if (.human_gate.default_yes // null) != null then .human_gate.default_yes
              elif ((.human_gate.default // "") | ascii_downcase) == "yes" then true
              else false end
            else false end
          ),
          allow_failure: (.allow_failure // false),
          cwd: (.cwd // ""),
          run_in_dry_run: (.run_in_dry_run // false)
        }
      | select(.run != "")
      | @base64
    ' 2>/dev/null || true
  )

  [[ "${#option_payloads[@]}" -gt 0 ]] || return 0

  if [[ "${mode}" == "multi" ]]; then
    local raw choices idx
    raw="$(json_hook_prompt_multi "${prompt}" "${option_labels[@]}" || true)"
    [[ -z "${raw}" ]] && return 0
    IFS=',' read -r -a choices <<< "${raw}"
    for idx in "${choices[@]}"; do
      idx="$(printf '%s' "${idx}" | tr -d '[:space:]')"
      [[ "${idx}" =~ ^[0-9]+$ ]] || continue
      if [[ "${idx}" -lt 1 || "${idx}" -gt "${#option_payloads[@]}" ]]; then
        continue
      fi
      p="$(printf '%s' "${option_payloads[$((idx - 1))]}" | base64 -d 2>/dev/null || true)"
      [[ -n "${p}" ]] || continue
      state_record_choice "hooks.json" "${event}" "select" "$(printf '%s' "${p}" | jq -r '.code // .label // "option"')" || true
      run_json_hook_command_entry \
        "${event}" \
        "$(printf '%s' "${p}" | jq -r '.run')" \
        "$(printf '%s' "${p}" | jq -c '.when // empty')" \
        "$(printf '%s' "${p}" | jq -r 'if .human_gate then "1" else "0" end')" \
        "$(printf '%s' "${p}" | jq -r '.prompt // empty')" \
        "$(printf '%s' "${p}" | jq -r 'if .default_yes then "1" else "0" end')" \
        "$(printf '%s' "${p}" | jq -r 'if .allow_failure then "1" else "0" end')" \
        "$(printf '%s' "${p}" | jq -r '.cwd // empty')" \
        "$(printf '%s' "${p}" | jq -r 'if .run_in_dry_run then "1" else "0" end')" \
        "${stop_on_error}" \
        "${step}" \
        "${step_exit_code}" \
        "${tasks_file}" || return $?
    done
    return 0
  fi

  local selected
  if [[ "${RALPH_HUMAN_GUARD_ASSUME_YES:-0}" == "1" ]]; then
    selected="1"
  else
    selected="$(json_hook_prompt_single "${prompt}" "${option_labels[@]}" || true)"
  fi
  [[ "${selected}" =~ ^[0-9]+$ ]] || return 0
  if [[ "${selected}" -lt 1 || "${selected}" -gt "${#option_payloads[@]}" ]]; then
    return 0
  fi
  p="$(printf '%s' "${option_payloads[$((selected - 1))]}" | base64 -d 2>/dev/null || true)"
  [[ -n "${p}" ]] || return 0
  state_record_choice "hooks.json" "${event}" "select" "$(printf '%s' "${p}" | jq -r '.code // .label // "option"')" || true
  run_json_hook_command_entry \
    "${event}" \
    "$(printf '%s' "${p}" | jq -r '.run')" \
    "$(printf '%s' "${p}" | jq -c '.when // empty')" \
    "$(printf '%s' "${p}" | jq -r 'if .human_gate then "1" else "0" end')" \
    "$(printf '%s' "${p}" | jq -r '.prompt // empty')" \
    "$(printf '%s' "${p}" | jq -r 'if .default_yes then "1" else "0" end')" \
    "$(printf '%s' "${p}" | jq -r 'if .allow_failure then "1" else "0" end')" \
    "$(printf '%s' "${p}" | jq -r '.cwd // empty')" \
    "$(printf '%s' "${p}" | jq -r 'if .run_in_dry_run then "1" else "0" end')" \
    "${stop_on_error}" \
    "${step}" \
    "${step_exit_code}" \
    "${tasks_file}" || return $?
}

# Resolves include path relative to parent hooks.json file.
hooks_json_resolve_include_path() {
  local parent_file="$1"
  local include_path="$2"

  include_path="${include_path/#\~/$HOME}"
  if [[ "${include_path}" == /* ]]; then
    printf '%s\n' "${include_path}"
    return 0
  fi

  local parent_dir
  parent_dir="$(cd "$(dirname "${parent_file}")" && pwd)"
  printf '%s\n' "${parent_dir}/${include_path}"
}

# Collects hooks.json files in include order (children first, parent last).
# Supports root keys: "include" or "includes" (string or array).
hooks_json_collect_files() {
  local hooks_file="$1"

  if [[ ! -f "${hooks_file}" ]]; then
    echo "hooks.json include not found: ${hooks_file}" >&2
    return 1
  fi

  # shellcheck disable=SC2154
  if [[ -n "${_RALPH_HOOKS_JSON_VISITING[${hooks_file}]:-}" ]]; then
    echo "hooks.json include cycle detected at: ${hooks_file}" >&2
    return 1
  fi
  # shellcheck disable=SC2154
  if [[ -n "${_RALPH_HOOKS_JSON_DONE[${hooks_file}]:-}" ]]; then
    return 0
  fi

  _RALPH_HOOKS_JSON_VISITING["${hooks_file}"]=1

  local include_rel include_abs
  local normalized
  normalized="$(json_like_to_temp_file "${hooks_file}")"

  while IFS= read -r include_rel; do
    [[ -n "${include_rel}" ]] || continue
    include_abs="$(hooks_json_resolve_include_path "${hooks_file}" "${include_rel}")"
    hooks_json_collect_files "${include_abs}" || return 1
  done < <(
    jq -r '
      (.include // .includes // empty)
      | if type == "array" then .[] elif type == "string" then . else empty end
    ' "${normalized}" 2>/dev/null || true
  )
  rm -f "${normalized}"

  unset '_RALPH_HOOKS_JSON_VISITING["'"${hooks_file}"'"]'
  _RALPH_HOOKS_JSON_DONE["${hooks_file}"]=1
  printf '%s\n' "${hooks_file}"
}

# Builds a merged hooks JSON file including all include dependencies.
# Arrays are concatenated; object keys are deep-merged; parent overrides scalars.
build_merged_hooks_json() {
  local root_hooks_file="$1"
  local out_file="$2"
  local -a files=()
  local -a normalized_files=()
  local f

  declare -gA _RALPH_HOOKS_JSON_VISITING=()
  declare -gA _RALPH_HOOKS_JSON_DONE=()

  while IFS= read -r f; do
    [[ -n "${f}" ]] && files+=("${f}")
  done < <(hooks_json_collect_files "${root_hooks_file}")

  [[ "${#files[@]}" -gt 0 ]] || return 1

  for f in "${files[@]}"; do
    local norm
    norm="$(json_like_to_temp_file "${f}")" || return 1
    normalized_files+=("${norm}")
  done

  jq -s '
    def deepmerge($a; $b):
      if ($a|type) == "object" and ($b|type) == "object" then
        reduce (($a + $b) | keys_unsorted[]) as $k
          ({}; .[$k] = deepmerge($a[$k]; $b[$k]))
      elif ($a|type) == "array" and ($b|type) == "array" then
        $a + $b
      elif $b == null then $a
      else $b
      end;
    reduce (map(del(.include, .includes))[]) as $item ({}; deepmerge(.; $item))
  ' "${normalized_files[@]}" > "${out_file}"
  rm -f "${normalized_files[@]}"
}

# Collects tasks.json files in include order (children first, parent last).
tasks_json_collect_files() {
  local tasks_file="$1"

  if [[ ! -f "${tasks_file}" ]]; then
    echo "tasks.json include not found: ${tasks_file}" >&2
    return 1
  fi

  # shellcheck disable=SC2154
  if [[ -n "${_RALPH_TASKS_JSON_VISITING[${tasks_file}]:-}" ]]; then
    echo "tasks.json include cycle detected at: ${tasks_file}" >&2
    return 1
  fi
  # shellcheck disable=SC2154
  if [[ -n "${_RALPH_TASKS_JSON_DONE[${tasks_file}]:-}" ]]; then
    return 0
  fi

  _RALPH_TASKS_JSON_VISITING["${tasks_file}"]=1

  local include_rel include_abs
  local normalized
  normalized="$(json_like_to_temp_file "${tasks_file}")"

  while IFS= read -r include_rel; do
    [[ -n "${include_rel}" ]] || continue
    include_abs="$(hooks_json_resolve_include_path "${tasks_file}" "${include_rel}")"
    tasks_json_collect_files "${include_abs}" || return 1
  done < <(
    jq -r '
      (.include // .includes // empty)
      | if type == "array" then .[] elif type == "string" then . else empty end
    ' "${normalized}" 2>/dev/null || true
  )
  rm -f "${normalized}"

  unset '_RALPH_TASKS_JSON_VISITING["'"${tasks_file}"'"]'
  _RALPH_TASKS_JSON_DONE["${tasks_file}"]=1
  printf '%s\n' "${tasks_file}"
}

# Builds merged tasks.json including include dependencies.
build_merged_tasks_json() {
  local root_tasks_file="$1"
  local out_file="$2"
  local -a files=()
  local -a normalized_files=()
  local f

  [[ -n "${root_tasks_file}" ]] || return 1
  [[ -f "${root_tasks_file}" ]] || return 1

  declare -gA _RALPH_TASKS_JSON_VISITING=()
  declare -gA _RALPH_TASKS_JSON_DONE=()

  while IFS= read -r f; do
    [[ -n "${f}" ]] && files+=("${f}")
  done < <(tasks_json_collect_files "${root_tasks_file}")

  [[ "${#files[@]}" -gt 0 ]] || return 1

  for f in "${files[@]}"; do
    local norm
    norm="$(json_like_to_temp_file "${f}")" || return 1
    normalized_files+=("${norm}")
  done

  jq -s '
    def deepmerge($a; $b):
      if ($a|type) == "object" and ($b|type) == "object" then
        reduce (($a + $b) | keys_unsorted[]) as $k
          ({}; .[$k] = deepmerge($a[$k]; $b[$k]))
      elif ($a|type) == "array" and ($b|type) == "array" then
        $a + $b
      elif $b == null then $a
      else $b
      end;
    reduce (map(del(.include, .includes))[]) as $item ({}; deepmerge(.; $item))
  ' "${normalized_files[@]}" > "${out_file}"
  rm -f "${normalized_files[@]}"
}

# Expands task references (`task`) using tasks.json entries.
expand_json_hook_task() {
  local payload="$1"
  local tasks_file="$2"
  local ref task_json norm_tasks

  ref="$(printf '%s' "${payload}" | jq -r '.task // empty' 2>/dev/null || true)"
  ref="$(json_hook_normalize_task_ref "${ref}")"
  [[ -n "${ref}" ]] || { printf '%s\n' "${payload}"; return 0; }
  [[ -n "${tasks_file}" && -f "${tasks_file}" ]] || { printf '%s\n' "${payload}"; return 0; }

  # Normalize JSONC to JSON for jq parsing
  norm_tasks="$(json_like_to_temp_file "${tasks_file}" 2>/dev/null || true)"
  [[ -n "${norm_tasks}" && -f "${norm_tasks}" ]] || { printf '%s\n' "${payload}"; return 0; }

  task_json="$(jq -c --arg ref "${ref}" '
    def dotted_path_lookup($obj; $ref):
      if ($obj|type) != "object" then empty
      elif ($obj[$ref] // null) != null then $obj[$ref]
      else (try ($obj | getpath($ref | split("."))) catch empty)
      end;
    if (.tasks|type) == "object" then (dotted_path_lookup(.tasks; $ref) // empty)
    elif (.tasks|type) == "array" then ([.tasks[] | select((.code // "") == $ref)][0] // empty)
    else empty end
  ' "${norm_tasks}" 2>/dev/null || true)"

  if [[ -z "${task_json}" || "${task_json}" == "null" ]]; then
    rm -f "${norm_tasks}"
    echo "${C_YELLOW}[hooks.json]${C_RESET} task not found: ${ref}" >&2
    printf '%s\n' "${payload}"
    return 0
  fi

  local result
  result="$(jq -cn --argjson task "${task_json}" --argjson cmd "${payload}" '
    def deepmerge($a; $b):
      if ($a|type) == "object" and ($b|type) == "object" then
        reduce (($a + $b) | keys_unsorted[]) as $k
          ({}; .[$k] = deepmerge($a[$k]; $b[$k]))
      elif ($a|type) == "array" and ($b|type) == "array" then
        $a + $b
      elif $b == null then $a
      else $b
      end;
    def clean($x):
      ($x
        | if (.run // "") == "" then del(.run) else . end
        | if (.cmd // "") == "" then del(.cmd) else . end
        | if (.cwd // "") == "" then del(.cwd) else . end
        | if (.prompt // "") == "" then del(.prompt) else . end
        | if (.when // "") == "" then del(.when) else . end
        | if (.allow_failure // false) == false then del(.allow_failure) else . end
        | if (.run_in_dry_run // false) == false then del(.run_in_dry_run) else . end
        | if (.human_gate // false) == false then del(.human_gate) else . end
        | if (.default_yes // false) == false then del(.default_yes) else . end
      );
    deepmerge($task; clean($cmd))
  ' 2>/dev/null || printf '%s\n' "${payload}")"
  rm -f "${norm_tasks}"
  printf '%s\n' "${result}"
}

# Normalizes task reference formats to dotted task key.
# Supported input examples:
# - "task:wizard.workflow-coding"
# - "{tasks.wizard.workflow-coding}"
# - "{wizard.workflow-coding}"
# - "wizard.workflow-coding"
json_hook_normalize_task_ref() {
  local ref="${1:-}"
  [[ -z "${ref}" ]] && return 0

  ref="${ref#task:}"
  if [[ "${ref}" =~ ^\{(.+)\}$ ]]; then
    ref="${BASH_REMATCH[1]}"
  fi
  ref="${ref#tasks.}"
  printf '%s\n' "${ref}"
}

# Runs a task from tasks.jsonc by reference path.
# Usage: run_task "git.is-repo" [tasks_file]
# Returns: exit code of the task command
run_task() {
  local ref="$1"
  local tasks_file="${2:-${RALPH_TASKS_FILE:-}}"
  local cmd cwd_abs

  # Resolve tasks file if not provided
  if [[ -z "${tasks_file}" || ! -f "${tasks_file}" ]]; then
    local root="${ROOT:-${RALPH_WORKSPACE:-.}}"
    if [[ -f "${root}/.ralph/tasks.jsonc" ]]; then
      tasks_file="${root}/.ralph/tasks.jsonc"
    elif [[ -f "${root}/.ralph/tasks.json" ]]; then
      tasks_file="${root}/.ralph/tasks.json"
    else
      echo "[run_task] tasks file not found" >&2
      return 1
    fi
  fi

  cmd="$(json_hook_when_task_command "${ref}" "${tasks_file}")"
  if [[ -z "${cmd}" ]]; then
    echo "[run_task] task not found: ${ref}" >&2
    return 1
  fi

  cwd_abs="${ROOT:-${RALPH_WORKSPACE:-.}}"
  (
    cd "${cwd_abs}"
    bash -lc "${cmd}"
  )
}

# Checks if a task condition passes (exit 0) without output.
# Usage: task_condition "git.is-repo" && echo "yes"
task_condition() {
  local ref="$1"
  local tasks_file="${2:-${RALPH_TASKS_FILE:-}}"

  run_task "${ref}" "${tasks_file}" >/dev/null 2>&1
}

# Executes hooks.json commands for event + phase.
# Phase values: before-system | system | after-system
run_json_hook_commands() {
  local event="$1"
  local phase="${2:-system}"
  local step="${3:-}"
  local step_exit_code="${4:-}"
  local hooks_file="${HOOKS_JSON_PATH:-}"
  local tasks_file="${TASKS_JSON_PATH:-${RALPH_TASKS_FILE:-}}"
  local merged_hooks_file=""
  local merged_tasks_file=""
  [[ -n "${hooks_file}" ]] || return 0
  [[ -f "${hooks_file}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  merged_hooks_file="$(mktemp)"
  if ! build_merged_hooks_json "${hooks_file}" "${merged_hooks_file}"; then
    rm -f "${merged_hooks_file}"
    echo "${C_YELLOW}[hooks.json]${C_RESET} failed to resolve includes"
    return 1
  fi
  hooks_file="${merged_hooks_file}"
  merged_tasks_file="$(mktemp)"
  if build_merged_tasks_json "${tasks_file}" "${merged_tasks_file}" 2>/dev/null; then
    tasks_file="${merged_tasks_file}"
  else
    rm -f "${merged_tasks_file}"
    merged_tasks_file=""
    tasks_file=""
  fi

  local stop_on_error
  stop_on_error="$(jq -r --arg event "${event}" --arg phase "${phase}" '
    .[$event][$phase] as $node
    | if $node == null then "false"
      elif ($node|type) == "object" then (($node.stop_on_error // true)|tostring)
      elif ($node|type) == "array" then "true"
      else "false"
      end
  ' "${hooks_file}" 2>/dev/null || echo "false")"

  local lines
  lines="$(jq -r --arg event "${event}" --arg phase "${phase}" '
    def to_command:
      if type == "string" then
        {type:"run", run: ., when: "", human_gate: false, prompt: "", default_yes: false, allow_failure: false, cwd: "", run_in_dry_run: false}
      elif type == "object" then
        {
          type: (if (.select // null) != null then "select" else "run" end),
          select: (.select // null),
          run: (.run // .cmd // ""),
          when: (.when // ""),
          human_gate: (
            if (.human_gate|type) == "boolean" then .human_gate
            elif (.human_gate|type) == "object" then true
            else false end
          ),
          prompt: (
            .prompt // (
              if (.human_gate|type) == "object"
              then (.human_gate.prompt // "")
              else ""
              end
            )
          ),
          default_yes: (
            if (.human_gate|type) == "object" then
              if (.human_gate.default_yes // null) != null then .human_gate.default_yes
              elif ((.human_gate.default // "") | ascii_downcase) == "yes" then true
              else false end
            else false end
          ),
          allow_failure: (.allow_failure // false),
          cwd: (.cwd // ""),
          run_in_dry_run: (.run_in_dry_run // false)
        }
      else empty end;

    .[$event][$phase] as $node
    | if $node == null then []
      elif ($node|type) == "array" then $node
      elif ($node|type) == "object" then ($node.commands // [])
      else [] end
    | .[]
    | to_command
    | select((.type == "select") or (.run != ""))
    | @base64
  ' "${hooks_file}" 2>/dev/null || true)"

  [[ -n "${lines}" ]] || return 0

  local line payload entry_type cmd human_gate prompt_text default_yes allow_failure cwd_rel run_in_dry_run
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    payload="$(printf '%s' "${line}" | base64 -d 2>/dev/null || true)"
    [[ -n "${payload}" ]] || continue
    entry_type="$(printf '%s' "${payload}" | jq -r '.type // "run"')"

    if [[ "${entry_type}" == "select" ]]; then
      local select_when_expr select_run_in_dry_run
      select_when_expr="$(printf '%s' "${payload}" | jq -c '.when // empty')"
      if ! json_hook_when_matches "${select_when_expr}" "${tasks_file}" ""; then
        echo "${C_DIM}[hooks.json]${C_RESET} ${event}: condition not met, skipping select"
        continue
      fi

      select_run_in_dry_run="$(printf '%s' "${payload}" | jq -r 'if .run_in_dry_run then "1" else "0" end')"
      if [[ "${DRY_RUN}" -eq 1 && "${select_run_in_dry_run}" != "1" ]]; then
        echo "${C_DIM}[hooks.json]${C_RESET} ${event}: select skipped in dry-run"
        continue
      fi

      run_json_hook_select_entry "${event}" "${payload}" "${stop_on_error}" "${step}" "${step_exit_code}" "${tasks_file}" || return $?
      continue
    fi

    cmd="$(printf '%s' "${payload}" | jq -r '.run // empty')"
    if [[ -z "${cmd}" ]]; then
      echo "${C_YELLOW}[hooks.json]${C_RESET} ${event}: no runnable command resolved; skipping"
      continue
    fi
    human_gate="$(printf '%s' "${payload}" | jq -r 'if .human_gate then "1" else "0" end')"
    prompt_text="$(printf '%s' "${payload}" | jq -r '.prompt // empty')"
    default_yes="$(printf '%s' "${payload}" | jq -r 'if .default_yes then "1" else "0" end')"
    allow_failure="$(printf '%s' "${payload}" | jq -r 'if .allow_failure then "1" else "0" end')"
    cwd_rel="$(printf '%s' "${payload}" | jq -r '.cwd // empty')"
    run_in_dry_run="$(printf '%s' "${payload}" | jq -r 'if .run_in_dry_run then "1" else "0" end')"

    run_json_hook_command_entry \
      "${event}" \
      "${cmd}" \
      "$(printf '%s' "${payload}" | jq -c '.when // empty')" \
      "${human_gate}" \
      "${prompt_text}" \
      "${default_yes}" \
      "${allow_failure}" \
      "${cwd_rel}" \
      "${run_in_dry_run}" \
      "${stop_on_error}" \
      "${step}" \
      "${step_exit_code}" \
      "${tasks_file}" || return $?
  done <<< "${lines}"

  rm -f "${merged_hooks_file}" "${merged_tasks_file}"
  return 0
}
