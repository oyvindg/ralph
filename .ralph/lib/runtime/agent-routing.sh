#!/usr/bin/env bash
# Agent routing helpers for Ralph orchestrator.
set -euo pipefail

resolve_agent_for_step() {
  local step_id="${1:-}"
  local step_desc="${2:-}"
  local haystack route matched=0
  local default_engine="" default_model=""
  local route_match route_engine route_model

  ACTIVE_ENGINE="${RALPH_ENGINE:-codex}"
  ACTIVE_MODEL="${MODEL:-}"

  if [[ "${ENGINE_CLI_SET}" -eq 1 || "${MODEL_CLI_SET}" -eq 1 ]]; then
    return 0
  fi

  haystack="$(printf '%s %s' "${step_id}" "${step_desc}" | tr '[:upper:]' '[:lower:]')"

  for route in ${PROFILE_AGENT_ROUTES:-}; do
    route_match=""
    route_engine=""
    route_model=""
    IFS='|' read -r route_match route_engine route_model <<< "${route}"
    route_match="$(printf '%s' "${route_match}" | tr '[:upper:]' '[:lower:]')"

    [[ -z "${route_match}" || -z "${route_engine}" ]] && continue

    if [[ "${route_match}" == "default" ]]; then
      default_engine="${route_engine}"
      default_model="${route_model}"
      continue
    fi

    if [[ "${haystack}" == *"${route_match}"* ]]; then
      ACTIVE_ENGINE="${route_engine}"
      if [[ -n "${route_model}" && "${route_model}" != "-" ]]; then
        ACTIVE_MODEL="${route_model}"
      fi
      matched=1
      break
    fi
  done

  if [[ "${matched}" -eq 0 ]] && [[ -n "${default_engine}" ]]; then
    ACTIVE_ENGINE="${default_engine}"
    if [[ -n "${default_model}" && "${default_model}" != "-" ]]; then
      ACTIVE_MODEL="${default_model}"
    fi
  fi
}
