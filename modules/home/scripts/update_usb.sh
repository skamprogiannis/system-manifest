#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
DEFAULT_MODE="prebuild"
MODE="$DEFAULT_MODE"
FLAKE_DIR="$PWD"
NIX_SHELL_PACKAGES=(squashfsTools cryptsetup util-linux coreutils findutils gnused)
REQUIRED_TOOLS=(nixos-install cryptsetup mount umount find rm du cut nproc mountpoint chroot sed mktemp cp mv date)
OPENED_MAPPER=0
MOUNTED_ROOT=0
MOUNTED_BOOT=0
MOUNTED_STAGE_STORE=0
CANCELED=0
CURRENT_PHASE="startup"
STAGE_DIR=""
STAGE_STORE=""
LOCAL_SQUASHFS=""
PHASE_LABEL=""
PHASE_STARTED_AT=0
TIMINGS=()
ORIGINAL_ARGS=("$@")

usage() {
  cat <<EOF
Usage:
  sudo update-usb [--mode prebuild|in-place] [--in-place] [path-to-flake-dir]

Defaults:
  mode:      $DEFAULT_MODE
  flake dir: $PWD
  usb root:  $USB_ROOT_PART
  usb boot:  $USB_BOOT_DEV

Examples:
  sudo update-usb /path/to/system-manifest/checkouts/main
  sudo update-usb --mode prebuild /path/to/system-manifest/checkouts/main
  sudo update-usb --in-place /path/to/system-manifest/checkouts/main
EOF
}

parse_args() {
  local positional=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        if [ "$#" -lt 2 ]; then
          echo "Error: --mode requires a value: prebuild or in-place."
          usage
          exit 1
        fi
        case "$2" in
          prebuild|in-place)
            MODE="$2"
            ;;
          *)
            echo "Error: invalid mode '$2'. Use prebuild or in-place."
            usage
            exit 1
            ;;
        esac
        shift 2
        ;;
      --mode=*)
        local mode_value="${1#*=}"
        case "$mode_value" in
          prebuild|in-place)
            MODE="$mode_value"
            ;;
          *)
            echo "Error: invalid mode '$mode_value'. Use prebuild or in-place."
            usage
            exit 1
            ;;
        esac
        shift
        ;;
      --in-place)
        MODE="in-place"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          positional+=("$1")
          shift
        done
        ;;
      -*)
        echo "Error: unknown option '$1'."
        usage
        exit 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#positional[@]}" -gt 1 ]; then
    usage
    exit 1
  fi

  if [ "${#positional[@]}" -eq 1 ]; then
    FLAKE_DIR="${positional[0]}"
  fi
}

parse_args "$@"

if ! command -v mksquashfs >/dev/null 2>&1; then
  if [ "${USB_UPDATE_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
    REEXEC_ARGS=""
    for arg in "${ORIGINAL_ARGS[@]}"; do
      REEXEC_ARGS+=" $(printf '%q' "$arg")"
    done
    echo "Entering nix-shell for required USB update tools..."
    exec nix-shell -p "${NIX_SHELL_PACKAGES[@]}" --run "USB_UPDATE_IN_NIX_SHELL=1 bash \"$0\"${REEXEC_ARGS}"
  fi
  echo "Error: mksquashfs is missing and nix-shell is unavailable."
  echo "Run manually:"
  echo "  sudo nix-shell -p ${NIX_SHELL_PACKAGES[*]} --run '$SCRIPT_NAME /path/to/system-manifest/checkouts/<worktree>'"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: please run with sudo."
  echo "Example: sudo update-usb /path/to/system-manifest/checkouts/<worktree>"
  exit 1
fi

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool '$tool' is not available in PATH."
    exit 1
  fi
done

if [ ! -d "$FLAKE_DIR" ] || [ ! -f "$FLAKE_DIR/flake.nix" ]; then
  echo "Error: flake directory '$FLAKE_DIR' is invalid (missing flake.nix)."
  exit 1
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

cleanup() {
  if [ "$CANCELED" -eq 1 ]; then
    echo "=== USB Update: Cleanup after cancellation ==="
  else
    echo "Cleaning up mounts..."
  fi

  if [ "$MOUNTED_STAGE_STORE" -eq 1 ]; then
    umount "$MOUNT_POINT/nix/store" 2>/dev/null || true
  fi
  if [ "$MOUNTED_BOOT" -eq 1 ]; then
    umount "$MOUNT_POINT/boot" 2>/dev/null || true
  fi
  if [ "$MOUNTED_ROOT" -eq 1 ]; then
    umount "$MOUNT_POINT" 2>/dev/null || true
  fi
  if [ "$OPENED_MAPPER" -eq 1 ]; then
    cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true
  fi

  if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
    rm -rf "$STAGE_DIR" 2>/dev/null || true
  fi

  if [ "$CANCELED" -eq 1 ]; then
    echo "Canceled during phase: $CURRENT_PHASE"
    echo "You can safely retry: sudo update-usb /path/to/system-manifest/checkouts/<worktree>"
  fi
}

cancel_update() {
  local signal="$1"
  local exit_code=130
  if [ "$signal" = "TERM" ]; then
    exit_code=143
  fi

  CANCELED=1
  echo
  echo "=== USB Update: Canceled ($signal) ==="
  echo "Interrupt received; attempting safe cleanup."
  exit "$exit_code"
}

trap cleanup EXIT
trap 'cancel_update INT' INT
trap 'cancel_update TERM' TERM

phase_begin() {
  CURRENT_PHASE="$1"
  PHASE_LABEL="$2"
  PHASE_STARTED_AT="$(date +%s)"
  echo "=== USB Update: $PHASE_LABEL ==="
}

phase_end() {
  local phase_ended_at phase_elapsed
  phase_ended_at="$(date +%s)"
  phase_elapsed=$((phase_ended_at - PHASE_STARTED_AT))
  TIMINGS+=("$PHASE_LABEL|$phase_elapsed")
}

print_timing_summary() {
  if [ "${#TIMINGS[@]}" -eq 0 ]; then
    return
  fi

  local total=0
  echo "=== USB Update: Timing Summary ==="
  for timing in "${TIMINGS[@]}"; do
    local label="${timing%%|*}"
    local seconds="${timing##*|}"
    total=$((total + seconds))
    printf '  - %s: %ss\n' "$label" "$seconds"
  done
  printf '  - total: %ss\n' "$total"
}

phase_begin "opening-luks" "Opening LUKS"
if [ ! -e "$USB_ROOT_DEV" ]; then
  cryptsetup open "$USB_ROOT_PART" "$USB_MAPPER_NAME"
  OPENED_MAPPER=1
fi
phase_end

phase_begin "mounting" "Mounting"
umount "$MOUNT_POINT/boot" 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

mount "$USB_ROOT_DEV" "$MOUNT_POINT"
MOUNTED_ROOT=1
mkdir -p "$MOUNT_POINT/boot"
mount "$USB_BOOT_DEV" "$MOUNT_POINT/boot"
MOUNTED_BOOT=1
phase_end

phase_begin "cleaning-stale-nix-state" "Cleaning stale Nix state"
rm -rf "$MOUNT_POINT/nix/var/nix/db"
rm -rf "$MOUNT_POINT/nix/var/nix/profiles"
find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
phase_end

if [ "$MODE" = "prebuild" ]; then
  phase_begin "preparing-prebuild-stage" "Preparing local prebuild stage"
  STAGE_DIR="$(mktemp -d /var/tmp/update-usb-stage.XXXXXX)"
  STAGE_STORE="$STAGE_DIR/store"
  mkdir -p "$STAGE_STORE"
  mkdir -p "$MOUNT_POINT/nix/store"
  mount --bind "$STAGE_STORE" "$MOUNT_POINT/nix/store"
  MOUNTED_STAGE_STORE=1
  phase_end
fi

phase_begin "installing-nixos" "Installing NixOS (${MODE})"
nixos-install --flake "$FLAKE_DIR#usb" --root "$MOUNT_POINT" --no-root-passwd
phase_end

phase_begin "activating-home-manager" "Activating Home Manager"
HM_SERVICE="$MOUNT_POINT/etc/systemd/system/home-manager-stefan.service"
if [ ! -f "$HM_SERVICE" ]; then
  echo "Error: expected Home Manager service not found at $HM_SERVICE"
  exit 1
fi

HM_EXEC=$(sed -n 's/^ExecStart=//p' "$HM_SERVICE" | head -n1)
if [ -z "$HM_EXEC" ]; then
  echo "Error: could not determine Home Manager activation command from $HM_SERVICE"
  exit 1
fi

chroot "$MOUNT_POINT" /nix/var/nix/profiles/system/sw/bin/su - stefan -c \
  "HOME_MANAGER_BACKUP_EXT=backup $HM_EXEC"
phase_end

if [ "$MODE" = "prebuild" ]; then
  phase_begin "building-squashfs" "Building squashfs locally (desktop SSD)"
  LOCAL_SQUASHFS="$STAGE_DIR/nix-store.squashfs"
  rm -f "$LOCAL_SQUASHFS"
  mksquashfs "$STAGE_STORE" "$LOCAL_SQUASHFS" \
    -comp zstd \
    -Xcompression-level 3 \
    -b 1048576 \
    -processors "$(nproc)"
  SQFS_SIZE="$(du -sh "$LOCAL_SQUASHFS" | cut -f1)"
  echo "local squashfs image: $SQFS_SIZE"
  phase_end

  phase_begin "syncing-squashfs" "Syncing squashfs to USB"
  umount "$MOUNT_POINT/nix/store"
  MOUNTED_STAGE_STORE=0
  rm -f "$MOUNT_POINT/nix-store.squashfs.tmp" "$MOUNT_POINT/nix-store.squashfs"
  cp "$LOCAL_SQUASHFS" "$MOUNT_POINT/nix-store.squashfs.tmp"
  mv "$MOUNT_POINT/nix-store.squashfs.tmp" "$MOUNT_POINT/nix-store.squashfs"
  SQFS_SIZE="$(du -sh "$MOUNT_POINT/nix-store.squashfs" | cut -f1)"
  echo "usb squashfs image: $SQFS_SIZE"
  phase_end
else
  phase_begin "building-squashfs" "Building squashfs in-place on USB (slow path)"
  rm -f "$MOUNT_POINT/nix-store.squashfs"
  mksquashfs "$MOUNT_POINT/nix/store" "$MOUNT_POINT/nix-store.squashfs" \
    -comp zstd \
    -Xcompression-level 3 \
    -b 1048576 \
    -processors "$(nproc)"
  SQFS_SIZE="$(du -sh "$MOUNT_POINT/nix-store.squashfs" | cut -f1)"
  echo "squashfs image: $SQFS_SIZE"
  phase_end
fi

phase_begin "cleaning-ext4-store" "Cleaning ext4 store"
find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
rm -rf "$MOUNT_POINT/nix/var/nix/db"
phase_end

CURRENT_PHASE="done"
echo "=== USB Update: Done ==="
echo "Mode used: $MODE"
print_timing_summary
echo "Boot flow: LUKS unlock -> squashfs overlay on /nix/store -> fast reads"
