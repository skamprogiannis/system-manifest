#!/usr/bin/env bash
# shellcheck disable=SC2034

stage_has_mounts() {
  local target
  while IFS= read -r target; do
    # findmnt --raw hex-escapes whitespace and backslashes in mount paths.
    printf -v target '%b' "$target"
    case "$target" in
      "$STAGE_DIR"|"$STAGE_DIR"/*) return 0 ;;
    esac
  done < <(findmnt -rn -o TARGET)
  return 1
}

stage_is_owned() {
  [ -d "$STAGE_DIR" ] && [ ! -L "$STAGE_DIR" ] \
    && [ "$(stat -c %u "$STAGE_DIR")" = "$EUID" ] \
    && [ ! -L "$STAGE_DIR/.update-usb-workspace" ] \
    && [ "$(cat "$STAGE_DIR/.update-usb-workspace" 2>/dev/null)" = update-usb-v1 ]
}

prepare_stage_directory() {
  local canonical
  case "$STAGE_DIR" in
    *:*|*,*|*\\*|*$'\n'*)
      echo 'Error: staging directory contains characters unsupported by OverlayFS mount options.' >&2
      return 1 ;;
  esac
  canonical="$(realpath -m -- "$STAGE_DIR")" || return 1
  if [ "$canonical" != "$STAGE_DIR" ] || [ "$STAGE_DIR" = / ] || [ -L "$STAGE_DIR" ]; then
    echo "Error: staging requires a canonical absolute directory without symlinks: $STAGE_DIR" >&2
    return 1
  fi
  if [ -e "$STAGE_DIR" ]; then
    if [ ! -d "$STAGE_DIR" ] || [ "$(stat -c %u "$STAGE_DIR")" != "$EUID" ]; then
      echo "Error: staging directory must be owned by the updater user: $STAGE_DIR" >&2
      return 1
    fi
    if ! stage_is_owned && [ -n "$(find "$STAGE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      echo "Error: refusing to remove unmarked staging files at $STAGE_DIR. Choose an empty --stage-dir." >&2
      return 1
    fi
    if stage_has_mounts; then
      echo "Error: staging still contains mounts: $STAGE_DIR" >&2
      return 1
    fi
    rm -rf -- "$STAGE_DIR" || return 1
  fi
  mkdir -p -- "$STAGE_DIR" || return 1
  chmod 0700 -- "$STAGE_DIR" || return 1
  printf '%s\n' update-usb-v1 > "$STAGE_DIR/.update-usb-workspace" || return 1
  STAGE_PREPARED=1
}

require_free_space() {
  local directory="$1" required="$2" description="$3" available
  available="$(df -B1 --output=avail "$directory" | tail -n1 | tr -d ' ')" || return 1
  if [ "$available" -lt "$required" ]; then
    echo "Error: insufficient space for $description at $directory (need $required bytes; available $available)." >&2
    return 1
  fi
}

cleanup_stage_mounts() {
  local target failed=0
  for target in "$STAGE_DIR/store" "$STAGE_DIR/lower"; do
    if mountpoint -q "$target"; then
      umount "$target" || failed=1
    fi
  done
  return "$failed"
}

detach_target_stage() {
  local target
  for target in "$MOUNT_POINT/nix/store" "$MOUNT_POINT/nix/var/nix"; do
    if mountpoint -q "$target"; then
      umount "$target" || return 1
    fi
  done
  MOUNTED_STAGE_STORE=0
  MOUNTED_STAGE_STATE=0
}

prepare_target_stage() {
  STAGE_STORE="$STAGE_DIR/store"
  STAGE_STATE="$STAGE_DIR/nix-state"
  STAGE_LOWER="$STAGE_DIR/lower"
  STAGE_UPPER="$STAGE_DIR/upper"
  mkdir -p "$STAGE_STORE" "$STAGE_STATE" "$MOUNT_POINT/nix/store" "$MOUNT_POINT/nix/var/nix" || return 1

  if [ "$PRESERVE_PREVIOUS_GENERATION" -eq 1 ]; then
    cp -a "$MOUNT_POINT/nix/var/nix/." "$STAGE_STATE/" || return 1
    if [ "$MODE" = prebuild ]; then
      require_free_space "$STAGE_DIR" "$(stat -c %s "$MOUNT_POINT/nix-store.squashfs")" 'compressed staging base' || return 1
      run_with_progress 'Copying previous image to SSD' cp "$MOUNT_POINT/nix-store.squashfs" "$STAGE_DIR/base.squashfs" || return 1
      mkdir -p "$STAGE_DIR/lower" "$STAGE_DIR/upper" "$STAGE_DIR/work" || return 1
      mount -t squashfs -o loop,ro "$STAGE_DIR/base.squashfs" "$STAGE_DIR/lower" || return 1
      # Private immutable lower data avoids host store sharing and GC races.
      mount -t overlay overlay -o "lowerdir=$STAGE_DIR/lower,upperdir=$STAGE_DIR/upper,workdir=$STAGE_DIR/work,index=off,metacopy=off,redirect_dir=off" "$STAGE_STORE" || return 1
    else
      run_with_progress 'Expanding previous image on USB' unsquashfs -f -d "$STAGE_STORE" "$MOUNT_POINT/nix-store.squashfs" || return 1
    fi
  fi
  mount --bind "$STAGE_STORE" "$MOUNT_POINT/nix/store" || return 1
  MOUNTED_STAGE_STORE=1
  mount --bind "$STAGE_STATE" "$MOUNT_POINT/nix/var/nix" || return 1
  MOUNTED_STAGE_STATE=1
}

check_staging_capacity() {
  local closure="$RUNTIME_DIR/tmp/desired-closure.json" missing=0 bytes path estimated_image total
  nix path-info --json --recursive "$DESIRED_SYSTEM_TOPLEVEL" > "$closure" || return 1
  while IFS=$'\t' read -r path bytes; do
    if [ ! -e "$STAGE_STORE/${path#/nix/store/}" ] && [ ! -L "$STAGE_STORE/${path#/nix/store/}" ]; then
      missing=$((missing + bytes))
    fi
  done < <("$UPDATE_USB_JQ" -r 'to_entries[] | [.key, .value.narSize] | @tsv' "$closure")
  total="$("$UPDATE_USB_JQ" '[.[].narSize] | add // 0' "$closure")" || return 1
  # Compression is not knowable in advance. Reserve an estimate, then check
  # the actual finished image before touching published USB artifacts.
  estimated_image=$((total * 3 / 5 + missing * 3 / 5 + 1073741824))
  echo "Estimated additional staging requirement: $((missing + estimated_image)) bytes."
  require_free_space "$STAGE_DIR" "$((missing + estimated_image))" 'new packages and replacement image (estimate)'
}
