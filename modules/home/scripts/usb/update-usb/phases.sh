#!/usr/bin/env bash
# shellcheck disable=SC2034

is_verbose() {
  [ "${VERBOSE:-0}" -eq 1 ]
}

verbose_log() {
  if is_verbose; then
    printf '%s\n' "$*"
  fi
}

run_logged() {
  local description="$1"
  shift

  if is_verbose; then
    "$@"
    return
  fi

  local output="" status=0
  if output="$("$@" 2>&1)"; then
    return 0
  else
    status=$?
  fi

  echo "Error: $description failed." >&2
  if [ -n "$output" ]; then
    printf '%s\n' "$output" >&2
  fi
  return "$status"
}

phase_begin() {
  CURRENT_PHASE="$1"
  PHASE_LABEL="$2"
  PHASE_STARTED_AT="$(date +%s)"
  echo "=== USB Update: $PHASE_LABEL ==="
}

phase_end() {
  local phase_ended_at phase_elapsed
  phase_ended_at="$(date +%s)"
  phase_elapsed=$((phase_ended_at - PHASE_STARTED_AT))
  TIMINGS+=("$PHASE_LABEL|$phase_elapsed")
}

format_duration() {
  local seconds="$1"
  local hours minutes remaining

  if [ "$seconds" -lt 60 ]; then
    printf '%ss' "$seconds"
    return
  fi

  hours=$((seconds / 3600))
  minutes=$(((seconds % 3600) / 60))
  remaining=$((seconds % 60))

  if [ "$hours" -gt 0 ]; then
    if [ "$minutes" -gt 0 ] && [ "$remaining" -gt 0 ]; then
      printf '%sh %sm %ss' "$hours" "$minutes" "$remaining"
    elif [ "$minutes" -gt 0 ]; then
      printf '%sh %sm' "$hours" "$minutes"
    elif [ "$remaining" -gt 0 ]; then
      printf '%sh %ss' "$hours" "$remaining"
    else
      printf '%sh' "$hours"
    fi
    return
  fi

  if [ "$remaining" -gt 0 ]; then
    printf '%sm %ss' "$minutes" "$remaining"
  else
    printf '%sm' "$minutes"
  fi
}

print_timing_summary() {
  if [ "${#TIMINGS[@]}" -eq 0 ]; then
    return
  fi

  local total=0
  echo "=== USB Update: Timing Summary ==="
  for timing in "${TIMINGS[@]}"; do
    local label="${timing%%|*}"
    local seconds="${timing##*|}"
    total=$((total + seconds))
    printf '  - %s: %s\n' "$label" "$(format_duration "$seconds")"
  done
  printf '  - total: %s\n' "$(format_duration "$total")"
}
