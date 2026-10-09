#!/usr/bin/env bash
# Helpers and shared variables are consumed by the sourced implementation.
# Fixture subshells isolate simulated clocks and progress state.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329
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

# Exercise actual scheduler defaults without waiting a minute.
for VERBOSE in 0 1; do
  (
    unset PROGRESS_POLL_SECONDS
    sleep() { printf '%s\n' "$1" >>"$test_dir/polls-$VERBOSE"; command sleep .02; }
    run_with_progress 'Default cadence' bash -c 'sleep .08' >"$test_dir/cadence-$VERBOSE"
    expected=60
    if [ "$VERBOSE" -eq 1 ]; then expected=10; fi
    [ "$(head -n 1 "$test_dir/polls-$VERBOSE")" = "$expected" ] || fail "verbose=$VERBOSE: wrong reporting cadence"
  )
done

# Exercise rendering with a real pseudo-terminal.
export USB_PROGRESS_TEST_SOURCE="$source_dir"
export PROGRESS_POLL_SECONDS=.02
cat >"$test_dir/terminal-test.sh" <<'TERMINAL'
source "$USB_PROGRESS_TEST_SOURCE/phases.sh"
VERBOSE=0
run_with_progress 'Terminal heartbeat' sleep .1
TERMINAL
script -q -e -c "bash '$test_dir/terminal-test.sh'" "$test_dir/terminal" >/dev/null
terminal_text="$(cat "$test_dir/terminal")"
[[ "$terminal_text" == *$'\033[2K'* ]] || fail 'terminal progress appended lines instead of refreshing'
[[ "$terminal_text" == *'finished in'* ]] || fail 'terminal progress lost completion'
if grep -q $'\033' "$test_dir/heartbeat"; then fail 'redirected output contains terminal escapes'; fi
export PROGRESS_POLL_SECONDS=.05

VERBOSE=0
printf 'image data\n' >"$test_dir/source"
copy_with_progress "$test_dir/source" "$test_dir/target" 0 99 'Copying image' >"$test_dir/copy"
cmp "$test_dir/source" "$test_dir/target" || fail 'copied contents differ'
grep -q '100%.*copy finished.*elapsed' "$test_dir/copy" || fail 'copy lost measured progress or completion'
VERBOSE=1 copy_with_progress "$test_dir/source" "$test_dir/target" 0 99 'Detailed copy' >"$test_dir/verbose-copy"
grep -q '100%.*bytes.*B/s.*elapsed' "$test_dir/verbose-copy" || fail 'verbose copy lost byte counts and throughput'
status=0
copy_with_progress "$test_dir/source" "$test_dir/missing/target" 0 99 'Failed copy' >"$test_dir/failed-copy" 2>&1 || status=$?
[ "$status" -ne 0 ] || fail 'failed copy succeeded'

# Include an aligned tail smaller than dd's 4 MiB block and an existing candidate.
dd if=/dev/urandom of="$test_dir/direct-source" bs=4096 count=1025 status=none
truncate -s 8M "$test_dir/direct-target"
(
  dd() {
    [ "$(stat -c %s "$test_dir/direct-target")" -eq 0 ] || fail 'preallocation falsely reports a completed copy'
    command dd "$@"
  }
  copy_usb_image_with_progress "$test_dir/direct-source" "$test_dir/direct-target"
) >"$test_dir/direct-copy"
cmp "$test_dir/direct-source" "$test_dir/direct-target" || fail 'direct image copy changed data or retained a stale tail'
grep -q '100%.*copy finished' "$test_dir/direct-copy" || fail 'direct image copy lost completion'
# Reject bad alignment before touching the destination.
printf preserved >"$test_dir/direct-target"
status=0
copy_usb_image_with_progress "$test_dir/source" "$test_dir/direct-target" >"$test_dir/unaligned-copy" 2>&1 || status=$?
[ "$status" -ne 0 ] || fail 'unaligned image copy succeeded'
[ "$(cat "$test_dir/direct-target")" = preserved ] || fail 'invalid image overwrote destination'
# Allocation failure must stop the writer, not fall back and hide storage errors.
(
  fallocate() { return 28; }
  dd() { touch "$test_dir/unexpected-write"; }
  status=0
  copy_usb_image_with_progress "$test_dir/direct-source" "$test_dir/direct-target" >"$test_dir/allocation-failure" 2>&1 || status=$?
  [ "$status" -eq 28 ] || fail 'image allocation failure status was lost'
  [ ! -e "$test_dir/unexpected-write" ] || fail 'writer ran after allocation failed'
)

# Buffered file growth cannot predict durable transfer time. Completion is
# separate from reaching the expected size because I/O may still be finishing.
(
  date() { case "$1" in +%s%3N) printf '100000\n' ;; +%s) printf '100\n' ;; esac; }
  PROGRESS_COPY_TARGET="$test_dir/partial-copy"
  PROGRESS_COPY_BYTES=1000
  truncate -s 250 "$PROGRESS_COPY_TARGET"
  copy_progress 'Measured copy' 90000 >"$test_dir/copy-eta"
  grep -q '25%.*elapsed 10s' "$test_dir/copy-eta" || fail 'copy lost measured progress'
  if grep -q 'remaining for copy' "$test_dir/copy-eta"; then fail 'buffered growth invented a copy ETA'; fi
  truncate -s 0 "$PROGRESS_COPY_TARGET"
  copy_progress 'Starting copy' 100000 | grep -q '0%.*elapsed' || fail 'zero throughput lost copy progress'
  truncate -s 1000 "$PROGRESS_COPY_TARGET"
  copy_progress 'Buffered copy' 90000 | grep -q 'finishing copy' || fail 'full file size claimed completion early'
  PROGRESS_COMMAND_DONE=1 copy_progress 'Completed copy' 90000 | grep -q 'copy finished' || fail 'completed copy lacks completion status'
  PHASE_ESTIMATE_SECONDS=60
  PHASE_STARTED_AT=80
  command_progress 'Second command in phase' 95000 | grep -q 'phase about 40s remaining (previous run)' || fail 'phase ETA restarted for a later command'
  PHASE_STARTED_AT=20
  command_progress 'Slower phase' 95000 | grep -q 'taking longer.*remaining time unknown' || fail 'overrun invented a zero-second ETA'
  PHASE_ESTIMATE_SECONDS=''
  command_progress 'First run' 95000 | grep -q 'running; elapsed' || fail 'first run lost elapsed time'
)

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

# Cancellation exits while copy_with_progress locals are still in scope.
# Exercise the real EXIT cleanup rather than unwinding the copy function first.
cat >"$test_dir/cancel-copy.sh" <<'CANCEL_COPY'
set -euo pipefail
source "$1/phases.sh"
source "$1/cleanup.sh"
RUNTIME_DIR="$2/runtime"
MOUNT_POINT="$RUNTIME_DIR/root"
mkdir -p "$MOUNT_POINT" "$RUNTIME_DIR/tmp"
UPDATE_USB_TMP_DIR="$RUNTIME_DIR/tmp"
CURRENT_PHASE=copy
CANCELED=0
WORKSPACE_PREPARED=1
CLOSE_MAPPER_ON_CLEANUP=0
phase_begin() { :; }
phase_end() { :; }
finish_update_report() { :; }
cleanup_mount_tree() { :; }
cp() { kill -TERM "$supervisor"; sleep 30; }
supervisor=$$
trap 'cleanup "$?"' EXIT
trap 'cancel_update TERM' TERM
printf data > "$RUNTIME_DIR/source"
copy_with_progress "$RUNTIME_DIR/source" "$MOUNT_POINT/target" 0 100 'Copying image'
CANCEL_COPY
status=0
bash "$test_dir/cancel-copy.sh" "$source_dir" "$test_dir" >"$test_dir/cancel-copy" 2>&1 || status=$?
[ "$status" -eq 143 ] || fail 'copy cleanup lost cancellation status'
grep -q 'Unmounting target filesystems.*finished in' "$test_dir/cancel-copy" || fail 'copy cleanup lost completion'
if grep -q 'Unmounting target filesystems.*%' "$test_dir/cancel-copy"; then
  fail 'cleanup inherited copy progress from interrupted command'
fi

# shellcheck source=/dev/null
. "$source_dir/telemetry.sh"
# Completed phases in an interrupted run remain useful. Failed phases, corrupt
# reports, and timings from a different storage path must not supply an ETA.
(
  MODE=prebuild
  STAGE_DIR="$test_dir/eta-stage"
  MOUNT_POINT="$test_dir/eta-usb"
  UPDATE_REPORT_DIRECTORY="$test_dir/history"
  UPDATE_REPORT_TARGET_UUID=test-usb-uuid
  mkdir -p "$UPDATE_REPORT_DIRECTORY" "$STAGE_DIR" "$MOUNT_POINT"
  touch "$MOUNT_POINT/nix-store.squashfs"
  CURRENT_PHASE=installing-system
  context="$(phase_storage_context)"
  jq -n --arg storage "$context" '{mode: "prebuild", target: {uuid: "test-usb-uuid"}, status: "canceled", phases: [{name: "installing-system", status: "completed", seconds: 510, storage: $storage}]}' >"$UPDATE_REPORT_DIRECTORY/update-usb-1.json"
  UPDATE_REPORT_FILE="$UPDATE_REPORT_DIRECTORY/update-usb-2.json"
  jq '.phases[0].seconds = 999' "$UPDATE_REPORT_DIRECTORY/update-usb-1.json" >"$UPDATE_REPORT_FILE"
  phase_begin installing-system 'Installing test system' >/dev/null
  [ "$PHASE_ESTIMATE_SECONDS" = 510 ] || fail 'completed phase history was not loaded or current run was included'
  jq '.phases[0].status = "failed"' "$UPDATE_REPORT_FILE" >"$UPDATE_REPORT_DIRECTORY/update-usb-3.json"
  printf broken >"$UPDATE_REPORT_DIRECTORY/update-usb-4.json"
  cat "$UPDATE_REPORT_FILE" "$UPDATE_REPORT_FILE" >"$UPDATE_REPORT_DIRECTORY/update-usb-5.json"
  [ "$(previous_phase_seconds installing-system "$context")" = 510 ] || fail 'failed/corrupt/multiple-document history replaced usable timing'
  phase_begin installing-system 'Installing with malformed recent history' >/dev/null
  [ "$PHASE_ESTIMATE_SECONDS" = 510 ] || fail 'multiple estimates reached progress arithmetic'
  UPDATE_REPORT_TARGET_UUID=other-usb-uuid
  [ -z "$(previous_phase_seconds installing-system "$context")" ] || fail 'another USB supplied an ETA'
  UPDATE_REPORT_TARGET_UUID=test-usb-uuid
  touch "$STAGE_DIR/base.squashfs"
  phase_begin installing-system 'Installing test system from SSD cache' >/dev/null
  [ -z "$PHASE_ESTIMATE_SECONDS" ] || fail 'USB reads and SSD reads shared an ETA'
  rm "$STAGE_DIR/base.squashfs"
  STAGE_DIR="$test_dir/other-stage"
  phase_begin installing-system 'Installing on another staging filesystem' >/dev/null
  [ -z "$PHASE_ESTIMATE_SECONDS" ] || fail 'another staging location supplied an ETA'
)

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
  jq -e '.status == "completed" and .exit_status == 0 and (.phases | length) == 1 and .images.candidate.bytes == 11 and .target.free_bytes > 0 and .kernel != "" and .tools.cp != "" and (.phases[0].storage | type) == "string"' "$report" >/dev/null || fail 'run report is incomplete'
done
start_update_report "$test_dir/reports" "$source_dir" "$test_dir"
phase_begin verification 'Verifying image' >/dev/null
failed_report="$UPDATE_REPORT_FILE"
finish_update_report 23 >/dev/null
jq -e '.status == "failed" and .exit_status == 23 and .phases[0].status == "failed"' "$failed_report" >/dev/null || fail 'failed active phase not recorded'

echo 'USB progress checks passed.'
