#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

: "${USB_ROOT_PART:?}"
: "${USB_BOOT_DEV:?}"
: "${PREFERRED_USB_MAPPER_NAME:?}"

if [ -z "${USB_UPDATE_LIB_DIR:-}" ]; then
  USB_UPDATE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fi

# shellcheck disable=SC1090
source "$USB_UPDATE_LIB_DIR/args.sh"
# shellcheck disable=SC1090
source "$USB_UPDATE_LIB_DIR/cleanup.sh"
# shellcheck disable=SC1090
source "$USB_UPDATE_LIB_DIR/metadata.sh"
# shellcheck disable=SC1090
source "$USB_UPDATE_LIB_DIR/phases.sh"
# shellcheck disable=SC1090
source "$USB_UPDATE_LIB_DIR/squashfs.sh"

SCRIPT_NAME="$(basename "$0")"
USB_MAPPER_NAME="$PREFERRED_USB_MAPPER_NAME"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
DEFAULT_MODE="prebuild"
MODE="$DEFAULT_MODE"
FLAKE_DIR="$PWD"
NIX_SHELL_PACKAGES=(squashfsTools cryptsetup util-linux coreutils findutils gnused)
REQUIRED_TOOLS=(nixos-install cryptsetup mount umount findmnt find rm du cut sort nproc mountpoint sed mktemp cp mv date chroot lsblk sleep sync stat cat tr tail)
FORCE_UPDATE=0
VERBOSE=0
CLOSE_MAPPER_ON_CLEANUP=0
MOUNTED_ROOT=0
MOUNTED_BOOT=0
MOUNTED_STAGE_STORE=0
CANCELED=0
CURRENT_PHASE="startup"
STAGE_DIR=""
STAGE_STORE=""
LOCAL_SQUASHFS=""
FINAL_SQUASHFS=""
EXPECTED_CONFIG_REVISION=""
DESIRED_SYSTEM_TOPLEVEL=""
DESIRED_INIT_RELATIVE=""
TARGET_CONFIG_REVISION=""
TARGET_NIXOS_VERSION=""
TARGET_SYSTEM_TOPLEVEL=""
TARGET_INIT_RELATIVE=""
PHASE_LABEL=""
PHASE_STARTED_AT=0
TIMINGS=()
LAST_PROGRESS_LINE=""
ORIGINAL_ARGS=("$@")

parse_args "$@"

if ! command -v mksquashfs >/dev/null 2>&1 || ! command -v unsquashfs >/dev/null 2>&1; then
  if [ "${USB_UPDATE_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
    REEXEC_ARGS=""
    for arg in "${ORIGINAL_ARGS[@]}"; do
      REEXEC_ARGS+=" $(printf '%q' "$arg")"
    done
    echo "Entering nix-shell for required USB update tools..."
    exec nix-shell -p "${NIX_SHELL_PACKAGES[@]}" --run "USB_UPDATE_IN_NIX_SHELL=1 bash \"$0\"${REEXEC_ARGS}"
  fi
  echo "Error: required squashfs tools are missing and nix-shell is unavailable."
  echo "Run manually:"
  echo "  sudo nix-shell -p ${NIX_SHELL_PACKAGES[*]} --run '$SCRIPT_NAME /path/to/system-manifest/main'"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: please run with sudo."
  echo "Example: sudo update-usb /path/to/system-manifest/main"
  exit 1
fi

for tool in nix "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool '$tool' is not available in PATH."
    exit 1
  fi
done

if [ ! -d "$FLAKE_DIR" ] || [ ! -f "$FLAKE_DIR/flake.nix" ]; then
  echo "Error: flake directory '$FLAKE_DIR' is invalid (missing flake.nix)."
  echo "Pass a worktree path containing flake.nix, for example /path/to/system-manifest/main."
  exit 1
fi

EXPECTED_CONFIG_REVISION="$(read_expected_config_revision || true)"
if ! capture_desired_system_metadata; then
  echo "Error: refusing to update USB before touching it because the desired USB system path could not be evaluated." >&2
  exit 1
fi
echo "Source flake: $FLAKE_DIR"
if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
  echo "Desired revision: $EXPECTED_CONFIG_REVISION"
else
  echo "Warning: could not resolve desired USB revision from $FLAKE_DIR"
fi
if [ -n "$DESIRED_SYSTEM_TOPLEVEL" ]; then
  verbose_log "Desired system: $DESIRED_SYSTEM_TOPLEVEL"
fi

if [ ! -e "$USB_ROOT_PART" ]; then
  echo "Error: USB root partition not found at $USB_ROOT_PART"
  echo "Run sudo setup-persistent-usb /dev/sdX first, then retry."
  exit 1
fi

if [ ! -e "$USB_BOOT_DEV" ]; then
  echo "Error: USB boot partition not found at $USB_BOOT_DEV"
  echo "Run sudo setup-persistent-usb /dev/sdX first, then retry."
  exit 1
fi

if mountpoint -q "$MOUNT_POINT"; then
  echo "Error: $MOUNT_POINT is already mounted. Refusing to continue."
  echo "Please unmount it first to avoid touching the wrong filesystem."
  exit 1
fi

trap cleanup EXIT
trap 'cancel_update INT' INT
trap 'cancel_update TERM' TERM

phase_begin "opening-luks" "Opening LUKS" 0
refresh_usb_mapper
if [ ! -e "$USB_ROOT_DEV" ]; then
  cryptsetup open "$USB_ROOT_PART" "$PREFERRED_USB_MAPPER_NAME"
  refresh_usb_mapper
fi
CLOSE_MAPPER_ON_CLEANUP=1
phase_end

phase_begin "mounting" "Mounting" 2
umount "$MOUNT_POINT/boot" 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

mount "$USB_ROOT_DEV" "$MOUNT_POINT"
MOUNTED_ROOT=1
mkdir -p "$MOUNT_POINT/boot"
mount "$USB_BOOT_DEV" "$MOUNT_POINT/boot"
MOUNTED_BOOT=1
phase_end

phase_begin "checking-existing-squashfs" "Checking existing USB squashfs" 3
if ! skip_if_existing_squashfs_is_current; then
  phase_end
  CURRENT_PHASE="done"
  print_timing_summary
  exit 0
fi
phase_end

phase_begin "cleaning-stale-nix-state" "Cleaning stale Nix state" 4
rm -rf "$MOUNT_POINT/nix/var/nix/db"
rm -rf "$MOUNT_POINT/nix/var/nix/profiles"
if [ "$MODE" = "in-place" ]; then
  find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
else
  verbose_log "Prebuild mode: skipping ext4 /nix/store wipe (slow USB random I/O)."
fi
phase_end

if [ "$MODE" = "prebuild" ]; then
  phase_begin "preparing-prebuild-stage" "Preparing local prebuild stage" 5
  STAGE_DIR="$(mktemp -d /var/tmp/update-usb-stage.XXXXXX)"
  STAGE_STORE="$STAGE_DIR/store"
  mkdir -p "$STAGE_STORE"
  mkdir -p "$MOUNT_POINT/nix/store"
  mount --bind "$STAGE_STORE" "$MOUNT_POINT/nix/store"
  MOUNTED_STAGE_STORE=1
  phase_end
fi

if [ "$MODE" = "prebuild" ]; then
  progress_plan_init 1080 120 10 5 10 360 660 10 5
else
  progress_plan_init 1080 120 10 5 10 1800 10 600
fi

phase_begin_estimated "building-usb-system" "Building USB system" 1080 6
run_logged_progress "Building USB system" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END" "$PHASE_PROGRESS_ESTIMATE" nix build --no-link "$FLAKE_DIR#nixosConfigurations.usb.config.system.build.toplevel"
phase_end_estimated

phase_begin_estimated "installing-nixos" "Installing NixOS" 120
run_logged_progress "Installing NixOS" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END" "$PHASE_PROGRESS_ESTIMATE" nixos-install --system "$DESIRED_SYSTEM_TOPLEVEL" --root "$MOUNT_POINT" --no-root-passwd
phase_end_estimated

phase_begin_estimated "verifying-installed-revision" "Verifying installed revision" 10
verify_installed_revision
phase_end_estimated

phase_begin_estimated "verifying-home-manager" "Verifying Home Manager" 5
HM_SERVICE="$MOUNT_POINT/etc/systemd/system/home-manager-stefan.service"
if [ -f "$HM_SERVICE" ]; then
  verbose_log "Home Manager service found. It will activate on first boot."
else
  echo "Warning: Home Manager service not found at $HM_SERVICE"
  echo "First boot may not have the full user environment."
fi
phase_end_estimated

phase_begin_estimated "preparing-home-manager-state" "Preparing Home Manager state" 10
# Home Manager's first-boot activation writes GC roots and per-user profiles
# under ~/.local/state. Seed the directories in the target root now so the
# activation service can succeed on a fresh USB image.
chroot "$MOUNT_POINT" /nix/var/nix/profiles/system/sw/bin/install -d -m 0755 -o stefan -g users \
  /home/stefan/.local/state/home-manager \
  /home/stefan/.local/state/home-manager/gcroots \
  /home/stefan/.local/state/nix \
  /home/stefan/.local/state/nix/profiles
phase_end_estimated

if [ "$MODE" = "prebuild" ]; then
  phase_begin_estimated "building-squashfs" "Building squashfs locally (desktop SSD)" 360
  LOCAL_SQUASHFS="$STAGE_DIR/nix-store.squashfs"
  rm -f "$LOCAL_SQUASHFS"
  run_logged_progress "Building squashfs" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END" "$PHASE_PROGRESS_ESTIMATE" mksquashfs "$STAGE_STORE" "$LOCAL_SQUASHFS" \
    -comp zstd \
    -Xcompression-level 3 \
    -b 1048576 \
    -processors "$(nproc)"
  SQFS_SIZE="$(du -sh "$LOCAL_SQUASHFS" | cut -f1)"
  echo "Local squashfs image: $SQFS_SIZE"
  phase_end_estimated

  phase_begin_estimated "syncing-squashfs" "Syncing squashfs to USB" 660
  umount "$MOUNT_POINT/nix/store"
  MOUNTED_STAGE_STORE=0
  rm -f "$MOUNT_POINT/nix-store.squashfs.tmp" "$MOUNT_POINT/nix-store.squashfs"
  echo "Copying $SQFS_SIZE squashfs image to USB; this can take several minutes."
  copy_with_progress "$LOCAL_SQUASHFS" "$MOUNT_POINT/nix-store.squashfs.tmp" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END" "Syncing squashfs to USB"
  mv "$MOUNT_POINT/nix-store.squashfs.tmp" "$MOUNT_POINT/nix-store.squashfs"
  FINAL_SQUASHFS="$MOUNT_POINT/nix-store.squashfs"
  SQFS_SIZE="$(du -sh "$MOUNT_POINT/nix-store.squashfs" | cut -f1)"
  echo "USB squashfs image: $SQFS_SIZE"
  phase_end_estimated
else
  phase_begin_estimated "building-squashfs" "Building squashfs in-place on USB (slow path)" 1800
  rm -f "$MOUNT_POINT/nix-store.squashfs"
  run_logged_progress "Building squashfs" "$PHASE_PROGRESS_START" "$PHASE_PROGRESS_END" "$PHASE_PROGRESS_ESTIMATE" mksquashfs "$MOUNT_POINT/nix/store" "$MOUNT_POINT/nix-store.squashfs" \
    -comp zstd \
    -Xcompression-level 3 \
    -b 1048576 \
    -processors "$(nproc)"
  FINAL_SQUASHFS="$MOUNT_POINT/nix-store.squashfs"
  SQFS_SIZE="$(du -sh "$MOUNT_POINT/nix-store.squashfs" | cut -f1)"
  echo "Squashfs image: $SQFS_SIZE"
  phase_end_estimated
fi

phase_begin_estimated "verifying-squashfs" "Verifying USB squashfs" 10
verify_squashfs_contains_system "$FINAL_SQUASHFS"
phase_end_estimated

if [ "$MODE" = "prebuild" ]; then
  phase_begin_estimated "cleaning-ext4-store" "Cleaning ext4 store" 5
else
  phase_begin_estimated "cleaning-ext4-store" "Cleaning ext4 store" 600
fi
if [ "$MODE" = "in-place" ]; then
  find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
else
  verbose_log "Prebuild mode: leaving ext4 /nix/store untouched."
fi
# Preserve the target Nix DB. The booted squashfs store still needs valid DB
# registration so Home Manager can realize its generation and add GC roots.
phase_end_estimated

CURRENT_PHASE="done"
progress_set 100 "Done"
echo "Mode: $MODE"
if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
  echo "Desired revision: $EXPECTED_CONFIG_REVISION"
fi
if [ -n "$TARGET_CONFIG_REVISION" ]; then
  echo "Written revision: $TARGET_CONFIG_REVISION"
fi
if [ -n "$TARGET_SYSTEM_TOPLEVEL" ]; then
  verbose_log "Written system: $TARGET_SYSTEM_TOPLEVEL"
fi
print_timing_summary
echo "Boot flow: LUKS unlock -> squashfs overlay on /nix/store -> fast reads"
echo "After boot, verify with: nixos-version --json && readlink -f /run/current-system"
