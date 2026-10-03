#!/usr/bin/env bash
# Shared variables and stub functions are consumed by the sourced updater.
# shellcheck disable=SC2034,SC2329
set -euo pipefail

lib_dir="${1:?updater source directory required}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
export LC_ALL=C
export PROGRESS_POLL_SECONDS=0.05

# shellcheck source=/dev/null
source "$lib_dir/phases.sh"
# shellcheck source=/dev/null
source "$lib_dir/squashfs.sh"
# shellcheck source=/dev/null
source "$lib_dir/staging.sh"
# shellcheck source=/dev/null
source "$lib_dir/transaction.sh"
# shellcheck source=/dev/null
source "$lib_dir/cleanup.sh"
# shellcheck source=/dev/null
source "$lib_dir/telemetry.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

VERBOSE=0
MODE=prebuild
STAGE_DIR="$test_root/stage"
MOUNT_POINT="$test_root/root"
RUNTIME_DIR="$test_root/run"
UPDATE_USB_JQ="${UPDATE_USB_JQ:-jq}"
mkdir -p "$MOUNT_POINT/nix/var/nix/profiles" "$RUNTIME_DIR"

mkdir -p "$STAGE_DIR"
printf 'valuable\n' > "$STAGE_DIR/unrelated"
if prepare_stage_directory; then
  echo 'Unmarked nonempty staging directory was accepted' >&2
  exit 1
fi
test "$(cat "$STAGE_DIR/unrelated")" = valuable
rm -rf "$STAGE_DIR"
prepare_stage_directory
test -f "$STAGE_DIR/.update-usb-workspace"
printf 'disposable\n' > "$STAGE_DIR/old"
prepare_stage_directory
test ! -e "$STAGE_DIR/old"

(
  # This fixture deliberately leaves the parent's staging path unchanged.
  # shellcheck disable=SC2030
  STAGE_DIR="$test_root/stage with spaces"
  prepare_stage_directory
  printf 'mounted-data\n' > "$STAGE_DIR/sentinel"
  raw_stage="${STAGE_DIR// /\\x20}"
  raw_mount="$raw_stage/extra"
  # findmnt --raw hex-escapes spaces even though the filesystem path is literal.
  findmnt() { printf '%s\n' "$raw_mount"; }
  stage_has_mounts || fail 'escaped mount below a custom staging path was missed'
  if prepare_stage_directory; then fail 'mounted custom stage was recreated'; fi
  test "$(cat "$STAGE_DIR/sentinel")" = mounted-data
  cleanup_stage_mounts() { :; }
  if remove_update_stage; then fail 'mounted custom stage was deleted during cleanup'; fi
  test "$(cat "$STAGE_DIR/sentinel")" = mounted-data
  raw_mount="$raw_stage"
  stage_has_mounts || fail 'mount exactly at the custom staging path was missed'
  raw_mount="$raw_stage-other/extra"
  if stage_has_mounts; then fail 'a sibling mount was treated as part of staging'; fi
)

# The ordinary staging fixture remains active outside the isolated space-path test.
# shellcheck disable=SC2031
if require_free_space "$STAGE_DIR" 999999999999999999 test; then
  echo 'Impossible capacity request was accepted' >&2
  exit 1
fi

# A new installation must not destroy the published database during preflight.
mkdir -p "$MOUNT_POINT/nix/var/nix/db"
printf 'previous\n' > "$MOUNT_POINT/nix/var/nix/db/sentinel"
prepare_generation_state
test "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = previous

TARGET_SYSTEM_TOPLEVEL=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-new-system
PREVIOUS_SYSTEM_TOPLEVEL=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-old-system
TARGET_CONFIG_REVISION=test-revision
TARGET_INIT_RELATIVE="${TARGET_SYSTEM_TOPLEVEL#/nix/store/}/init"
ln -s "$PREVIOUS_SYSTEM_TOPLEVEL" "$MOUNT_POINT/nix/var/nix/profiles/system-1-link"
ln -s system-1-link "$MOUNT_POINT/nix/var/nix/profiles/system"
mkdir -p "$test_root/new-state/profiles" "$test_root/new-state/db"
ln -s "$TARGET_SYSTEM_TOPLEVEL" "$test_root/new-state/profiles/system-2-link"
ln -s system-2-link "$test_root/new-state/profiles/system"
printf 'new-state\n' > "$test_root/new-state/db/sentinel"
printf 'old-image\n' > "$MOUNT_POINT/nix-store.squashfs"
printf 'new-image\n' > "$MOUNT_POINT/nix-store.squashfs.tmp"
IMAGE_SHA256="$(image_checksum "$MOUNT_POINT/nix-store.squashfs.tmp")"
# The VM check uses real SquashFS; this fixture isolates durable ordering.
verify_squashfs_contains_system() { test -s "$1"; }
install_target_bootloader() {
  test "$(cat "$MOUNT_POINT/nix-store.squashfs")" = new-image
  test "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = new-state
  printf '%s\n' "$TARGET_SYSTEM_TOPLEVEL" > "$MOUNT_POINT/boot-selection"
}
prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$test_root/new-state"
test "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = previous
transaction_checkpoint() { [ "$1" != after-image ]; }
if resume_usb_transaction; then
  echo 'Expected interruption after image publication' >&2
  exit 1
fi
test "$(cat "$MOUNT_POINT/nix-store.squashfs")" = new-image
test "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = previous
test ! -e "$MOUNT_POINT/boot-selection"

transaction_checkpoint() { [ "$1" != after-metadata ]; }
if resume_usb_transaction; then
  echo 'Expected interruption after metadata publication' >&2
  exit 1
fi
test "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = new-state
test ! -e "$MOUNT_POINT/boot-selection"
# Repeating this interruption must not exchange metadata back to the old state.
if resume_usb_transaction; then exit 1; fi
test "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = new-state
transaction_checkpoint() { :; }
resume_usb_transaction
test "$(cat "$MOUNT_POINT/boot-selection")" = "$TARGET_SYSTEM_TOPLEVEL"
test ! -e "$MOUNT_POINT/.update-usb-transaction"
test ! -e "$MOUNT_POINT/nix/var/nix.update-usb-next"

# Corrupt copies must not advance the published state or boot selection.
printf 'replacement\n' > "$MOUNT_POINT/nix-store.squashfs.tmp"
IMAGE_SHA256="$(printf 'expected\n' | sha256sum | cut -d ' ' -f1)"
prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$test_root/new-state"
if resume_usb_transaction; then
  echo 'Corrupt image was published' >&2
  exit 1
fi
test "$(cat "$MOUNT_POINT/nix-store.squashfs")" = new-image
test ! -e "$MOUNT_POINT/nix-store.squashfs.tmp"
test ! -e "$MOUNT_POINT/nix/var/nix.update-usb-next"
test ! -e "$MOUNT_POINT/.update-usb-transaction"
test "$(cat "$MOUNT_POINT/boot-selection")" = "$TARGET_SYSTEM_TOPLEVEL"

# A failed transfer must allow a subsequent update without manual recovery.
printf 'new-image\n' > "$MOUNT_POINT/nix-store.squashfs.tmp"
IMAGE_SHA256="$(image_checksum "$MOUNT_POINT/nix-store.squashfs.tmp")"
prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$test_root/new-state"
resume_usb_transaction
test ! -e "$MOUNT_POINT/.update-usb-transaction"

(
  MOUNT_POINT="$test_root/invalid-metadata"
  mkdir -p "$MOUNT_POINT/nix/var/nix/db"
  printf 'old-image\n' > "$MOUNT_POINT/nix-store.squashfs"
  printf 'previous-state\n' > "$MOUNT_POINT/nix/var/nix/db/sentinel"
  printf 'new-image\n' > "$MOUNT_POINT/nix-store.squashfs.tmp"
  IMAGE_SHA256="$(image_checksum "$MOUNT_POINT/nix-store.squashfs.tmp")"
  prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$test_root/new-state"
  transaction_id="$(jq -r .id "$TRANSACTION_DIR/transaction.json")"

  printf 'wrong-transaction\n' > "$PENDING_STATE/.update-usb-transaction-id"
  if resume_usb_transaction; then fail 'mismatched metadata identity was accepted'; fi
  test "$(cat "$MOUNT_POINT/nix-store.squashfs")" = old-image
  test "$(cat "$PUBLISHED_STATE/db/sentinel")" = previous-state
  test -f "$CANDIDATE_SQUASHFS"
  test ! -e "$MOUNT_POINT/boot-selection"

  printf '%s\n' "$transaction_id" > "$PENDING_STATE/.update-usb-transaction-id"
  ln -sfn "$PREVIOUS_SYSTEM_TOPLEVEL" "$PENDING_STATE/profiles/system"
  if resume_usb_transaction; then fail 'mismatched metadata profile was accepted'; fi
  test "$(cat "$MOUNT_POINT/nix-store.squashfs")" = old-image
  test "$(cat "$PUBLISHED_STATE/db/sentinel")" = previous-state
  test -f "$CANDIDATE_SQUASHFS"
  test ! -e "$MOUNT_POINT/boot-selection"
)

(
  MOUNT_POINT="$test_root/interrupted-record"
  mkdir -p "$MOUNT_POINT/nix/var/nix"
  printf 'published-image\n' > "$MOUNT_POINT/nix-store.squashfs"
  transaction_paths

  # Interruption after the ownership marker is removed leaves an empty directory.
  mkdir "$TRANSACTION_DIR"
  resume_usb_transaction
  test ! -e "$TRANSACTION_DIR"
  test "$(cat "$FINAL_SQUASHFS")" = published-image

  # Preparation may stop before the JSON record is made durable.
  mkdir "$TRANSACTION_DIR" "$PENDING_STATE"
  printf 'update-usb-v1\n' > "$TRANSACTION_DIR/owner"
  : > "$TRANSACTION_DIR/transaction.json.tmp"
  printf 'partial-image\n' > "$CANDIDATE_SQUASHFS"
  printf 'partial-state\n' > "$PENDING_STATE/sentinel"
  resume_usb_transaction
  test ! -e "$TRANSACTION_DIR"
  test ! -e "$PENDING_STATE"
  test ! -e "$CANDIDATE_SQUASHFS"
  test "$(cat "$FINAL_SQUASHFS")" = published-image
)

(
  MOUNT_POINT="$test_root/pending-cleanup"
  mkdir -p "$MOUNT_POINT/.update-usb-transaction"
  printf 'published-image\n' > "$MOUNT_POINT/nix-store.squashfs"
  printf 'pending-image\n' > "$MOUNT_POINT/nix-store.squashfs.tmp"
  printf '{"pending":true}\n' > "$MOUNT_POINT/.update-usb-transaction/transaction.json"
  remove_pending_squashfs
  test "$(cat "$MOUNT_POINT/nix-store.squashfs.tmp")" = pending-image
  test -s "$MOUNT_POINT/.update-usb-transaction/transaction.json"
  rm -r "$MOUNT_POINT/.update-usb-transaction"
  remove_pending_squashfs
  test ! -e "$MOUNT_POINT/nix-store.squashfs.tmp"
  test "$(cat "$MOUNT_POINT/nix-store.squashfs")" = published-image
)

(
  MOUNT_POINT="$test_root/no-op"
  mkdir -p "$MOUNT_POINT/nix/var/nix/profiles" "$MOUNT_POINT/boot/grub"
  DESIRED_SYSTEM_TOPLEVEL="$TARGET_SYSTEM_TOPLEVEL"
  DESIRED_INIT_RELATIVE="${DESIRED_SYSTEM_TOPLEVEL#/nix/store/}/init"
  EXPECTED_CONFIG_REVISION=test-revision
  FORCE_UPDATE=0
  # Image contents are fixture lines; profile and GRUB parsing remain real.
  unsquashfs() { [ "$1" = -cat ] && grep -Fxq -- "$3" "$2"; }
  printf '%s\n' "$DESIRED_INIT_RELATIVE" > "$MOUNT_POINT/nix-store.squashfs"
  ln -s "$DESIRED_SYSTEM_TOPLEVEL" "$MOUNT_POINT/nix/var/nix/profiles/system"
  printf ' linux /kernel init=%s/init quiet\n' "$DESIRED_SYSTEM_TOPLEVEL" > "$MOUNT_POINT/boot/grub/grub.cfg"
  status=0
  skip_if_existing_squashfs_is_current || status=$?
  [ "$status" -eq 1 ] || fail 'matching image, profile and boot entry did not skip'

  ln -sfn "$PREVIOUS_SYSTEM_TOPLEVEL" "$MOUNT_POINT/nix/var/nix/profiles/system"
  skip_if_existing_squashfs_is_current || fail 'stale profile incorrectly skipped update'
  ln -sfn "$DESIRED_SYSTEM_TOPLEVEL" "$MOUNT_POINT/nix/var/nix/profiles/system"
  printf ' linux /kernel init=%s/init quiet\n' "$PREVIOUS_SYSTEM_TOPLEVEL" > "$MOUNT_POINT/boot/grub/grub.cfg"
  skip_if_existing_squashfs_is_current || fail 'stale boot entry incorrectly skipped update'
  printf ' linux /kernel init=%s/init quiet\n' "$DESIRED_SYSTEM_TOPLEVEL" > "$MOUNT_POINT/boot/grub/grub.cfg"
  printf '%s/init\n' "${PREVIOUS_SYSTEM_TOPLEVEL#/nix/store/}" > "$MOUNT_POINT/nix-store.squashfs"
  skip_if_existing_squashfs_is_current || fail 'stale image incorrectly skipped update'
  printf '%s\n' "$DESIRED_INIT_RELATIVE" > "$MOUNT_POINT/nix-store.squashfs"
  mkdir "$MOUNT_POINT/.update-usb-transaction"
  skip_if_existing_squashfs_is_current || fail 'pending transaction incorrectly skipped update'
  rmdir "$MOUNT_POINT/.update-usb-transaction"
  FORCE_UPDATE=1
  skip_if_existing_squashfs_is_current || fail 'forced update incorrectly skipped'
)

# Cleanup must preserve the failing phase before starting its own phase, and
# remove in-place staging while the target root is still mounted.
cleanup_fixture="$test_root/in-place-cleanup"
mkdir -p "$cleanup_fixture"
(
  MODE=in-place
  MOUNT_POINT="$cleanup_fixture/root"
  STAGE_DIR="$MOUNT_POINT/.update-usb-stage"
  RUNTIME_DIR="$cleanup_fixture/runtime"
  UPDATE_USB_TMP_DIR="$RUNTIME_DIR/tmp"
  mkdir -p "$STAGE_DIR" "$UPDATE_USB_TMP_DIR"
  printf mounted > "$cleanup_fixture/root-mounted"
  printf '%s\n' "$STAGE_DIR" > "$RUNTIME_DIR/stage-path"
  start_update_report "$cleanup_fixture/reports" "$lib_dir" "$MOUNT_POINT"
  phase_begin verifying-transfer 'Verifying complete USB image checksum'
  CANCELED=0
  WORKSPACE_PREPARED=1
  STAGE_PREPARED=1
  CLOSE_MAPPER_ON_CLEANUP=1
  TIMINGS=()

  stop_active_child() { printf 'stop-child\n' >> "$cleanup_fixture/order"; }
  detach_target_stage() {
    test -f "$cleanup_fixture/root-mounted" || return 1
    test -d "$STAGE_DIR" || return 1
    jq -e '.phases[0].name == "verifying-transfer" and .phases[0].status == "failed"' "$UPDATE_REPORT_FILE" >/dev/null || return 1
    printf 'detach-stage\n' >> "$cleanup_fixture/order"
  }
  remove_update_stage() {
    test -f "$cleanup_fixture/root-mounted" || return 1
    rm -r "$STAGE_DIR" || return 1
    printf 'remove-stage\n' >> "$cleanup_fixture/order"
  }
  cleanup_mount_tree() {
    test ! -e "$STAGE_DIR" || return 1
    test -f "$cleanup_fixture/root-mounted" || return 1
    rm "$cleanup_fixture/root-mounted" || return 1
    printf 'unmount-root\n' >> "$cleanup_fixture/order"
  }
  close_usb_mapper() {
    test ! -e "$cleanup_fixture/root-mounted" || return 1
    printf 'close-mapper\n' >> "$cleanup_fixture/order"
  }
  cleanup 37
) > "$cleanup_fixture/output" 2>&1 &
cleanup_pid=$!
status=0
wait "$cleanup_pid" || status=$?
[ "$status" -eq 37 ] || { cat "$cleanup_fixture/output" >&2; fail "cleanup lost original exit status: $status"; }
printf 'stop-child\ndetach-stage\nremove-stage\nunmount-root\nclose-mapper\n' > "$cleanup_fixture/expected-order"
cmp "$cleanup_fixture/order" "$cleanup_fixture/expected-order" || fail 'in-place cleanup order is unsafe'
test ! -e "$cleanup_fixture/runtime/stage-path"
test ! -e "$cleanup_fixture/runtime/tmp"
jq -e '.status == "failed" and .exit_status == 37 and (.phases | length) == 2 and .phases[0].status == "failed" and .phases[1].name == "cleanup" and .phases[1].status == "completed"' "$cleanup_fixture"/reports/update-usb-*.json >/dev/null || fail 'failed phase and cleanup were not reported separately'

printf 'USB updater unit checks passed\n'
