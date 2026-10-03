#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

: "${USB_ROOT_PART:?}"
: "${USB_BOOT_DEV:?}"
: "${PREFERRED_USB_MAPPER_NAME:?}"
USB_UPDATE_LIB_DIR="${USB_UPDATE_LIB_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
for fragment in args phases telemetry cleanup metadata squashfs staging transaction; do
  # shellcheck disable=SC1090
  source "$USB_UPDATE_LIB_DIR/$fragment.sh"
done

SCRIPT_NAME="$(basename "$0")"
USB_MAPPER_NAME="$PREFERRED_USB_MAPPER_NAME"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
RUNTIME_DIR=/run/update-usb
MOUNT_POINT="$RUNTIME_DIR/root"
STAGE_DIR=/var/tmp/update-usb-stage
STAGE_DIR_EXPLICIT=0
DEFAULT_MODE=prebuild
MODE="$DEFAULT_MODE"
FLAKE_DIR="$PWD"
NIX_SHELL_PACKAGES=(squashfsTools cryptsetup util-linux coreutils findutils gnused gawk jq)
REQUIRED_TOOLS=(nix nix-env nix-store nixos-install nixos-enter cryptsetup mount umount findmnt find rm du cut sort nproc mountpoint sed mktemp cp mv date chroot lsblk sleep sync stat cat tr tail flock mkdir chmod rmdir df realpath xargs sha256sum awk unshare env)
UPDATE_USB_JQ="${UPDATE_USB_JQ:-jq}"
FORCE_UPDATE=0
VERBOSE=0
CLOSE_MAPPER_ON_CLEANUP=0
WORKSPACE_PREPARED=0
STAGE_PREPARED=0
PRESERVE_PREVIOUS_GENERATION=0
PREVIOUS_SYSTEM_TOPLEVEL=""
ACTIVE_CHILD_PID=""
CANCELED=0
CURRENT_PHASE=startup
TARGET_CONFIG_REVISION=""
TARGET_NIXOS_VERSION=""
TARGET_SYSTEM_TOPLEVEL=""
TARGET_INIT_RELATIVE=""
TIMINGS=()
ORIGINAL_ARGS=("$@")

parse_args "$@"
if [ "$MODE" = in-place ] && [ "$STAGE_DIR_EXPLICIT" -eq 1 ]; then
  echo 'Error: --stage-dir selects host staging and cannot be combined with --in-place.' >&2
  exit 1
fi

if ! command -v mksquashfs >/dev/null 2>&1 || ! command -v unsquashfs >/dev/null 2>&1; then
  if [ "${USB_UPDATE_IN_NIX_SHELL:-0}" != 1 ] && command -v nix-shell >/dev/null 2>&1; then
    printf -v REEXEC_COMMAND '%q ' bash "$0" "${ORIGINAL_ARGS[@]}"
    exec nix-shell -p "${NIX_SHELL_PACKAGES[@]}" --run "USB_UPDATE_IN_NIX_SHELL=1 $REEXEC_COMMAND"
  fi
  echo "Error: squashfs tools are missing; run inside nix-shell -p ${NIX_SHELL_PACKAGES[*]}." >&2
  exit 1
fi
if [ "$EUID" -ne 0 ]; then
  echo 'Error: please run with sudo.' >&2
  exit 1
fi
for tool in "${REQUIRED_TOOLS[@]}" "$UPDATE_USB_JQ"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool '$tool' is not available." >&2
    exit 1
  fi
done

initialize_update_runtime
trap 'cleanup "$?"' EXIT
trap 'cancel_update HUP' HUP
trap 'cancel_update INT' INT
trap 'cancel_update TERM' TERM
if [ ! -f "$FLAKE_DIR/flake.nix" ]; then
  echo "Error: pass a worktree containing flake.nix: $FLAKE_DIR" >&2
  exit 1
fi
FLAKE_DIR="$(realpath "$FLAKE_DIR")"
EXPECTED_CONFIG_REVISION="$(read_expected_config_revision || true)"
capture_desired_system_metadata
echo "Source flake: $FLAKE_DIR"
echo "Desired revision: ${EXPECTED_CONFIG_REVISION:-unknown}"
if [ ! -e "$USB_ROOT_PART" ] || [ ! -e "$USB_BOOT_DEV" ]; then
  echo 'Error: labeled USB root and boot partitions are required.' >&2
  exit 1
fi
ROOT_DISK="$(lsblk -ndo PKNAME "$(readlink -f "$USB_ROOT_PART")")"
BOOT_DISK="$(lsblk -ndo PKNAME "$(readlink -f "$USB_BOOT_DEV")")"
if [ -z "$ROOT_DISK" ] || [ "$ROOT_DISK" != "$BOOT_DISK" ]; then
  echo 'Error: USB root and boot labels must identify partitions on the same disk.' >&2
  exit 1
fi
prepare_update_workspace

phase_begin opening-luks 'Opening USB encryption mapping'
refresh_usb_mapper
if [ -e "$USB_ROOT_DEV" ] && findmnt -rn -S "$USB_ROOT_DEV" >/dev/null; then
  echo 'Error: USB root is already mounted outside this updater.' >&2
  exit 1
fi
if [ ! -e "$USB_ROOT_DEV" ]; then
  cryptsetup open "$USB_ROOT_PART" "$PREFERRED_USB_MAPPER_NAME"
  refresh_usb_mapper
fi
CLOSE_MAPPER_ON_CLEANUP=1
mount "$USB_ROOT_DEV" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/boot"
mount "$USB_BOOT_DEV" "$MOUNT_POINT/boot"
phase_end
start_update_report /var/log/update-usb "$FLAKE_DIR" "$MOUNT_POINT"

# Recovery precedes no-op detection: an image alone is not a completed update.
resume_usb_transaction
remove_pending_squashfs
if ! skip_if_existing_squashfs_is_current; then
  CURRENT_PHASE='done'
  exit 0
fi
report_image previous "$MOUNT_POINT/nix-store.squashfs"
prepare_generation_state

phase_begin building-system 'Building desired USB system in the host store'
# The output link pins the desired closure until installation and cleanup finish.
run_with_progress 'Building USB system' nix build --out-link "$RUNTIME_DIR/built-system" "$FLAKE_DIR#nixosConfigurations.usb.config.system.build.toplevel"
if [ "$(readlink "$RUNTIME_DIR/built-system")" != "$DESIRED_SYSTEM_TOPLEVEL" ]; then
  echo 'Error: the flake changed between evaluation and build; rerun the update.' >&2
  exit 1
fi
phase_end

phase_begin preparing-stage 'Preparing private store and Nix metadata'
if [ "$MODE" = in-place ]; then
  STAGE_DIR="$MOUNT_POINT/.update-usb-stage"
fi
prepare_stage_directory
printf '%s\n' "$STAGE_DIR" > "$RUNTIME_DIR/stage-path"
prepare_target_stage
check_staging_capacity
phase_end

phase_begin installing-system 'Installing into private staging'
NIX_CONFIG="${NIX_CONFIG:-}"$'\nauto-optimise-store = false' \
  run_with_progress 'Installing NixOS into staging' nixos-install \
    --system "$DESIRED_SYSTEM_TOPLEVEL" --root "$MOUNT_POINT" \
    --no-root-passwd --no-channel-copy --no-bootloader
verify_installed_revision
if ! chroot "$MOUNT_POINT" "$TARGET_SYSTEM_TOPLEVEL/sw/bin/test" -f \
  "$TARGET_SYSTEM_TOPLEVEL/etc/systemd/system/home-manager-stefan.service"; then
  echo 'Warning: the new system does not provide the expected Home Manager service.' >&2
fi
run_with_progress 'Keeping current and rollback generations' prune_usb_system_generations
phase_end

phase_begin building-squashfs 'Building replacement squashfs'
LOCAL_SQUASHFS="$STAGE_DIR/nix-store.squashfs"
# Nix opens even read-only stores by ensuring .links exists; retain the empty
# directory while omitting the optimiser's hard-link pool.
run_with_progress 'Building replacement squashfs' mksquashfs "$STAGE_STORE" "$LOCAL_SQUASHFS" \
  -noappend -comp zstd -Xcompression-level 3 -b 1048576 -processors "$(nproc)" -wildcards -e '.links/*'
report_image built "$LOCAL_SQUASHFS"
phase_end

phase_begin verifying-closures 'Verifying packages in the completed image'
run_with_progress 'Verifying current and rollback package contents' verify_image_closures "$LOCAL_SQUASHFS"
# shellcheck disable=SC2016
run_with_progress 'Hashing completed image' bash -c 'sha256sum -- "$1" > "$2"' _ "$LOCAL_SQUASHFS" "$UPDATE_USB_TMP_DIR/image.sha256"
IMAGE_SHA256="$(cut -d ' ' -f1 "$UPDATE_USB_TMP_DIR/image.sha256")"
detach_target_stage
phase_end

phase_begin copying-image 'Copying replacement image to USB'
CANDIDATE_SQUASHFS="$MOUNT_POINT/nix-store.squashfs.tmp"
METADATA_BYTES="$(du -s -B1 "$STAGE_STATE" | cut -f1)"
if [ "$MODE" = prebuild ]; then
  require_free_space "$MOUNT_POINT" "$(( $(stat -c %s "$LOCAL_SQUASHFS") + METADATA_BYTES + 16777216 ))" 'replacement image and Nix metadata'
  copy_with_progress "$LOCAL_SQUASHFS" "$CANDIDATE_SQUASHFS" 0 100 'Copying replacement image to USB'
else
  require_free_space "$MOUNT_POINT" "$((METADATA_BYTES + 16777216))" 'replacement Nix metadata'
  mv -T "$LOCAL_SQUASHFS" "$CANDIDATE_SQUASHFS"
fi
report_image candidate "$CANDIDATE_SQUASHFS"
phase_end

phase_begin flushing-image 'Flushing copied image writes to USB'
run_with_progress 'Flushing copied image writes to USB' sync -f "$CANDIDATE_SQUASHFS"
phase_end
phase_begin preparing-publication 'Preparing pending USB metadata'
run_with_progress 'Preparing pending USB metadata' prepare_usb_transaction "$CANDIDATE_SQUASHFS" "$STAGE_STATE"
phase_end
resume_usb_transaction
report_image published "$MOUNT_POINT/nix-store.squashfs"
CURRENT_PHASE='done'
echo "Published system: $TARGET_SYSTEM_TOPLEVEL"
# The EXIT handler flushes cleanup and reports completion only after unmounting.
