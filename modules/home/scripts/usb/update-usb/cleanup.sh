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
    return 1
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
  if declare -F stop_active_command >/dev/null; then
    stop_active_command
    return
  fi
  local pid="${ACTIVE_CHILD_PID:-}"

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
}

cleanup_mount_tree() {
  local target mount_targets failed=0

  if ! mount_targets="$(findmnt -Rrn --mountpoint "$MOUNT_POINT" -o TARGET 2>/dev/null)"; then
    return 0
  fi

  while IFS= read -r target; do
    case "$target" in
      "$MOUNT_POINT"|"$MOUNT_POINT"/*)
        printf '%s\n' "$target"
        ;;
    esac
  done <<<"$mount_targets" | sort -r > "$UPDATE_USB_TMP_DIR/mounts"
  while IFS= read -r target; do
    if mountpoint -q "$target"; then
      if ! umount "$target"; then
        cleanup_warn "failed to unmount $target"
        failed=1
      fi
    fi
  done < "$UPDATE_USB_TMP_DIR/mounts"
  return "$failed"
}

remove_pending_squashfs() {
  local pending="$MOUNT_POINT/nix-store.squashfs.tmp"

  if [ -d "$MOUNT_POINT/.update-usb-transaction" ]; then
    echo 'Preserving pending USB transaction for the next invocation.'
    return 0
  fi
  if [ -e "$pending" ]; then
    run_cleanup_step "failed to remove incomplete squashfs candidate $pending" rm -f "$pending"
  fi
}

remove_update_stage() {
  if [ -n "${STAGE_DIR:-}" ] && [ -d "$STAGE_DIR" ]; then
    if ! stage_is_owned; then
      cleanup_warn "preserving unmarked staging directory $STAGE_DIR"
      return 1
    fi
    cleanup_stage_mounts || return 1
    if stage_has_mounts; then
      cleanup_warn "preserving staging directory with active mounts $STAGE_DIR"
      return 1
    fi
    rm -rf -- "$STAGE_DIR" || return 1
  fi
}

remove_obsolete_usb_mountpoint() {
  rmdir "$MOUNT_POINT/mnt/usb-sync" 2>/dev/null || true
}

prepare_update_workspace() {
  local requested_stage="$STAGE_DIR" recorded_stage
  if [ -f "$RUNTIME_DIR/stage-path" ]; then
    recorded_stage="$(cat "$RUNTIME_DIR/stage-path")"
    STAGE_DIR="$recorded_stage"
    if ! detach_target_stage || ! remove_update_stage; then
      STAGE_DIR="$requested_stage"
      return 1
    fi
    STAGE_DIR="$requested_stage"
    rm -f "$RUNTIME_DIR/stage-path"
  fi
  cleanup_mount_tree || return 1

  if mountpoint -q "$MOUNT_POINT"; then
    echo "Error: failed to recover stale update-usb mounts under $MOUNT_POINT." >&2
    return 1
  fi
  mkdir -p "$MOUNT_POINT" || return 1
  WORKSPACE_PREPARED=1
}

settle_usb_devices() {
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle --timeout=10 || true
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
  local status="${1:-$?}" mounts_clean=1 interrupted_phase="$CURRENT_PHASE" phase_status=failed
  # EXIT can run inside copy_with_progress before its local callback unwinds.
  local PROGRESS_CALLBACK=command_progress
  trap - EXIT
  trap '' HUP INT TERM
  if [ "$CANCELED" -eq 1 ]; then
    echo "=== USB Update: Cleanup after cancellation ==="
  else
    verbose_log "Cleaning up mounts..."
  fi

  stop_active_child

  if [ "${PHASE_ACTIVE:-0}" -eq 1 ]; then
    [ "$CANCELED" -eq 0 ] || phase_status=canceled
    if [ "$status" -eq 0 ]; then phase_end; else
      report_phase "$CURRENT_PHASE" "$PHASE_LABEL" "$(( $(date +%s) - PHASE_STARTED_AT ))" "$phase_status"
      PHASE_ACTIVE=0
    fi
  fi

  if [ "${WORKSPACE_PREPARED:-0}" -eq 1 ]; then
    phase_begin cleanup 'Unmounting and cleaning temporary files'
    remove_pending_squashfs || status=1
    # In-place staging is inside the USB root, so release it before that root.
    if [ "${STAGE_PREPARED:-0}" -eq 1 ]; then
      if detach_target_stage && remove_update_stage; then
        rm -f "$RUNTIME_DIR/stage-path"
      else
        mounts_clean=0
        status=1
      fi
    fi
    if ! run_with_progress 'Unmounting target filesystems' cleanup_mount_tree; then
      mounts_clean=0
      status=1
    fi
  fi
  if [ "$CLOSE_MAPPER_ON_CLEANUP" -eq 1 ] && [ "$mounts_clean" -eq 1 ]; then
    run_with_progress 'Closing USB encryption mapping' close_usb_mapper || status=1
  fi

  if [ "${WORKSPACE_PREPARED:-0}" -eq 1 ]; then
    phase_end
  fi
  rm -rf "${RUNTIME_DIR:?}/tmp"
  rm -f "$RUNTIME_DIR/built-system"
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  finish_update_report "$status"

  if [ "$CANCELED" -eq 1 ]; then
    echo "Canceled during phase: $interrupted_phase"
    echo 'Pending publication will be recovered on the next update-usb invocation.'
  elif [ "$status" -eq 0 ]; then
    progress_set 100 'Done; USB writes are flushed and cleanup is complete'
    print_timing_summary
  fi
  exit "$status"
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
