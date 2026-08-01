#!/usr/bin/env bash
# shellcheck disable=SC2034

cleanup_warn() {
  echo "Cleanup warning: $1" >&2
}

run_cleanup_step() {
  local description="$1"
  shift
  local output=""

  if ! output=$("$@" 2>&1); then
    cleanup_warn "$description"
    if [ -n "$output" ]; then
      printf '%s\n' "$output" >&2
    fi
  fi
}

initialize_update_runtime() {
  mkdir -p "$RUNTIME_DIR"
  chmod 0755 "$RUNTIME_DIR"
  exec 9>"$RUNTIME_DIR/lock"
  chmod 0600 "$RUNTIME_DIR/lock"
  if ! flock -n 9; then
    echo "Error: another update-usb process is already running." >&2
    return 1
  fi

  rm -rf "$RUNTIME_DIR/tmp"
  mkdir -p "$RUNTIME_DIR/tmp"
  chmod 0700 "$RUNTIME_DIR/tmp"
  export UPDATE_USB_TMP_DIR="$RUNTIME_DIR/tmp"
}

stop_active_child() {
  local pid="${ACTIVE_CHILD_PID:-}"

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
}

cleanup_mount_tree() {
  local target mount_targets

  if ! mount_targets="$(findmnt -Rrn --mountpoint "$MOUNT_POINT" -o TARGET 2>/dev/null)"; then
    return 0
  fi

  while IFS= read -r target; do
    case "$target" in
      "$MOUNT_POINT"|"$MOUNT_POINT"/*)
        printf '%s\n' "$target"
        ;;
    esac
  done <<<"$mount_targets" | sort -r | while IFS= read -r target; do
    if mountpoint -q "$target"; then
      run_cleanup_step "failed to unmount $target" umount "$target"
    fi
  done
}

remove_pending_squashfs() {
  local pending="$MOUNT_POINT/nix-store.squashfs.tmp"

  if [ -e "$pending" ]; then
    run_cleanup_step "failed to remove incomplete squashfs candidate $pending" rm -f "$pending"
  fi
}

remove_update_stage() {
  if [ -n "${STAGE_DIR:-}" ] && [ -d "$STAGE_DIR" ]; then
    run_cleanup_step "failed to remove temporary stage directory $STAGE_DIR" rm -rf "$STAGE_DIR"
  fi
}

remove_obsolete_usb_mountpoint() {
  rmdir "$MOUNT_POINT/mnt/usb-sync" 2>/dev/null || true
}

prepare_update_workspace() {
  WORKSPACE_PREPARED=1
  remove_pending_squashfs
  cleanup_mount_tree

  if mountpoint -q "$MOUNT_POINT"; then
    echo "Error: failed to recover stale update-usb mounts under $MOUNT_POINT." >&2
    return 1
  fi

  remove_update_stage
  mkdir -p "$MOUNT_POINT"
}

settle_usb_devices() {
  sync
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || true
  fi
}

close_usb_mapper() {
  local attempt output

  settle_usb_devices

  for attempt in 1 2 3 4 5; do
    if output="$(cryptsetup close "$USB_MAPPER_NAME" 2>&1)"; then
      return 0
    fi

    cleanup_mount_tree
    settle_usb_devices

    if [ "$attempt" -lt 5 ]; then
      sleep 1
    fi
  done

  if output="$(cryptsetup close --deferred "$USB_MAPPER_NAME" 2>&1)"; then
    verbose_log "Deferred mapper close scheduled for $USB_MAPPER_NAME."
    return 0
  fi

  cleanup_warn "failed to close mapper $USB_MAPPER_NAME"
  if [ -n "$output" ]; then
    printf '%s\n' "$output" >&2
  fi
  return 1
}

refresh_usb_mapper() {
  local existing_mapper=""
  existing_mapper=$(lsblk -nrpo NAME,TYPE "$USB_ROOT_PART" 2>/dev/null | sed -n '/ crypt$/ { s/ crypt$//; p; q; }')
  if [ -n "$existing_mapper" ]; then
    USB_ROOT_DEV="$existing_mapper"
    USB_MAPPER_NAME="${existing_mapper##*/}"
  else
    USB_MAPPER_NAME="$PREFERRED_USB_MAPPER_NAME"
    USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
  fi
}

cleanup() {
  if [ "$CANCELED" -eq 1 ]; then
    echo "=== USB Update: Cleanup after cancellation ==="
  else
    verbose_log "Cleaning up mounts..."
  fi

  stop_active_child

  if [ "${WORKSPACE_PREPARED:-0}" -eq 1 ]; then
    remove_pending_squashfs
    cleanup_mount_tree
    MOUNTED_STAGE_STORE=0
    MOUNTED_BOOT=0
    MOUNTED_ROOT=0
  fi
  if [ "$CLOSE_MAPPER_ON_CLEANUP" -eq 1 ]; then
    close_usb_mapper || true
  fi

  remove_update_stage
  rm -rf "${RUNTIME_DIR:?}/tmp"
  rmdir "$MOUNT_POINT" 2>/dev/null || true

  if [ "$CANCELED" -eq 1 ]; then
    echo "Canceled during phase: $CURRENT_PHASE"
    echo "You can safely retry: sudo update-usb /path/to/system-manifest/main"
  fi
}

cancel_update() {
  local signal="$1"
  local exit_code=130
  case "$signal" in
    HUP) exit_code=129 ;;
    INT) exit_code=130 ;;
    TERM) exit_code=143 ;;
  esac

  CANCELED=1
  echo
  echo "=== USB Update: Canceled ($signal) ==="
  echo "Interrupt received; attempting safe cleanup."
  exit "$exit_code"
}
