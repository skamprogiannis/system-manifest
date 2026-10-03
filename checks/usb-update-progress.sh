#!/usr/bin/env bash
# Helpers and shared variables are consumed by the sourced implementation.
# shellcheck disable=SC2034,SC2329
set -euo pipefail

source_dir="${1:?usage: usb-update-progress.sh update-usb-source-directory}"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
export UPDATE_USB_TMP_DIR="$test_dir"
export PROGRESS_POLL_SECONDS=0.05
# shellcheck source=/dev/null
. "$source_dir/phases.sh"
TIMINGS=()

fail() { echo "FAIL: $*" >&2; exit 1; }

# Force a valid scheduling outcome: the child exits before its first liveness poll.
(
  kill() { if [ "${1:-}" = -0 ]; then sleep 0.05; fi; builtin kill "$@"; }
  status=0
  run_logged_progress 'Immediate failure' 0 99 1 bash -c 'exit 42' >"$test_dir/failure" 2>&1 || status=$?
  [ "$status" -eq 42 ] || fail "a completed child returned $status instead of 42"
)

# Release the worker immediately before entering wait. A completed worker must
# be reaped immediately even when the next heartbeat is still far away.
for VERBOSE in 0 1; do
  (
    PROGRESS_POLL_SECONDS=2
    gate="$test_dir/completion-gate-$VERBOSE"
    mkfifo "$gate"
    released=0
    wait() {
      if [ "$released" -eq 0 ]; then
        released=1
        printf 'release\n' > "$gate"
        sleep .1
      fi
      builtin wait "$@"
    }
    started_ms="$(date +%s%3N)"
    status=0
    # The child Bash receives the FIFO path through its own positional argument.
    # shellcheck disable=SC2016
    run_with_progress 'Finishing before wait' bash -c 'read -r token < "$1"; exit 17' bash "$gate" >"$test_dir/completion-$VERBOSE" 2>&1 || status=$?
    elapsed_ms=$(( $(date +%s%3N) - started_ms ))
    [ "$status" -eq 17 ] || fail 'completion race lost the child exit status'
    [ "$elapsed_ms" -lt 1500 ] || fail "verbose=$VERBOSE: completed command waited ${elapsed_ms}ms for its heartbeat"
  )
done

for VERBOSE in 0 1; do
  run_logged_progress 'Flushing writes' 0 99 1 sleep 0.2 >"$test_dir/heartbeat"
  count="$(grep -c 'Flushing writes.*elapsed' "$test_dir/heartbeat" || true)"
  [ "$count" -ge 2 ] || fail "verbose=$VERBOSE: a silent command needs continuing elapsed-time updates"
  if grep -Eq '\[[0-9]+%\]' "$test_dir/heartbeat"; then
    fail 'elapsed time must not produce an overall percentage'
  fi
  status=0
  run_logged_progress 'Failed verification' 0 99 1 bash -c 'sleep .1; echo corrupt-image; exit 23' >"$test_dir/failed-verification" 2>&1 || status=$?
  [ "$status" -eq 23 ] || fail "verbose=$VERBOSE: verification failure status was lost"
  grep -q corrupt-image "$test_dir/failed-verification" || fail 'failed command output was lost'
done

printf 'image data\n' >"$test_dir/source"
copy_with_progress "$test_dir/source" "$test_dir/target" 0 99 'Copying image' >"$test_dir/copy"
cmp "$test_dir/source" "$test_dir/target" || fail 'copied contents differ'
grep -q '100%.*bytes.*B/s.*elapsed' "$test_dir/copy" || fail 'copy needs actual bytes, percentage, rate and elapsed time'
status=0
copy_with_progress "$test_dir/source" "$test_dir/missing/target" 0 99 'Failed copy' >"$test_dir/failed-copy" 2>&1 || status=$?
[ "$status" -ne 0 ] || fail 'failed copy succeeded'

for VERBOSE in 0 1; do
  worker() {
    printf '%s\n' "$BASHPID" >"$test_dir/worker-$VERBOSE"
    sleep 30 &
    printf '%s\n' "$!" >"$test_dir/descendant-$VERBOSE"
    wait
  }
  (
    trap 'stop_active_command; exit 143' TERM
    run_with_progress 'Cancelable command' worker
  ) >"$test_dir/cancellation-$VERBOSE" 2>&1 &
  supervisor=$!
  for attempt in {1..100}; do
    [ -s "$test_dir/descendant-$VERBOSE" ] && break
    sleep .01
  done
  [ -s "$test_dir/descendant-$VERBOSE" ] || fail 'cancellation worker did not start'
  kill -TERM "$supervisor"
  status=0
  wait "$supervisor" || status=$?
  [ "$status" -eq 143 ] || fail 'cancellation lost its exit status'
  for pid_file in "$test_dir/worker-$VERBOSE" "$test_dir/descendant-$VERBOSE"; do
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      state="$(sed -n 's/^State:[[:space:]]*\(.\).*/\1/p' "/proc/$pid/status" 2>/dev/null || true)"
      [ "$state" = Z ] || [ -z "$state" ] || fail "verbose=$VERBOSE: cancellation left process $pid running"
    fi
  done
done

# shellcheck source=/dev/null
. "$source_dir/telemetry.sh"
mkdir -p "$test_dir/reports"
printf keep >"$test_dir/reports/unrelated.json"
for run in {1..12}; do
  start_update_report "$test_dir/reports" "$source_dir" "$test_dir"
  phase_begin verification 'Verifying image' >/dev/null
  phase_end
  report_image candidate "$test_dir/source"
  finish_update_report 0 >/dev/null
done
count="$(find "$test_dir/reports" -name 'update-usb-*.json' | wc -l)"
[ "$count" -eq 10 ] || fail "retained $count reports instead of 10"
[ "$(cat "$test_dir/reports/unrelated.json")" = keep ] || fail 'retention touched unrelated files'
for report in "$test_dir"/reports/update-usb-*.json; do
  jq -e '.status == "completed" and .exit_status == 0 and (.phases | length) == 1 and .images.candidate.bytes == 11 and .target.free_bytes > 0 and .kernel != "" and .tools.cp != ""' "$report" >/dev/null || fail 'run report is incomplete'
done
start_update_report "$test_dir/reports" "$source_dir" "$test_dir"
phase_begin verification 'Verifying image' >/dev/null
failed_report="$UPDATE_REPORT_FILE"
finish_update_report 23 >/dev/null
jq -e '.status == "failed" and .exit_status == 23 and .phases[0].status == "failed"' "$failed_report" >/dev/null || fail 'failed active phase not recorded'

echo 'USB progress checks passed.'
