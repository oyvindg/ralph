#!/usr/bin/env bash
# =============================================================================
# AI Engine Hook
# =============================================================================
#
# Executes AI model based on RALPH_ENGINE environment variable.
# Automatically detects available engines on the system.
#
# Supported engines:
#   - codex      OpenAI Codex CLI (default)
#   - claude     Claude Code CLI
#   - ollama     Local models via Ollama
#   - openai     OpenAI API direct (requires OPENAI_API_KEY)
#   - anthropic  Anthropic API direct (requires ANTHROPIC_API_KEY)
#   - mock       Simulated responses for testing/dry-run
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

# =============================================================================
# Engine Detection
# =============================================================================

detect_codex() {
  command -v codex >/dev/null 2>&1
}

detect_claude() {
  command -v claude >/dev/null 2>&1
}

detect_ollama() {
  command -v ollama >/dev/null 2>&1 && \
    ollama list >/dev/null 2>&1
}

detect_openai() {
  [[ -n "${OPENAI_API_KEY:-}" ]]
}

detect_anthropic() {
  [[ -n "${ANTHROPIC_API_KEY:-}" ]]
}

# Mock is always available
detect_mock() {
  return 0
}

# =============================================================================
# List Available Engines
# =============================================================================

list_engines() {
  echo "Available AI engines:"
  echo ""

  if detect_codex; then
    echo "  [x] codex      - OpenAI Codex CLI"
  else
    echo "  [ ] codex      - OpenAI Codex CLI (not installed)"
  fi

  if detect_claude; then
    echo "  [x] claude     - Claude Code CLI"
  else
    echo "  [ ] claude     - Claude Code CLI (not installed)"
  fi

  if detect_ollama; then
    local models
    models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ', ' | sed 's/,$//')
    echo "  [x] ollama     - Local models: ${models:-none}"
  else
    echo "  [ ] ollama     - Local models (not running)"
  fi

  if detect_openai; then
    echo "  [x] openai     - OpenAI API (key set)"
  else
    echo "  [ ] openai     - OpenAI API (OPENAI_API_KEY not set)"
  fi

  if detect_anthropic; then
    echo "  [x] anthropic  - Anthropic API (key set)"
  else
    echo "  [ ] anthropic  - Anthropic API (ANTHROPIC_API_KEY not set)"
  fi

  echo "  [x] mock       - Simulated responses (always available)"
  echo ""
}

# =============================================================================
# Auto-detect Best Engine
# =============================================================================

auto_detect_engine() {
  # Priority: codex > claude > ollama > openai > anthropic
  if detect_codex; then
    echo "codex"
  elif detect_claude; then
    echo "claude"
  elif detect_ollama; then
    echo "ollama"
  elif detect_openai; then
    echo "openai"
  elif detect_anthropic; then
    echo "anthropic"
  else
    echo ""
  fi
}

# =============================================================================
# Engine: Mock (Simulated)
# =============================================================================
# Generates realistic stub responses for testing and dry-run mode.
# Supports failure simulation for testing error handling.
#
# Environment variables:
#   RALPH_MOCK_FAIL=1       Force mock to fail
#   RALPH_MOCK_FAIL_RATE=N  Random failure rate (0-100, e.g., 30 = 30%)
#   RALPH_MOCK_EMPTY=1      Generate empty response
#   RALPH_MOCK_ERROR=1      Generate response with error markers
#
run_mock() {
  # Check for forced failure
  if [[ "${RALPH_MOCK_FAIL:-0}" == "1" ]]; then
    echo "[ai] MOCK: Simulating AI failure"
    return 1
  fi

  # Check for random failure
  if [[ -n "${RALPH_MOCK_FAIL_RATE:-}" ]]; then
    local rand=$((RANDOM % 100))
    if [[ "${rand}" -lt "${RALPH_MOCK_FAIL_RATE}" ]]; then
      echo "[ai] MOCK: Random failure (${rand} < ${RALPH_MOCK_FAIL_RATE}%)"
      return 1
    fi
  fi

  # Check for empty response simulation
  if [[ "${RALPH_MOCK_EMPTY:-0}" == "1" ]]; then
    echo "[ai] MOCK: Generating empty response"
    : > "${RESPONSE_FILE}"
    return 0
  fi

  local prompt_preview
  prompt_preview=$(head -c 200 "${PROMPT_FILE}" | tr '\n' ' ')

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Check for error response simulation
  if [[ "${RALPH_MOCK_ERROR:-0}" == "1" ]]; then
    cat > "${RESPONSE_FILE}" <<EOF
##### Mock AI Response (WITH ERRORS)

**Generated:** ${timestamp}
**Engine:** mock (simulated error)

---

##### Error Simulation

ERROR: Simulated error in AI response
FAILED: Mock failure for testing
Exception: TestException - this is a simulated error

##### Prompt preview:
> ${prompt_preview}...

---

*This response simulates an error condition for testing.*
EOF
    echo "[ai] MOCK: Generated error response"
    return 0
  fi

  # Normal mock response
  cat > "${RESPONSE_FILE}" <<EOF
##### Mock AI Response

**Generated:** ${timestamp}
**Engine:** mock (simulated)
**Model:** ${MODEL:-default}

---

##### Summary

This is a simulated response for testing purposes.

**Prompt preview:**
> ${prompt_preview}...

##### Actions Taken

- [mock] Analyzed the prompt
- [mock] Simulated code analysis
- [mock] Generated placeholder response

##### Next Steps

1. Review the simulated output
2. Verify hook execution flow
3. Check session logging

---

*This response was generated by the mock engine for dry-run/testing.*
EOF

  echo "[ai] Mock response generated"
}

# =============================================================================
# Engine: Codex
# =============================================================================

run_codex() {
  if ! detect_codex; then
    echo "[ai] ERROR: codex CLI not installed" >&2
    exit 1
  fi

  local model_flag=""
  [[ -n "${MODEL}" ]] && model_flag="--model ${MODEL}"

  codex exec --full-auto \
    -C "${WORKSPACE}" \
    ${model_flag} \
    -o "${RESPONSE_FILE}" \
    - < "${PROMPT_FILE}"
}

# =============================================================================
# Engine: Claude
# =============================================================================

run_claude() {
  if ! detect_claude; then
    echo "[ai] ERROR: claude CLI not installed" >&2
    exit 1
  fi

  local model_flag=""
  [[ -n "${MODEL}" ]] && model_flag="--model ${MODEL}"

  claude ${model_flag} \
    -p "$(cat "${PROMPT_FILE}")" \
    > "${RESPONSE_FILE}"
}

# =============================================================================
# Engine: Ollama
# =============================================================================

run_ollama() {
  if ! detect_ollama; then
    echo "[ai] ERROR: ollama not running" >&2
    exit 1
  fi

  local model="${MODEL:-deepseek-coder}"

  ollama run "${model}" \
    < "${PROMPT_FILE}" \
    > "${RESPONSE_FILE}"
}

# =============================================================================
# Engine: OpenAI API
# =============================================================================

run_openai() {
  if ! detect_openai; then
    echo "[ai] ERROR: OPENAI_API_KEY not set" >&2
    exit 1
  fi

  local model="${MODEL:-gpt-4}"
  local prompt_content

  prompt_content=$(jq -Rs . < "${PROMPT_FILE}")

  curl -s https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${model}\",
      \"messages\": [{\"role\": \"user\", \"content\": ${prompt_content}}]
    }" | jq -r '.choices[0].message.content' > "${RESPONSE_FILE}"
}

# =============================================================================
# Engine: Anthropic API
# =============================================================================

run_anthropic() {
  if ! detect_anthropic; then
    echo "[ai] ERROR: ANTHROPIC_API_KEY not set" >&2
    exit 1
  fi

  local model="${MODEL:-claude-sonnet-4-20250514}"
  local prompt_content

  prompt_content=$(jq -Rs . < "${PROMPT_FILE}")

  curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${model}\",
      \"max_tokens\": 4096,
      \"messages\": [{\"role\": \"user\", \"content\": ${prompt_content}}]
    }" | jq -r '.content[0].text' > "${RESPONSE_FILE}"
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
    ENGINE=$(auto_detect_engine)
    if [[ -z "${ENGINE}" ]]; then
      echo "[ai] ERROR: No AI engine available" >&2
      echo "[ai] Run with RALPH_ENGINE=list to see options" >&2
      exit 1
    fi
    echo "[ai] Auto-detected: ${ENGINE}"
  fi

  validate_inputs

  echo "[ai] Engine: ${ENGINE}"
  [[ -n "${MODEL}" ]] && echo "[ai] Model: ${MODEL}"
  echo "[ai] Prompt: ${PROMPT_FILE}"

  # Dispatch to engine
  case "${ENGINE}" in
    mock)      run_mock      ;;
    codex)     run_codex     ;;
    claude)    run_claude    ;;
    ollama)    run_ollama    ;;
    openai)    run_openai    ;;
    anthropic) run_anthropic ;;
    *)
      echo "[ai] ERROR: Unknown engine: ${ENGINE}" >&2
      echo "[ai] Run with RALPH_ENGINE=list to see available engines" >&2
      exit 1
      ;;
  esac

  # Verify output
  verify_response

  echo "[ai] Response: ${RESPONSE_FILE}"
  exit 0
}

main "$@"
