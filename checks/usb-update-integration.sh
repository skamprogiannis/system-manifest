#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329
set -euo pipefail

# Only the VM harness sets this flag. No device discovery or real USB labels are
# used by these tests; the integration disk belongs to the test driver.
[ "${USB_UPDATE_TEST_VM:-}" = 1 ] || {
  echo "Run this harness inside its NixOS test VM." >&2
  exit 1
}

export LC_ALL=C
VERBOSE=1
MODE=prebuild
FORCE_UPDATE=0
TIMINGS=()
MOUNT_POINT=/mnt
STAGE_DIR=/var/tmp/usb-update-test-stage
RUNTIME_DIR=/run/usb-update-test
PRESERVE_PREVIOUS_GENERATION=0
PREVIOUS_SYSTEM_TOPLEVEL=""
TARGET_SYSTEM_TOPLEVEL=""
TARGET_INIT_RELATIVE=""
TARGET_CONFIG_REVISION=""
EXPECTED_CONFIG_REVISION=""
UPDATE_USB_JQ=$(command -v jq)
mkdir -p "$RUNTIME_DIR/tmp"

# shellcheck source=/dev/null
source "$UPDATE_USB_SOURCE_DIR/phases.sh"
# shellcheck source=/dev/null
source "$UPDATE_USB_SOURCE_DIR/metadata.sh"
# shellcheck source=/dev/null
source "$UPDATE_USB_SOURCE_DIR/staging.sh"
# shellcheck source=/dev/null
source "$UPDATE_USB_SOURCE_DIR/squashfs.sh"
# shellcheck source=/dev/null
source "$UPDATE_USB_SOURCE_DIR/transaction.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  if (set -e; "$@"); then
    fail "Unexpected success: $*"
  fi
}

compress_store() {
  mksquashfs "$1" "$2" -noappend -no-progress -comp zstd \
    -Xcompression-level 1 -processors 2 -wildcards -e '.links/*' >/dev/null
}

set_profile() {
  local root="$1" system="$2"
  nix copy --no-check-sigs --to "$root" "$system"
  nix-env --store "$root" --profile "$root/nix/var/nix/profiles/system" --set "$system"
}

target_metadata_hash() {
  find "$MOUNT_POINT/nix/var/nix" -type f ! -name '*.lock' -print0 |
    sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}

fixture_tests() {
  local fixture_root original_image_hash original_shared_hash original_metadata_hash
  local generation_count available capacity_output closure_bytes expected_capacity
  fixture_root=$(mktemp -d /var/tmp/usb-update-fixtures.XXXXXX)
  MOUNT_POINT="$fixture_root/target"
  STAGE_DIR="$fixture_root/stage"
  mkdir -p "$MOUNT_POINT"
  truncate -s 768M "$fixture_root/target.ext4"
  mkfs.ext4 -q -F "$fixture_root/target.ext4"
  mount -o loop "$fixture_root/target.ext4" "$MOUNT_POINT"

  mkdir -p "$MOUNT_POINT/nix/var/nix/db"
  printf preserved > "$MOUNT_POINT/nix/var/nix/db/sentinel"
  prepare_generation_state
  [ "$(cat "$MOUNT_POINT/nix/var/nix/db/sentinel")" = preserved ] || fail "Invalid prior state was deleted before publication"
  rm "$MOUNT_POINT/nix/var/nix/db/sentinel"
  available=$(df -B1 --output=avail "$MOUNT_POINT" | tail -n1 | tr -d ' ')
  expect_failure require_free_space "$MOUNT_POINT" "$((available + 1))" 'test candidate'
  mkdir -p "$STAGE_DIR"
  printf unrelated > "$STAGE_DIR/sentinel"
  expect_failure prepare_stage_directory
  [ "$(cat "$STAGE_DIR/sentinel")" = unrelated ] || fail "Unowned staging contents were removed"
  rm "$STAGE_DIR/sentinel"

  set_profile "$MOUNT_POINT" "$FIXTURE_OLDEST"
  set_profile "$MOUNT_POINT" "$FIXTURE_OLD"
  compress_store "$MOUNT_POINT/nix/store" "$MOUNT_POINT/nix-store.squashfs"
  original_image_hash=$(sha256sum "$MOUNT_POINT/nix-store.squashfs" | cut -d' ' -f1)
  original_shared_hash=$(sha256sum "$FIXTURE_SHARED/payload" | cut -d' ' -f1)
  original_metadata_hash=$(target_metadata_hash)
  find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

  prepare_generation_state
  [ "$PRESERVE_PREVIOUS_GENERATION" = 1 ] || fail "Previous generation was discarded"
  [ "$PREVIOUS_SYSTEM_TOPLEVEL" = "$FIXTURE_OLD" ] || fail "Wrong rollback generation"
  prepare_stage_directory
  prepare_target_stage
  [ "$(findmnt -n -o FSTYPE --mountpoint "$STAGE_STORE")" = overlay ] || fail "Staging did not use OverlayFS"
  set_profile "$MOUNT_POINT" "$FIXTURE_NEW"
  TARGET_SYSTEM_TOPLEVEL="$FIXTURE_NEW"
  TARGET_INIT_RELATIVE="${FIXTURE_NEW#/nix/store/}/init"
  TARGET_CONFIG_REVISION=fixture-new
  DESIRED_SYSTEM_TOPLEVEL="$FIXTURE_NEW"
  closure_bytes=$(nix path-info --json --json-format 1 --recursive "$FIXTURE_NEW" "$FIXTURE_OLD" "$FIXTURE_OLDEST" | jq '[.[].narSize] | add')
  expected_capacity=$((closure_bytes * 3 / 5 + 1073741824))
  capacity_output=$(check_staging_capacity)
  [[ "$capacity_output" == *"Estimated additional staging requirement: $expected_capacity bytes."* ]] || fail "Capacity estimate treats present packages as missing"
  prune_usb_system_generations
  if mountpoint -q "$MOUNT_POINT/proc"; then fail "Target GC leaked its private proc mount"; fi
  generation_count=$(nix-env --store "$MOUNT_POINT" --profile "$MOUNT_POINT/nix/var/nix/profiles/system" --list-generations | wc -l)
  [ "$generation_count" -eq 2 ] || fail "Expected exactly two generations"
  [ -e "$STAGE_STORE/${FIXTURE_OLD#/nix/store/}/init" ] || fail "Rollback closure was collected"
  [ -e "$STAGE_STORE/${FIXTURE_NEW#/nix/store/}/init" ] || fail "New closure missing"
  [ ! -e "$STAGE_STORE/${FIXTURE_OLDEST#/nix/store/}" ] || fail "Oldest generation survived GC"
  [ ! -e "$STAGE_STORE/${FIXTURE_OBSOLETE#/nix/store/}" ] || fail "Obsolete dependency survived GC"
  [ "$(sha256sum "$MOUNT_POINT/nix-store.squashfs" | cut -d' ' -f1)" = "$original_image_hash" ] || fail "Compressed base changed"
  [ "$(sha256sum "$FIXTURE_SHARED/payload" | cut -d' ' -f1)" = "$original_shared_hash" ] || fail "Host store file changed"
  # An unchanged megabyte-sized dependency must remain in the compressed lower
  # layer rather than being copied to the writable upper layer.
  [ -z "$(find "$STAGE_DIR" -path "*/${FIXTURE_SHARED#/nix/store/}/payload" ! -path "$STAGE_STORE/*" ! -path '*/lower/*' -print -quit)" ] || fail "Unchanged dependency copied into the upper layer"
  compress_store "$STAGE_STORE" "$STAGE_DIR/candidate.squashfs"
  verify_image_closures "$STAGE_DIR/candidate.squashfs"
  # Preserve the expected init while corrupting a dependency: presence-only
  # checks must not accept this otherwise structurally valid squashfs.
  unsquashfs -no-progress -d "$STAGE_DIR/corrupt-store" "$STAGE_DIR/candidate.squashfs" >/dev/null
  chmod -R u+w "$STAGE_DIR/corrupt-store"
  printf corrupted > "$STAGE_DIR/corrupt-store/${FIXTURE_SHARED#/nix/store/}/payload"
  compress_store "$STAGE_DIR/corrupt-store" "$STAGE_DIR/corrupt-content.squashfs"
  expect_failure verify_image_closures "$STAGE_DIR/corrupt-content.squashfs"
  cp "$STAGE_STORE/${FIXTURE_SHARED#/nix/store/}/payload" "$STAGE_DIR/corrupt-store/${FIXTURE_SHARED#/nix/store/}/payload"
  printf corrupted > "$STAGE_DIR/corrupt-store/${FIXTURE_OLD#/nix/store/}/references"
  compress_store "$STAGE_DIR/corrupt-store" "$STAGE_DIR/corrupt-rollback.squashfs"
  PREVIOUS_SYSTEM_TOPLEVEL="$FIXTURE_NEW"
  expect_failure verify_image_closures "$STAGE_DIR/corrupt-rollback.squashfs"
  PREVIOUS_SYSTEM_TOPLEVEL="$FIXTURE_OLD"
  cp "$STAGE_DIR/candidate.squashfs" "$STAGE_DIR/broken.squashfs"
  truncate -s 128 "$STAGE_DIR/broken.squashfs"
  expect_failure verify_image_closures "$STAGE_DIR/broken.squashfs"
  detach_target_stage
  [ "$(target_metadata_hash)" = "$original_metadata_hash" ] || fail "Staging changed published Nix metadata"

  cp "$STAGE_DIR/candidate.squashfs" "$MOUNT_POINT/nix-store.squashfs.tmp"
  IMAGE_SHA256=$(sha256sum "$MOUNT_POINT/nix-store.squashfs.tmp" | cut -d' ' -f1)
  available=$(df -B1 --output=avail "$MOUNT_POINT" | tail -n1 | tr -d ' ')
  fallocate -l "$((available - 8388608))" "$MOUNT_POINT/space-pressure"
  expect_failure prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$STAGE_STATE"
  [ ! -e "$MOUNT_POINT/.update-usb-transaction" ] || fail "Insufficient space created a transaction"
  [ "$(target_metadata_hash)" = "$original_metadata_hash" ] || fail "Insufficient space changed published metadata"
  rm "$MOUNT_POINT/space-pressure"
  prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$STAGE_STATE"
  # A damaged candidate must leave both the current image and metadata intact.
  printf broken > "$MOUNT_POINT/nix-store.squashfs.tmp"
  expect_failure resume_usb_transaction
  [ "$(sha256sum "$MOUNT_POINT/nix-store.squashfs" | cut -d' ' -f1)" = "$original_image_hash" ] || fail "Corrupt candidate replaced current image"
  [ "$(target_metadata_hash)" = "$original_metadata_hash" ] || fail "Corrupt candidate replaced metadata"
  [ ! -e "$MOUNT_POINT/.update-usb-transaction" ] || fail "Rejected candidate blocks a fresh retry"
  cp "$STAGE_DIR/candidate.squashfs" "$MOUNT_POINT/nix-store.squashfs.tmp"
  prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$STAGE_STATE"

  # Boot installation is covered with real NixOS generations below. Tiny
  # fixtures exercise retry semantics without pretending their init is NixOS.
  install_target_bootloader() { touch "$MOUNT_POINT/bootloader-installed"; }
  transaction_checkpoint() { [ "$1" != after-image ] || exit 75; }
  expect_failure resume_usb_transaction
  [ "$(sha256sum "$MOUNT_POINT/nix-store.squashfs" | cut -d' ' -f1)" = "$IMAGE_SHA256" ] || fail "Image checkpoint was not reached"
  [ "$(target_metadata_hash)" = "$original_metadata_hash" ] || fail "Metadata published before image checkpoint"
  transaction_checkpoint() { [ "$1" != after-metadata ] || exit 75; }
  expect_failure resume_usb_transaction
  [ "$(profile_store_target "$MOUNT_POINT/nix/var/nix/profiles/system")" = "$FIXTURE_NEW" ] || fail "Metadata exchange did not publish new generation"
  [ ! -e "$MOUNT_POINT/bootloader-installed" ] || fail "Bootloader published before metadata checkpoint"
  transaction_checkpoint() { :; }
  resume_usb_transaction
  [ -e "$MOUNT_POINT/bootloader-installed" ] || fail "Retry did not finish bootloader publication"
  resume_usb_transaction
  cleanup_stage_mounts
  umount "$MOUNT_POINT"
  rm -rf -- "$fixture_root"
}

mount_target() {
  mkdir -p "$MOUNT_POINT"
  mount LABEL=usb-test-root "$MOUNT_POINT"
  mkdir -p "$MOUNT_POINT/boot"
  mount LABEL=USBTESTBOOT "$MOUNT_POINT/boot"
}

unmount_target() {
  sync -f "$MOUNT_POINT"
  umount -R "$MOUNT_POINT"
}

initial_install() {
  # /dev/vda is an empty image created specifically by this test's QEMU driver.
  [ "$(blockdev --getsize64 /dev/vda)" = 3221225472 ] || fail "Unexpected test disk size"
  sgdisk --zap-all --new=1:0:+128M --typecode=1:ef00 --new=2:0:0 --typecode=2:8300 /dev/vda
  udevadm settle
  mkfs.vfat -n USBTESTBOOT /dev/vda1
  mkfs.ext4 -q -F -L usb-test-root /dev/vda2
  mount_target
  prepare_generation_state
  [ "$PRESERVE_PREVIOUS_GENERATION" = 0 ] || fail "First installation unexpectedly reused a generation"
  prepare_stage_directory
  prepare_target_stage
  nixos-install --system "$OLD_SYSTEM" --root "$MOUNT_POINT" --no-root-passwd --no-channel-copy --no-bootloader
  TARGET_SYSTEM_TOPLEVEL="$OLD_SYSTEM"
  TARGET_INIT_RELATIVE="${OLD_SYSTEM#/nix/store/}/init"
  TARGET_CONFIG_REVISION=usb-update-old
  prune_usb_system_generations
  compress_store "$STAGE_STORE" "$STAGE_DIR/candidate.squashfs"
  verify_image_closures "$STAGE_DIR/candidate.squashfs"
  detach_target_stage
  cp "$STAGE_DIR/candidate.squashfs" "$MOUNT_POINT/nix-store.squashfs.tmp"
  sync -f "$MOUNT_POINT/nix-store.squashfs.tmp"
  IMAGE_SHA256=$(sha256sum "$MOUNT_POINT/nix-store.squashfs.tmp" | cut -d' ' -f1)
  prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$STAGE_STATE"
  cleanup_stage_mounts
  resume_usb_transaction
  unmount_target
}

prepare_update() {
  local published_profile
  mount_target
  published_profile=$(profile_store_target "$MOUNT_POINT/nix/var/nix/profiles/system")
  [ "$published_profile" = "$OLD_SYSTEM" ] || fail "Unexpected initial generation"
  prepare_generation_state
  prepare_stage_directory
  prepare_target_stage
  nixos-install --system "$NEW_SYSTEM" --root "$MOUNT_POINT" --no-root-passwd --no-channel-copy --no-bootloader
  TARGET_SYSTEM_TOPLEVEL="$NEW_SYSTEM"
  TARGET_INIT_RELATIVE="${NEW_SYSTEM#/nix/store/}/init"
  TARGET_CONFIG_REVISION=usb-update-new
  prune_usb_system_generations
  compress_store "$STAGE_STORE" "$STAGE_DIR/candidate.squashfs"
  verify_image_closures "$STAGE_DIR/candidate.squashfs"
  detach_target_stage
  [ "$(profile_store_target "$MOUNT_POINT/nix/var/nix/profiles/system")" = "$OLD_SYSTEM" ] || fail "Prepared update changed the published profile"
  cp "$STAGE_DIR/candidate.squashfs" "$MOUNT_POINT/nix-store.squashfs.tmp"
  sync -f "$MOUNT_POINT/nix-store.squashfs.tmp"
  IMAGE_SHA256=$(sha256sum "$MOUNT_POINT/nix-store.squashfs.tmp" | cut -d' ' -f1)
  prepare_usb_transaction "$MOUNT_POINT/nix-store.squashfs.tmp" "$STAGE_STATE"
  cleanup_stage_mounts
  unmount_target
}

resume_update() {
  local stop_after="$1"
  mount_target
  transaction_checkpoint() {
    if [ "$1" = "$stop_after" ]; then
      exit 75
    fi
  }
  if [ "$stop_after" = complete ]; then
    resume_usb_transaction
  else
    local status=0
    (resume_usb_transaction) || status=$?
    [ "$status" -eq 75 ] || fail "Expected interruption at $stop_after, got $status"
  fi
  unmount_target
}

select_rollback() {
  mount_target
  # GRUB's first submenu contains the retained generations; selecting the old
  # generation tests the actual existing menu entry and its kernel/initrd paths.
  grep -Fq "$OLD_SYSTEM/init" "$MOUNT_POINT/boot/grub/grub.cfg" || fail "Rollback GRUB entry missing"
  sed -i 's/^[[:space:]]*set default=.*/set default="1>1"/' "$MOUNT_POINT/boot/grub/grub.cfg"
  grep -Fq 'set default="1>1"' "$MOUNT_POINT/boot/grub/grub.cfg" || fail "Rollback boot selection was not written"
  unmount_target
}

case "${1:-}" in
  fixtures) fixture_tests ;;
  initial) initial_install ;;
  prepare) prepare_update ;;
  after-image|after-metadata) resume_update "$1" ;;
  finish) resume_update complete ;;
  rollback) select_rollback ;;
  *) fail "Unknown integration step: ${1:-}" ;;
esac
