#!/usr/bin/env bash

profile_store_target() {
  local profile="$1"
  local current="$profile"
  local link=""
  local i

  for ((i = 0; i < 3; i++)); do
    [ -L "$current" ] || return 1
    link="$(readlink "$current")"
    case "$link" in
      /nix/store/*)
        printf '%s\n' "$link"
        return 0
        ;;
      /*)
        return 1
        ;;
      *)
        current="$(dirname "$current")/$link"
        ;;
    esac
  done

  return 1
}

prepare_generation_state() {
  local squashfs_path="$MOUNT_POINT/nix-store.squashfs"
  local system_profile="$MOUNT_POINT/nix/var/nix/profiles/system"
  local profile_target=""
  local init_relative=""

  PRESERVE_PREVIOUS_GENERATION=0

  if [ ! -f "$squashfs_path" ] || [ ! -L "$system_profile" ]; then
    verbose_log "No complete previous USB generation found; starting with clean Nix profile state."
    rm -rf "$MOUNT_POINT/nix/var/nix/db" "$MOUNT_POINT/nix/var/nix/profiles"
    return 0
  fi

  profile_target="$(profile_store_target "$system_profile" 2>/dev/null || true)"
  if [ -z "$profile_target" ]; then
    echo "Warning: existing USB system profile is invalid; dropping rollback state." >&2
    rm -rf "$MOUNT_POINT/nix/var/nix/db" "$MOUNT_POINT/nix/var/nix/profiles"
    return 0
  fi

  init_relative="${profile_target#/nix/store/}/init"
  if ! unsquashfs -cat "$squashfs_path" "$init_relative" >/dev/null 2>&1; then
    echo "Warning: existing USB profile is not present in the current squashfs; dropping rollback state." >&2
    rm -rf "$MOUNT_POINT/nix/var/nix/db" "$MOUNT_POINT/nix/var/nix/profiles"
    return 0
  fi

  PRESERVE_PREVIOUS_GENERATION=1
  echo "Previous USB generation validated for rollback."
  verbose_log "Rollback generation: $profile_target"
}

hydrate_store_from_existing_squashfs() {
  local destination="$1"
  local squashfs_path="$MOUNT_POINT/nix-store.squashfs"

  mkdir -p "$destination"
  if [ "$PRESERVE_PREVIOUS_GENERATION" -ne 1 ]; then
    return 0
  fi

  echo "Hydrating previous generation into the update store..."
  unsquashfs -f -d "$destination" "$squashfs_path" >/dev/null
}

prune_usb_system_generations() {
  local nix_env="/nix/var/nix/profiles/system/sw/bin/nix-env"
  local nix_store="/nix/var/nix/profiles/system/sw/bin/nix-store"
  local profile="/nix/var/nix/profiles/system"

  nixos-enter --root "$MOUNT_POINT" -c "$nix_env --profile $profile --delete-generations +2"
  nixos-enter --root "$MOUNT_POINT" -c "$nix_store --gc"
  echo "Retained USB generations:"
  nixos-enter --root "$MOUNT_POINT" -c "$nix_env --profile $profile --list-generations"
}

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

publish_squashfs() {
  local candidate="$1"
  local final="$MOUNT_POINT/nix-store.squashfs"

  verify_squashfs_contains_system "$candidate"
  sync -f "$candidate"
  mv -f "$candidate" "$final"
  sync -f "$MOUNT_POINT"
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
