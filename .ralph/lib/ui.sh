#!/usr/bin/env bash
# Shared terminal UI helpers for Ralph hooks.
set -euo pipefail

# Prints a reusable ASCII box border.
ui_box_border() {
  local width="${1:-76}"
  printf '+'
  printf '%*s' "$((width + 2))" '' | tr ' ' '-'
  printf '+\n'
}

# Prints one left-aligned line inside a reusable ASCII box.
ui_box_line() {
  local text="${1:-}"
  local width="${2:-76}"
  printf '| %-*s |\n' "${width}" "${text}"
}

# Renders an interactive menu with arrow-key support.
# Usage:
#   choice="$(ui_prompt_menu_arrow "Prompt text" "Option 1" "Option 2" ...)"
# Returns:
#   prints selected 1-based index to stdout.
ui_prompt_menu_arrow() {
  local prompt="$1"
  shift
  local -a options=("$@")
  local selected=0
  local key key2 key3
  local option_count="${#options[@]}"
  local printed_lines=0

  # Clears the previously rendered menu block so the next frame redraws in-place.
  clear_menu_block() {
    local i
    if [[ "${printed_lines}" -le 0 ]]; then
      return 0
    fi
    for ((i=0; i<printed_lines; i++)); do
      printf '\033[1A\r\033[2K' >&2
    done
  }

  while true; do
    clear_menu_block

    echo "${prompt}" >&2
    local i
    for ((i=0; i<option_count; i++)); do
      if [[ "${i}" -eq "${selected}" ]]; then
        echo "  > $((i + 1))) ${options[i]}" >&2
      else
        echo "    $((i + 1))) ${options[i]}" >&2
      fi
    done
    printed_lines=$((option_count + 1))

    IFS= read -rsn1 key
    case "${key}" in
      "")
        clear_menu_block
        echo $((selected + 1))
        return 0
        ;;
      $'\n'|$'\r')
        clear_menu_block
        echo $((selected + 1))
        return 0
        ;;
      1|2|3|4|5|6|7|8|9)
        clear_menu_block
        echo "${key}"
        return 0
        ;;
      $'\x1b')
        IFS= read -rsn1 -t 0.02 key2 || true
        if [[ "${key2}" == "[" ]]; then
          IFS= read -rsn1 -t 0.02 key3 || true
          case "${key3}" in
            A) selected=$(( (selected - 1 + option_count) % option_count )) ;; # Up
            B) selected=$(( (selected + 1) % option_count )) ;;                 # Down
          esac
        fi
        ;;
    esac
  done
}

# Renders a paged interactive menu with arrow-key support.
# Usage:
#   choice="$(ui_prompt_menu_window 4 "Select plan:" "a.json" "b.json" ...)"
# Returns:
#   prints selected 1-based index to stdout.
ui_prompt_menu_window() {
  local page_size="${1:-4}"
  shift
  local prompt="$1"
  shift
  local -a options=("$@")
  local selected=0
  local option_count="${#options[@]}"
  local key key2 key3
  local printed_lines=0

  [[ "${option_count}" -gt 0 ]] || return 1
  [[ "${page_size}" =~ ^[0-9]+$ ]] || page_size=4
  [[ "${page_size}" -lt 1 ]] && page_size=4

  clear_menu_block_window() {
    local i
    if [[ "${printed_lines}" -le 0 ]]; then
      return 0
    fi
    for ((i=0; i<printed_lines; i++)); do
      printf '\033[1A\r\033[2K' >&2
    done
  }

  while true; do
    clear_menu_block_window

    local start=$(( (selected / page_size) * page_size ))
    local end=$(( start + page_size ))
    [[ "${end}" -gt "${option_count}" ]] && end="${option_count}"

    echo "${prompt}" >&2
    echo "Showing $((start + 1))-${end} of ${option_count} (↑/↓ + Enter)" >&2
    local i
    for ((i=start; i<end; i++)); do
      if [[ "${i}" -eq "${selected}" ]]; then
        echo "  > $((i + 1))) ${options[i]}" >&2
      else
        echo "    $((i + 1))) ${options[i]}" >&2
      fi
    done
    printed_lines=$((2 + end - start))

    IFS= read -rsn1 key
    case "${key}" in
      ""|$'\n'|$'\r')
        clear_menu_block_window
        echo $((selected + 1))
        return 0
        ;;
      1|2|3|4|5|6|7|8|9)
        if [[ "${key}" -le "${option_count}" ]]; then
          clear_menu_block_window
          echo "${key}"
          return 0
        fi
        ;;
      $'\x1b')
        IFS= read -rsn1 -t 0.02 key2 || true
        if [[ "${key2}" == "[" ]]; then
          IFS= read -rsn1 -t 0.02 key3 || true
          case "${key3}" in
            A) selected=$(( (selected - 1 + option_count) % option_count )) ;;
            B) selected=$(( (selected + 1) % option_count )) ;;
          esac
        fi
        ;;
    esac
  done
}
