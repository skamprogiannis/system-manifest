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

progress_set() {
  local percent="$1"
  shift
  local message="$*"
  local line="[$percent%] $message"

  if [ "$percent" -lt "${PROGRESS_PERCENT:-0}" ]; then
    percent="$PROGRESS_PERCENT"
    line="[$percent%] $message"
  elif [ "$percent" -gt 100 ]; then
    percent=100
    line="[$percent%] $message"
  fi

  if [ "${LAST_PROGRESS_LINE:-}" != "$line" ]; then
    printf '%s\n' "$line"
    LAST_PROGRESS_LINE="$line"
  fi
  PROGRESS_PERCENT="$percent"
}

extract_latest_percent() {
  local log_file="$1"

  if [ ! -s "$log_file" ]; then
    return 1
  fi

  tr '\r' '\n' <"$log_file" \
    | sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p' \
    | tail -n1
}

map_percent_range() {
  local percent="$1"
  local start="$2"
  local end="$3"

  if [ "$percent" -lt 0 ]; then
    percent=0
  elif [ "$percent" -gt 100 ]; then
    percent=100
  fi

  printf '%s\n' $((start + (percent * (end - start) / 100)))
}

estimated_progress_percent() {
  local elapsed_seconds="$1"
  local estimate_seconds="$2"
  local start="$3"
  local end="$4"

  if [ "$estimate_seconds" -le 0 ] || [ "$elapsed_seconds" -le 0 ]; then
    printf '%s\n' "$start"
    return
  fi

  if [ "$elapsed_seconds" -gt "$estimate_seconds" ]; then
    elapsed_seconds="$estimate_seconds"
  fi

  printf '%s\n' $((start + (elapsed_seconds * (end - start) / estimate_seconds)))
}

adaptive_progress_end() {
  local current_percent="$1"
  local phase_seconds="$2"
  local remaining_seconds="$3"
  local available_percent end_percent

  if [ "$remaining_seconds" -le 0 ] || [ "$phase_seconds" -le 0 ]; then
    printf '%s\n' "$current_percent"
    return
  fi

  available_percent=$((100 - current_percent))
  end_percent=$((current_percent + (available_percent * phase_seconds / remaining_seconds)))

  if [ "$end_percent" -ge 100 ]; then
    end_percent=99
  elif [ "$end_percent" -le "$current_percent" ] && [ "$current_percent" -lt 99 ]; then
    end_percent=$((current_percent + 1))
  fi

  printf '%s\n' "$end_percent"
}

progress_plan_init() {
  local estimate_seconds

  PROGRESS_PLAN_REMAINING_SECONDS=0
  for estimate_seconds in "$@"; do
    PROGRESS_PLAN_REMAINING_SECONDS=$((PROGRESS_PLAN_REMAINING_SECONDS + estimate_seconds))
  done
}

progress_plan_begin() {
  local estimate_seconds="$1"

  PHASE_PROGRESS_START="${PROGRESS_PERCENT:-0}"
  PHASE_PROGRESS_END="$(adaptive_progress_end "$PHASE_PROGRESS_START" "$estimate_seconds" "$PROGRESS_PLAN_REMAINING_SECONDS")"
  PHASE_PROGRESS_ESTIMATE="$estimate_seconds"
}

progress_plan_end() {
  local elapsed_seconds completed_percent

  elapsed_seconds=$(( $(date +%s) - PHASE_STARTED_AT ))
  completed_percent="$(estimated_progress_percent "$elapsed_seconds" "$PHASE_PROGRESS_ESTIMATE" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END")"
  progress_set "$completed_percent" "$PHASE_LABEL"
  PROGRESS_PLAN_REMAINING_SECONDS=$((PROGRESS_PLAN_REMAINING_SECONDS - PHASE_PROGRESS_ESTIMATE))
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

run_logged_progress() {
  local description="$1"
  local start_percent="$2"
  local end_percent="$3"
  local estimate_seconds="$4"
  shift 4

  if is_verbose; then
    "$@"
    return
  fi

  local log_file pid status=0 displayed_percent latest_percent mapped_percent started_at
  local sleep_pid wait_status
  local poll_seconds="${PROGRESS_POLL_SECONDS:-60}"

  log_file="$(mktemp)"
  started_at="$(date +%s)"
  "$@" >"$log_file" 2>&1 &
  pid="$!"

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$poll_seconds" &
    sleep_pid="$!"

    set +e
    wait -n "$pid" "$sleep_pid"
    wait_status=$?
    set -e

    if ! kill -0 "$pid" 2>/dev/null; then
      if kill -0 "$sleep_pid" 2>/dev/null; then
        kill "$sleep_pid" 2>/dev/null || true
        wait "$sleep_pid" 2>/dev/null || true
      fi
      status="$wait_status"
      break
    fi

    wait "$sleep_pid" 2>/dev/null || true

    latest_percent="$(extract_latest_percent "$log_file" || true)"
    if [ -n "$latest_percent" ]; then
      mapped_percent="$(map_percent_range "$latest_percent" "$start_percent" "$end_percent")"
      if [ "$mapped_percent" -lt "$end_percent" ]; then
        progress_set "$mapped_percent" "$description"
      fi
      continue
    fi

    displayed_percent="$(estimated_progress_percent "$(( $(date +%s) - started_at ))" "$estimate_seconds" "$start_percent" "$end_percent")"
    if [ "$displayed_percent" -lt "$end_percent" ]; then
      progress_set "$displayed_percent" "$description"
    fi
  done

  if [ "$status" -ne 0 ]; then
    echo "Error: $description failed." >&2
    if [ -s "$log_file" ]; then
      cat "$log_file" >&2
    fi
    rm -f "$log_file"
    return "$status"
  fi

  rm -f "$log_file"
}

copy_with_progress() {
  local source="$1"
  local target="$2"
  local start_percent="$3"
  local end_percent="$4"
  local description="$5"

  if is_verbose; then
    cp "$source" "$target"
    return
  fi

  local total_bytes copied_bytes raw_percent mapped_percent pid status=0
  local sleep_pid wait_status
  total_bytes="$(stat -c '%s' "$source")"
  cp "$source" "$target" &
  pid="$!"

  while kill -0 "$pid" 2>/dev/null; do
    sleep 1 &
    sleep_pid="$!"

    set +e
    wait -n "$pid" "$sleep_pid"
    wait_status=$?
    set -e

    if ! kill -0 "$pid" 2>/dev/null; then
      if kill -0 "$sleep_pid" 2>/dev/null; then
        kill "$sleep_pid" 2>/dev/null || true
        wait "$sleep_pid" 2>/dev/null || true
      fi
      status="$wait_status"
      break
    fi

    wait "$sleep_pid" 2>/dev/null || true

    copied_bytes="$(stat -c '%s' "$target" 2>/dev/null || printf '0')"
    if [ "$total_bytes" -gt 0 ]; then
      raw_percent=$((copied_bytes * 100 / total_bytes))
      mapped_percent="$(map_percent_range "$raw_percent" "$start_percent" "$end_percent")"
      if [ "$mapped_percent" -lt "$end_percent" ]; then
        progress_set "$mapped_percent" "$description"
      fi
    fi
  done

  if [ "$status" -ne 0 ]; then
    echo "Error: $description failed." >&2
    return "$status"
  fi
}

phase_begin() {
  CURRENT_PHASE="$1"
  PHASE_LABEL="$2"
  PHASE_STARTED_AT="$(date +%s)"
  if [ -n "${3:-}" ]; then
    progress_set "$3" "$PHASE_LABEL"
  else
    echo "=== USB Update: $PHASE_LABEL ==="
  fi
}

phase_begin_estimated() {
  CURRENT_PHASE="$1"
  PHASE_LABEL="$2"
  PHASE_STARTED_AT="$(date +%s)"
  if [ -n "${4:-}" ]; then
    progress_set "$4" "$PHASE_LABEL"
  fi
  progress_plan_begin "$3"
  progress_set "$PHASE_PROGRESS_START" "$PHASE_LABEL"
}

phase_end() {
  local phase_ended_at phase_elapsed
  phase_ended_at="$(date +%s)"
  phase_elapsed=$((phase_ended_at - PHASE_STARTED_AT))
  TIMINGS+=("$PHASE_LABEL|$phase_elapsed")
}

phase_end_estimated() {
  progress_plan_end
  phase_end
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
