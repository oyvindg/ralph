#!/usr/bin/env bash
# Docker helpers for Ralph containerized execution.
# Delegates to task:docker.* from tasks.jsonc.
set -euo pipefail

DOCKER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load parser for run_task/task_condition helpers
if [[ -f "${DOCKER_LIB_DIR}/core/parser.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DOCKER_LIB_DIR}/core/parser.sh"
fi

# Build the ralph docker image.
docker_build() {
  run_task "docker.build"
}

# Check if ralph docker image exists.
docker_image_exists() {
  task_condition "docker.image-exists"
}

# Run ralph in docker container.
docker_run() {
  local rebuild="$1"
  shift

  # Build image if needed
  if [[ "${rebuild}" -eq 1 ]] || ! docker_image_exists; then
    docker_build
  fi

  # Parse args to find workspace/plan/guide paths for mounting
  declare -A MOUNT_PATHS
  local DOCKER_ARGS=()
  local DOCKER_WORKSPACE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        DOCKER_WORKSPACE="$(cd "${2/#\~/$HOME}" && pwd)"
        MOUNT_PATHS["${DOCKER_WORKSPACE}"]=1
        DOCKER_ARGS+=("$1" "${DOCKER_WORKSPACE}")
        shift 2
        ;;
      --plan)
        local plan_arg="${2/#\~/$HOME}"
        if [[ "${plan_arg}" == */* ]]; then
          local plan_dir
          plan_dir="$(cd "$(dirname "${plan_arg}")" && pwd)"
          MOUNT_PATHS["${plan_dir}"]=1
          DOCKER_ARGS+=("$1" "${plan_dir}/$(basename "${plan_arg}")")
        else
          DOCKER_ARGS+=("$1" "${plan_arg}")
        fi
        shift 2
        ;;
      --guide)
        local guide_path="${2/#\~/$HOME}"
        guide_path="$(cd "$(dirname "${guide_path}")" && pwd)/$(basename "${guide_path}")"
        MOUNT_PATHS["$(dirname "${guide_path}")"]=1
        DOCKER_ARGS+=("$1" "${guide_path}")
        shift 2
        ;;
      *)
        DOCKER_ARGS+=("$1")
        shift
        ;;
    esac
  done

  # Default workspace to current directory
  if [[ -z "${DOCKER_WORKSPACE}" ]]; then
    DOCKER_WORKSPACE="$(pwd)"
    MOUNT_PATHS["${DOCKER_WORKSPACE}"]=1
  fi

  # Build unique volume mounts
  local VOLUMES=()
  for path in "${!MOUNT_PATHS[@]}"; do
    VOLUMES+=(-v "${path}:${path}")
  done

  # TTY flags
  local TTY_FLAGS=""
  [[ -t 1 ]] && TTY_FLAGS="-t"
  [[ -t 0 ]] && TTY_FLAGS="-it"

  # Temp file for error checking
  local output_file
  output_file=$(mktemp)
  trap "rm -f ${output_file}" EXIT

  # Run ralph in docker as current user
  set +e
  docker run --rm ${TTY_FLAGS} \
    --user "$(id -u):$(id -g)" \
    -w "${DOCKER_WORKSPACE}" \
    "${VOLUMES[@]}" \
    -v "${HOME}/.codex/auth.json:${HOME}/.codex/auth.json:ro" \
    -v "${HOME}/.codex/config.toml:${HOME}/.codex/config.toml:ro" \
    -e HOME="${HOME}" \
    ralph "${DOCKER_ARGS[@]}" 2>&1 | tee "${output_file}"
  local exit_code=${PIPESTATUS[0]}
  set -e

  # Check for rate limit errors
  if grep -qi "usage limit\|hit your.*limit\|rate limit" "${output_file}" 2>/dev/null; then
    echo ""
    echo $'\033[31m============================================\033[0m'
    echo $'\033[31m  API USAGE LIMIT REACHED\033[0m'
    echo $'\033[33m  Check your plan or wait for quota reset\033[0m'
    echo $'\033[31m============================================\033[0m'
  fi

  exit ${exit_code}
}

# Check for docker delegation flags and handle them.
# Returns 0 if delegated (caller should exit), 1 if not delegated.
check_docker_delegation() {
  for arg in "$@"; do
    if [[ "${arg}" == "--docker-build" ]]; then
      docker_build
      exit 0
    fi
    if [[ "${arg}" == "--docker" ]]; then
      local args=()
      for a in "$@"; do
        [[ "${a}" != "--docker" ]] && args+=("${a}")
      done
      docker_run 0 "${args[@]}"
    fi
    if [[ "${arg}" == "--docker-rebuild" ]]; then
      local args=()
      for a in "$@"; do
        [[ "${a}" != "--docker-rebuild" ]] && args+=("${a}")
      done
      docker_run 1 "${args[@]}"
    fi
  done
}
