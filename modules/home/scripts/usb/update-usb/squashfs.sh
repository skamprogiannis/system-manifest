#!/usr/bin/env bash

verify_squashfs_contains_system() {
  local squashfs_path="$1"

  if [ -z "$TARGET_SYSTEM_TOPLEVEL" ] || [ -z "$TARGET_INIT_RELATIVE" ]; then
    echo "Error: target system metadata was not captured before squashfs verification."
    exit 1
  fi

  if [ ! -f "$squashfs_path" ]; then
    echo "Error: squashfs image not found at $squashfs_path"
    exit 1
  fi

  if ! unsquashfs -cat "$squashfs_path" "$TARGET_INIT_RELATIVE" >/dev/null 2>&1; then
    echo "Error: $squashfs_path does not contain the installed USB system path."
    echo "Expected to find: $TARGET_SYSTEM_TOPLEVEL"
    exit 1
  fi

  echo "Squashfs verified."
  verbose_log "verified squashfs contains: $TARGET_SYSTEM_TOPLEVEL"
  verbose_log "usb squashfs timestamp: $(stat -c '%y' "$squashfs_path")"
}

skip_if_existing_squashfs_is_current() {
  local squashfs_path="$MOUNT_POINT/nix-store.squashfs"

  if [ "$FORCE_UPDATE" -eq 1 ]; then
    verbose_log "Force update requested; skipping existing squashfs preflight."
    return 0
  fi

  if [ -z "$DESIRED_SYSTEM_TOPLEVEL" ] || [ -z "$DESIRED_INIT_RELATIVE" ]; then
    echo "Warning: desired USB system path unavailable; continuing update." >&2
    return 0
  fi

  if [ ! -f "$squashfs_path" ]; then
    verbose_log "No existing USB squashfs found; continuing update."
    return 0
  fi

  if unsquashfs -cat "$squashfs_path" "$DESIRED_INIT_RELATIVE" >/dev/null 2>&1; then
    echo "Existing USB squashfs already contains the desired system; skipping update."
    if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
      echo "Expected revision: $EXPECTED_CONFIG_REVISION"
    fi
    verbose_log "Desired USB system path: $DESIRED_SYSTEM_TOPLEVEL"
    verbose_log "USB squashfs timestamp: $(stat -c '%y' "$squashfs_path")"
    echo "Pass --force to rebuild and rewrite the USB anyway."
    return 1
  fi

  verbose_log "Existing USB squashfs does not contain the desired system; continuing update."
  return 0
}
