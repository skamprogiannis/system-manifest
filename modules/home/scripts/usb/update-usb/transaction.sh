#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016

transaction_paths() {
  TRANSACTION_DIR="$MOUNT_POINT/.update-usb-transaction"
  PENDING_STATE="$MOUNT_POINT/nix/var/nix.update-usb-next"
  PUBLISHED_STATE="$MOUNT_POINT/nix/var/nix"
  CANDIDATE_SQUASHFS="$MOUNT_POINT/nix-store.squashfs.tmp"
  FINAL_SQUASHFS="$MOUNT_POINT/nix-store.squashfs"
}

image_checksum() {
  sha256sum -- "$1" | cut -d ' ' -f1
}

verify_image_checksum() {
  local image="$1" expected="$2" actual
  actual="$(image_checksum "$image")" || return 1
  if [ "$actual" != "$expected" ]; then
    echo "Error: squashfs checksum mismatch: $image" >&2
    return 1
  fi
}

transaction_checkpoint() {
  # Test harnesses replace this hook to interrupt between durable steps.
  : "$1"
}

transaction_is_owned() {
  [ -d "$TRANSACTION_DIR" ] && [ ! -L "$TRANSACTION_DIR" ] \
    && [ "$(stat -c %u "$TRANSACTION_DIR")" = "$EUID" ] \
    && [ "$(cat "$TRANSACTION_DIR/owner" 2>/dev/null)" = update-usb-v1 ]
}

remove_transaction_record() {
  # Remove the durable record before its ownership marker, so interruption
  # always leaves either a recognizable record or an empty owned directory.
  rm -f -- "$TRANSACTION_DIR/transaction.json" "$TRANSACTION_DIR/transaction.json.tmp" || return 1
  rm -f -- "$TRANSACTION_DIR/owner" || return 1
  rmdir -- "$TRANSACTION_DIR" || return 1
}

prepare_usb_transaction() {
  local candidate="$1" state="$2" id metadata_bytes
  transaction_paths
  if [ "$candidate" != "$CANDIDATE_SQUASHFS" ] || [ ! -f "$candidate" ]; then
    echo 'Error: transaction candidate must be the USB temporary image.' >&2
    return 1
  fi
  if [ -e "$TRANSACTION_DIR" ] || [ -e "$PENDING_STATE" ]; then
    echo 'Error: pending USB transaction must be recovered before preparation.' >&2
    return 1
  fi
  metadata_bytes="$(du -s -B1 "$state" | cut -f1)" || return 1
  require_free_space "$MOUNT_POINT" "$((metadata_bytes + 16777216))" 'pending Nix metadata' || return 1
  id="$(cat /proc/sys/kernel/random/uuid)" || return 1
  mkdir -m 0700 "$TRANSACTION_DIR" || return 1
  printf '%s\n' update-usb-v1 > "$TRANSACTION_DIR/owner" || return 1
  mkdir "$PENDING_STATE" || return 1
  cp -a "$state/." "$PENDING_STATE/" || return 1
  printf '%s\n' "$id" > "$PENDING_STATE/.update-usb-transaction-id" || return 1
  "$UPDATE_USB_JQ" -n \
    --arg id "$id" --arg hash "$IMAGE_SHA256" \
    --arg system "$TARGET_SYSTEM_TOPLEVEL" \
    --arg previous "${PREVIOUS_SYSTEM_TOPLEVEL:-}" \
    --arg revision "${TARGET_CONFIG_REVISION:-}" \
    '{schema:1, id:$id, image_sha256:$hash, system:$system, previous:$previous, revision:$revision}' \
    > "$TRANSACTION_DIR/transaction.json.tmp" || return 1
  sync -f "$PENDING_STATE" || return 1
  mv -T "$TRANSACTION_DIR/transaction.json.tmp" "$TRANSACTION_DIR/transaction.json" || return 1
  sync -f "$TRANSACTION_DIR" || return 1
}

installed_boot_system() {
  local config="$MOUNT_POINT/boot/grub/grub.cfg"
  [ -f "$config" ] || return 0
  awk '/^[[:space:]]*linux(efi|16)?[[:space:]]/ {
    for (i=1; i<=NF; i++) if ($i ~ /^init=\/nix\/store\//) {
      sub(/^init=/, "", $i); sub(/\/init$/, "", $i); print $i; exit
    }
  }' "$config"
}

install_target_bootloader() {
  local status=0
  mkdir -p "$MOUNT_POINT/nix/store" || return 1
  ln -sfn /proc/mounts "$MOUNT_POINT/etc/mtab" || return 1
  mount -t squashfs -o loop,ro "$FINAL_SQUASHFS" "$MOUNT_POINT/nix/store" || return 1
  # Match nixos-install's nested bind so absolute paths in bootloader options
  # resolve inside nixos-enter's private namespace.
  export mountPoint="$MOUNT_POINT"
  if ! NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root "$MOUNT_POINT" --system "$TARGET_SYSTEM_TOPLEVEL" -c '
    set -eu
    mount --rbind --mkdir / "$mountPoint"
    mount --make-rslave "$mountPoint"
    /run/current-system/bin/switch-to-configuration boot
    umount -R "$mountPoint"
    rmdir "$mountPoint" 2>/dev/null || true
  '; then
    status=1
  fi
  if [ "$status" -eq 0 ]; then
    # Activation has created target users by this point.
    chroot "$MOUNT_POINT" "$TARGET_SYSTEM_TOPLEVEL/sw/bin/install" -d -m 0755 -o stefan -g users \
      /home/stefan/.local/state/home-manager /home/stefan/.local/state/home-manager/gcroots \
      /home/stefan/.local/state/nix /home/stefan/.local/state/nix/profiles || status=1
  fi
  umount "$MOUNT_POINT/nix/store" || return 1
  [ "$status" -eq 0 ] || return "$status"
  sync -f "$MOUNT_POINT/boot" || return 1
  sync -f "$MOUNT_POINT" || return 1
  if [ "$(installed_boot_system)" != "$TARGET_SYSTEM_TOPLEVEL" ]; then
    echo 'Error: GRUB does not select the published system.' >&2
    return 1
  fi
}

resume_usb_transaction() {
  local id hash state_id
  transaction_paths
  [ -e "$TRANSACTION_DIR" ] || return 0
  if [ -d "$TRANSACTION_DIR" ] && [ ! -L "$TRANSACTION_DIR" ] \
    && [ "$(stat -c %u "$TRANSACTION_DIR")" = "$EUID" ] \
    && [ -z "$(find "$TRANSACTION_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    rmdir "$TRANSACTION_DIR" || return 1
    return 0
  fi
  if ! transaction_is_owned; then
    echo "Error: refusing unrecognized transaction directory: $TRANSACTION_DIR" >&2
    return 1
  fi
  if [ ! -f "$TRANSACTION_DIR/transaction.json" ]; then
    # No image or metadata can be published until this record is durable.
    rm -rf -- "$PENDING_STATE" || return 1
    rm -f -- "$CANDIDATE_SQUASHFS" || return 1
    remove_transaction_record || return 1
    return 0
  fi
  if ! "$UPDATE_USB_JQ" -e '
    .schema == 1 and (.id | test("^[a-f0-9-]+$"))
    and (.image_sha256 | test("^[a-f0-9]{64}$"))
    and (.system | test("^/nix/store/[a-zA-Z0-9+._?=-]+$"))
    and (.previous == "" or (.previous | test("^/nix/store/[a-zA-Z0-9+._?=-]+$")))
  ' "$TRANSACTION_DIR/transaction.json" >/dev/null; then
    echo 'Error: invalid USB transaction record; preserving recovery files.' >&2
    return 1
  fi
  id="$("$UPDATE_USB_JQ" -r .id "$TRANSACTION_DIR/transaction.json")" || return 1
  hash="$("$UPDATE_USB_JQ" -r .image_sha256 "$TRANSACTION_DIR/transaction.json")" || return 1
  TARGET_SYSTEM_TOPLEVEL="$("$UPDATE_USB_JQ" -r .system "$TRANSACTION_DIR/transaction.json")" || return 1
  TARGET_CONFIG_REVISION="$("$UPDATE_USB_JQ" -r .revision "$TRANSACTION_DIR/transaction.json")" || return 1
  PREVIOUS_SYSTEM_TOPLEVEL="$("$UPDATE_USB_JQ" -r .previous "$TRANSACTION_DIR/transaction.json")" || return 1
  TARGET_INIT_RELATIVE="${TARGET_SYSTEM_TOPLEVEL#/nix/store/}/init"
  state_id="$(cat "$PUBLISHED_STATE/.update-usb-transaction-id" 2>/dev/null || true)"

  if [ "$state_id" != "$id" ]; then
    if [ "$(cat "$PENDING_STATE/.update-usb-transaction-id" 2>/dev/null || true)" != "$id" ] \
      || [ "$(profile_store_target "$PENDING_STATE/profiles/system" || true)" != "$TARGET_SYSTEM_TOPLEVEL" ]; then
      echo 'Error: pending Nix metadata does not match the verified image.' >&2
      return 1
    fi
  elif [ "$(profile_store_target "$PUBLISHED_STATE/profiles/system" || true)" != "$TARGET_SYSTEM_TOPLEVEL" ]; then
    echo 'Error: published Nix metadata does not match its transaction.' >&2
    return 1
  fi

  if [ -f "$CANDIDATE_SQUASHFS" ]; then
    if [ "$state_id" = "$id" ]; then
      echo 'Error: published metadata conflicts with an unpublished image; preserving recovery files.' >&2
      return 1
    fi
    phase_begin flushing-squashfs 'Flushing image writes to USB'
    run_with_progress 'Flushing image writes to USB' sync -f "$CANDIDATE_SQUASHFS" || return 1
    phase_end
    phase_begin verifying-transfer 'Verifying complete USB image checksum'
    if ! run_with_progress 'Verifying complete USB image checksum' verify_image_checksum "$CANDIDATE_SQUASHFS" "$hash"; then
      # The published image and metadata are still untouched. Discard only
      # this invalid candidate so a subsequent invocation can rebuild it.
      # Retire the record durably before removing its candidate; otherwise an
      # interrupted discard would resemble a completed image rename.
      rm -f -- "$TRANSACTION_DIR/transaction.json" || return 1
      sync -f "$TRANSACTION_DIR" || return 1
      rm -f -- "$CANDIDATE_SQUASHFS" || return 1
      rm -rf -- "$PENDING_STATE" || return 1
      remove_transaction_record || return 1
      return 1
    fi
    phase_end
    verify_squashfs_contains_system "$CANDIDATE_SQUASHFS" || return 1
    mv -T "$CANDIDATE_SQUASHFS" "$FINAL_SQUASHFS" || return 1
    sync -f "$MOUNT_POINT" || return 1
  else
    run_with_progress 'Checking published image for recovery' verify_image_checksum "$FINAL_SQUASHFS" "$hash" || return 1
  fi
  transaction_checkpoint after-image || return 1

  if [ "$state_id" != "$id" ]; then
    mkdir -p "$PUBLISHED_STATE" || return 1
    mv --exchange --no-copy -T "$PENDING_STATE" "$PUBLISHED_STATE" || return 1
    sync -f "$PUBLISHED_STATE" || return 1
  fi
  transaction_checkpoint after-metadata || return 1

  phase_begin publishing-boot 'Publishing boot configuration'
  run_with_progress 'Publishing boot configuration' install_target_bootloader || return 1
  phase_end
  transaction_checkpoint after-bootloader || return 1
  cp "$TRANSACTION_DIR/transaction.json" "$MOUNT_POINT/.update-usb-manifest.json.tmp" || return 1
  mv -T "$MOUNT_POINT/.update-usb-manifest.json.tmp" "$MOUNT_POINT/.update-usb-manifest.json" || return 1
  sync -f "$MOUNT_POINT" || return 1
  rm -rf -- "$PENDING_STATE" || return 1
  remove_transaction_record || return 1
  sync -f "$MOUNT_POINT" || return 1
}
