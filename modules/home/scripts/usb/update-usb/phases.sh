#!/usr/bin/env bash
# shellcheck disable=SC2034

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
    printf '  - %s: %ss\n' "$label" "$seconds"
  done
  printf '  - total: %ss\n' "$total"
}
