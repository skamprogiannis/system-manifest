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

free_space_bytes() {
  local available
  available="$(df -B1 --output=avail "$1" | tail -n1 | tr -d ' ')" || return 1
  if [[ ! "$available" =~ ^[0-9]+$ ]]; then
    echo "Error: could not read available space at $1." >&2
    return 1
  fi
  printf '%s\n' "$available"
}

format_storage_size() {
  LC_ALL=C awk -v bytes="$1" 'BEGIN { printf "%.2f GiB (%s bytes)", bytes / 1073741824, bytes }'
}

require_free_space() {
  local directory="$1" required="$2" description="$3" available
  available="$(free_space_bytes "$directory")" || return 1
  if [ "$available" -lt "$required" ]; then
    echo "Error: insufficient space for $description at $directory (need $(format_storage_size "$required"); available $(format_storage_size "$available"); short by $(format_storage_size "$((required - available))"))." >&2
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

release_target_stage() {
  detach_target_stage || return 1
  cleanup_stage_mounts
}

mount_stage_overlay() {
  local image="$1"
  mkdir -p "$STAGE_DIR/lower" "$STAGE_DIR/upper" "$STAGE_DIR/work" || return 1
  mount -t squashfs -o loop,ro "$image" "$STAGE_DIR/lower" || return 1
  # Private writable data avoids host store sharing and GC races with either
  # the unchanged USB image or an optional SSD copy as the read-only lower.
  mount -t overlay overlay -o "lowerdir=$STAGE_DIR/lower,upperdir=$STAGE_DIR/upper,workdir=$STAGE_DIR/work,index=off,metacopy=off,redirect_dir=off" "$STAGE_STORE" || return 1
}

bind_target_stage() {
  mount --bind "$STAGE_STORE" "$MOUNT_POINT/nix/store" || return 1
  MOUNTED_STAGE_STORE=1
  mount --bind "$STAGE_STATE" "$MOUNT_POINT/nix/var/nix" || return 1
  MOUNTED_STAGE_STATE=1
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
      # Capacity is checked before allocating an optional compressed base copy.
      # The published image stays unchanged until all staging mounts are released.
      mount_stage_overlay "$MOUNT_POINT/nix-store.squashfs" || return 1
    else
      run_with_progress 'Expanding previous image on USB' unsquashfs -f -d "$STAGE_STORE" "$MOUNT_POINT/nix-store.squashfs" || return 1
    fi
  fi
  bind_target_stage
}

cache_previous_image_if_room() {
  local base_bytes available
  if [ "$MODE" != prebuild ] || [ "$PRESERVE_PREVIOUS_GENERATION" -ne 1 ]; then return 0; fi
  : "${STAGING_REQUIRED_BYTES:?staging capacity must be checked before caching the base}"
  base_bytes="$(stat -c %s "$MOUNT_POINT/nix-store.squashfs")" || return 1
  available="$(free_space_bytes "$STAGE_DIR")" || return 1
  if [ "$((available - base_bytes))" -lt "$STAGING_REQUIRED_BYTES" ]; then
    require_free_space "$STAGE_DIR" "$STAGING_REQUIRED_BYTES" 'new packages and replacement image (estimate)' || return 1
    echo "Reading the previous image directly from USB; avoiding an SSD copy saves $(format_storage_size "$base_bytes")."
    echo 'New packages and the replacement image will still be staged locally.'
    return 0
  fi

  copy_with_progress "$MOUNT_POINT/nix-store.squashfs" "$STAGE_DIR/base.squashfs" 0 100 'Copying previous image to SSD' || return 1
  release_target_stage || return 1
  mount_stage_overlay "$STAGE_DIR/base.squashfs" || return 1
  bind_target_stage || return 1
  # Other host activity can consume space while the optional copy is written.
  require_free_space "$STAGE_DIR" "$STAGING_REQUIRED_BYTES" 'new packages and replacement image (estimate)'
}

check_staging_capacity() {
  local closure="$RUNTIME_DIR/tmp/desired-closure.json"
  local rollback_closure="$RUNTIME_DIR/tmp/rollback-closure.json"
  local closure_paths="$RUNTIME_DIR/tmp/desired-closure.tsv"
  local missing=0 bytes path estimated_image total required profile generation available
  local headroom=1073741824
  local rollback_roots=()
  local closure_filter='
    if type == "object" and length > 0 and
      all(to_entries[]; (.key | startswith("/nix/store/")) and
        (.value.narSize | type == "number" and . >= 0 and floor == .))
    then to_entries[] | [.key, .value.narSize] | @tsv
    else error("invalid path-info closure") end'

  nix path-info --json --json-format 1 --recursive "$DESIRED_SYSTEM_TOPLEVEL" > "$closure" || return 1
  "$UPDATE_USB_JQ" -r "$closure_filter" "$closure" > "$closure_paths" || return 1
  # $root is a jq variable, not a shell expansion.
  # shellcheck disable=SC2016
  "$UPDATE_USB_JQ" -e --arg root "$DESIRED_SYSTEM_TOPLEVEL" 'has($root)' "$closure" >/dev/null || return 1
  while IFS=$'\t' read -r path bytes; do
    if [ ! -e "$STAGE_STORE/${path#/nix/store/}" ] && [ ! -L "$STAGE_STORE/${path#/nix/store/}" ]; then
      missing=$((missing + bytes))
    fi
  done < "$closure_paths"

  printf '{}\n' > "$rollback_closure" || return 1
  if [ "${PRESERVE_PREVIOUS_GENERATION:-0}" -eq 1 ]; then
    [ -n "$PREVIOUS_SYSTEM_TOPLEVEL" ] || return 1
    rollback_roots+=("$PREVIOUS_SYSTEM_TOPLEVEL")
    # Manual rollback and forced reinstalls can retain profiles other than
    # the active generation. Conservatively include every existing root.
    for profile in "$MOUNT_POINT"/nix/var/nix/profiles/system-*-link; do
      [ -L "$profile" ] || continue
      generation="$(profile_store_target "$profile")" || return 1
      rollback_roots+=("$generation")
    done
    # The host may no longer have a rollback path; its metadata lives in the
    # private target database, already bound to the staging state directory.
    nix --extra-experimental-features read-only-local-store path-info \
      --store "local?root=$MOUNT_POINT&read-only=true" --json --json-format 1 \
      --recursive "${rollback_roots[@]}" > "$rollback_closure" || return 1
    "$UPDATE_USB_JQ" -r "$closure_filter" "$rollback_closure" >/dev/null || return 1
    for generation in "${rollback_roots[@]}"; do
      # shellcheck disable=SC2016
      "$UPDATE_USB_JQ" -e --arg root "$generation" 'has($root)' "$rollback_closure" >/dev/null || return 1
    done
  fi
  total="$("$UPDATE_USB_JQ" -s 'add | [.[].narSize] | add // 0' "$closure" "$rollback_closure")" || return 1
  # Desired totals already include new packages. Count shared paths once in
  # the replacement image, and reserve writable space only for missing paths.
  # Compression remains an estimate; publication checks the finished image.
  estimated_image=$((total * 3 / 5))
  required=$((missing + estimated_image + headroom))
  available="$(free_space_bytes "$STAGE_DIR")" || return 1
  echo "Missing packages to stage: $missing bytes."
  echo "Estimated replacement image: $estimated_image bytes."
  echo "Staging headroom: $headroom bytes."
  echo "Estimated additional staging requirement: $required bytes."
  echo "Staging capacity: $(format_storage_size "$required") required; $(format_storage_size "$available") currently free at $STAGE_DIR."
  if ! require_free_space "$STAGE_DIR" "$required" 'new packages and replacement image (estimate)'; then
    if [ "${MODE:-prebuild}" = in-place ]; then
      echo 'Rerun without --in-place and use --stage-dir PATH on a filesystem with sufficient free space.' >&2
    else
      echo 'Use --stage-dir PATH to select another staging filesystem with sufficient free space.' >&2
    fi
    return 1
  fi
  STAGING_REQUIRED_BYTES="$required"
}
