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

# Compatibility for callers that formerly supplied estimated overall percentages.
progress_set() {
  shift
  local line="=== USB Update: $* ==="
  if [ "${LAST_PROGRESS_LINE:-}" != "$line" ]; then
    printf '%s\n' "$line"
    LAST_PROGRESS_LINE="$line"
  fi
}

progress_plan_init() { :; }
progress_plan_begin() {
  PHASE_PROGRESS_START=0
  PHASE_PROGRESS_END=0
  PHASE_PROGRESS_ESTIMATE=0
}
progress_plan_end() { :; }

format_duration() {
  local seconds="$1"
  if [ "$seconds" -ge 3600 ]; then
    printf '%sh %sm %ss' "$((seconds / 3600))" "$(((seconds % 3600) / 60))" "$((seconds % 60))"
  elif [ "$seconds" -ge 60 ]; then
    printf '%sm %ss' "$((seconds / 60))" "$((seconds % 60))"
  else
    printf '%ss' "$seconds"
  fi
}

command_progress() {
  local description="$1" started_ms="$2" elapsed
  elapsed=$(( ($(date +%s%3N) - started_ms) / 1000 ))
  printf '  %s — elapsed %s\n' "$description" "$(format_duration "$elapsed")"
}

copy_progress() {
  local description="$1" started_ms="$2" copied_bytes elapsed_ms percent rate
  copied_bytes="$(stat -c '%s' "$PROGRESS_COPY_TARGET" 2>/dev/null || printf '0')"
  elapsed_ms=$(( $(date +%s%3N) - started_ms ))
  [ "$elapsed_ms" -gt 0 ] || elapsed_ms=1
  [ "$copied_bytes" -le "$PROGRESS_COPY_BYTES" ] || copied_bytes="$PROGRESS_COPY_BYTES"
  percent=100
  if [ "$PROGRESS_COPY_BYTES" -gt 0 ]; then
    percent=$((copied_bytes * 100 / PROGRESS_COPY_BYTES))
  fi
  rate=$((copied_bytes * 1000 / elapsed_ms))
  printf '  %s — %s%%, %s/%s bytes, %s B/s average, elapsed %s\n' \
    "$description" "$percent" "$copied_bytes" "$PROGRESS_COPY_BYTES" "$rate" "$(format_duration "$((elapsed_ms / 1000))")"
}

stop_active_command() {
  local pid="${ACTIVE_CHILD_PID:-}" timer="${ACTIVE_PROGRESS_TIMER_PID:-}" attempt
  if [ -n "$timer" ]; then
    kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
  fi
  ACTIVE_PROGRESS_TIMER_PID=""
  if [ -n "$pid" ]; then
    # The worker owns a separate process group, including function subprocesses.
    kill -TERM -- "-$pid" 2>/dev/null || true
    for attempt in {1..50}; do
      if ! kill -0 -- "-$pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
}

run_with_progress() {
  local description="$1"
  shift
  local log_file pid timer status=0 started_ms completed_pid monitor_was_set=0
  local callback="${PROGRESS_CALLBACK:-command_progress}"
  local poll_seconds="${PROGRESS_POLL_SECONDS:-10}"

  log_file="$(mktemp "${UPDATE_USB_TMP_DIR:-${TMPDIR:-/tmp}}/update-usb-progress.XXXXXX")" || return
  started_ms="$(date +%s%3N)"
  "$callback" "$description" "$started_ms"
  case "$-" in *m*) monitor_was_set=1 ;; esac
  # Job control gives shell functions their own process group without exporting state.
  set -m
  if is_verbose; then
    "$@" &
  else
    "$@" >"$log_file" 2>&1 &
  fi
  pid="$!"
  ACTIVE_CHILD_PID="$pid"
  if [ "$monitor_was_set" -eq 0 ]; then set +m; fi

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$poll_seconds" &
    timer="$!"
    ACTIVE_PROGRESS_TIMER_PID="$timer"
    completed_pid=""
    # wait -n can miss an already-finished job. Explicit wait below owns its status.
    wait -n -p completed_pid "$pid" "$timer" 2>/dev/null || true
    if [ "${completed_pid:-}" = "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      kill "$timer" 2>/dev/null || true
      wait "$timer" 2>/dev/null || true
      ACTIVE_PROGRESS_TIMER_PID=""
      break
    fi
    wait "$timer" 2>/dev/null || true
    ACTIVE_PROGRESS_TIMER_PID=""
    "$callback" "$description" "$started_ms"
  done

  # Even a command that finished before the first poll must have its status read.
  wait "$pid" || status=$?
  ACTIVE_CHILD_PID=""
  if [ "$status" -ne 0 ]; then
    printf 'Error: %s failed (exit %s).\n' "$description" "$status" >&2
    if [ -s "$log_file" ]; then cat "$log_file" >&2; fi
  else
    "$callback" "$description" "$started_ms"
  fi
  rm -f "$log_file"
  return "$status"
}

run_logged() {
  run_with_progress "$@"
}

run_logged_progress() {
  local description="$1"
  shift 4
  run_with_progress "$description" "$@"
}

copy_with_progress() {
  local source="$1" target="$2" description="$5"
  local PROGRESS_CALLBACK=copy_progress PROGRESS_COPY_TARGET="$target" PROGRESS_COPY_BYTES
  PROGRESS_COPY_BYTES="$(stat -c '%s' "$source")" || return
  run_with_progress "$description" cp -- "$source" "$target"
}

phase_begin() {
  CURRENT_PHASE="$1"
  PHASE_LABEL="$2"
  PHASE_STARTED_AT="$(date +%s)"
  PHASE_ACTIVE=1
  progress_set 0 "$PHASE_LABEL"
}

phase_begin_estimated() {
  phase_begin "$1" "$2"
  progress_plan_begin
}

phase_end() {
  local elapsed=$(( $(date +%s) - PHASE_STARTED_AT ))
  TIMINGS+=("$PHASE_LABEL|$elapsed")
  if declare -F report_phase >/dev/null; then report_phase "$CURRENT_PHASE" "$PHASE_LABEL" "$elapsed" completed; fi
  PHASE_ACTIVE=0
}

phase_end_estimated() {
  phase_end
}

print_timing_summary() {
  if [ "${#TIMINGS[@]}" -eq 0 ]; then return; fi
  local total=0 timing label seconds
  echo "=== USB Update: Timing Summary ==="
  for timing in "${TIMINGS[@]}"; do
    label="${timing%%|*}"
    seconds="${timing##*|}"
    total=$((total + seconds))
    printf '  - %s: %s\n' "$label" "$(format_duration "$seconds")"
  done
  printf '  - total: %s\n' "$(format_duration "$total")"
}
