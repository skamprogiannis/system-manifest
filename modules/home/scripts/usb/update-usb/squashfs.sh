#!/usr/bin/env bash
# shellcheck disable=SC2034

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
      */*) return 1 ;;
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
  PREVIOUS_SYSTEM_TOPLEVEL=""

  if [ ! -f "$squashfs_path" ] || [ ! -L "$system_profile" ]; then
    verbose_log "No complete previous USB generation found; starting with clean Nix profile state."
    return 0
  fi

  profile_target="$(profile_store_target "$system_profile" 2>/dev/null || true)"
  if [ -z "$profile_target" ]; then
    echo "Warning: existing USB system profile is invalid; dropping rollback state." >&2
    return 0
  fi

  init_relative="${profile_target#/nix/store/}/init"
  if ! unsquashfs -cat "$squashfs_path" "$init_relative" >/dev/null 2>&1; then
    echo "Warning: existing USB profile is not present in the current squashfs; dropping rollback state." >&2
    return 0
  fi

  PRESERVE_PREVIOUS_GENERATION=1
  PREVIOUS_SYSTEM_TOPLEVEL="$profile_target"
  echo "Previous USB generation validated for rollback."
  verbose_log "Rollback generation: $profile_target"
}

prune_usb_system_generations() {
  local profile="$MOUNT_POINT/nix/var/nix/profiles/system"
  local chroot_bin
  chroot_bin="$(command -v chroot)" || return 1

  # nixos-enter activates the target, so preparation uses the local store API.
  nix-env --store "$MOUNT_POINT" --profile "$profile" --delete-generations +2 || return 1
  mkdir -p "$MOUNT_POINT/proc" || return 1
  # A host-side GC scans host /proc and retains unrelated matching store paths.
  # The target's Nix runs without activation, with only its own process tree
  # visible. Its executable belongs to the retained current system closure.
  unshare --mount --pid --fork --kill-child --propagation private \
    --mount-proc="$MOUNT_POINT/proc" \
    env -i HOME=/root USER=root \
    "$chroot_bin" "$MOUNT_POINT" "$TARGET_SYSTEM_TOPLEVEL/sw/bin/nix-store" \
    --store local --option build-users-group '' --option auto-optimise-store false --gc || return 1
  echo "Retained USB generations:"
  nix-env --store "$MOUNT_POINT" --profile "$profile" --list-generations
}

verify_squashfs_contains_system() {
  local squashfs_path="$1"

  if [ -z "$TARGET_SYSTEM_TOPLEVEL" ] || [ -z "$TARGET_INIT_RELATIVE" ]; then
    echo "Error: target system metadata was not captured before squashfs verification."
    return 1
  fi

  if [ ! -f "$squashfs_path" ]; then
    echo "Error: squashfs image not found at $squashfs_path"
    return 1
  fi

  if ! unsquashfs -cat "$squashfs_path" "$TARGET_INIT_RELATIVE" >/dev/null 2>&1; then
    echo "Error: $squashfs_path does not contain the installed USB system path."
    echo "Expected to find: $TARGET_SYSTEM_TOPLEVEL"
    return 1
  fi

  echo "Expected system found in squashfs."
  verbose_log "verified squashfs contains: $TARGET_SYSTEM_TOPLEVEL"
  verbose_log "usb squashfs timestamp: $(stat -c '%y' "$squashfs_path")"
}

verify_image_closures() {
  local image="$1" result=0 profile generation
  local closure_file="$RUNTIME_DIR/tmp/image-closure"
  local store="local?root=$MOUNT_POINT&read-only=true"
  local roots=("$TARGET_SYSTEM_TOPLEVEL")
  if [ -n "${PREVIOUS_SYSTEM_TOPLEVEL:-}" ]; then
    roots+=("$PREVIOUS_SYSTEM_TOPLEVEL")
  fi
  # A forced rewrite can retain an older rollback even when the active system
  # already equals the desired one. Verify every retained profile as well.
  for profile in "$MOUNT_POINT"/nix/var/nix/profiles/system-*-link; do
    [ -L "$profile" ] || continue
    generation="$(profile_store_target "$profile")" || return 1
    roots+=("$generation")
  done
  verify_squashfs_contains_system "$image" || return 1
  umount "$MOUNT_POINT/nix/store" || return 1
  if ! mount -t squashfs -o loop,ro "$image" "$MOUNT_POINT/nix/store"; then
    mount --bind "$STAGE_STORE" "$MOUNT_POINT/nix/store" || true
    return 1
  fi
  if nix-store --extra-experimental-features read-only-local-store --store "$store" --query --requisites "${roots[@]}" > "$closure_file"; then
    xargs -r -d '\n' -n 128 nix-store --extra-experimental-features read-only-local-store --store "$store" --verify-path < "$closure_file" || result=1
  else
    result=1
  fi
  umount "$MOUNT_POINT/nix/store" || return 1
  mount --bind "$STAGE_STORE" "$MOUNT_POINT/nix/store" || return 1
  if [ "$result" -eq 0 ]; then
    echo "Verified package contents of current and retained rollback closures."
  fi
  return "$result"
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

  if [ ! -d "$MOUNT_POINT/.update-usb-transaction" ] \
    && [ "$(profile_store_target "$MOUNT_POINT/nix/var/nix/profiles/system" || true)" = "$DESIRED_SYSTEM_TOPLEVEL" ] \
    && [ "$(installed_boot_system)" = "$DESIRED_SYSTEM_TOPLEVEL" ] \
    && unsquashfs -cat "$squashfs_path" "$DESIRED_INIT_RELATIVE" >/dev/null 2>&1; then
    echo "USB image, profile and boot entry already select the desired system; skipping update."
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
