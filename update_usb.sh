#!/usr/bin/env bash
set -euo pipefail

USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$SCRIPT_DIR"
NIX_SHELL_PACKAGES=(squashfsTools cryptsetup util-linux coreutils findutils)
REQUIRED_TOOLS=(nixos-install cryptsetup mount umount find rm du cut nproc)
OPENED_MAPPER=0
MOUNTED_ROOT=0
MOUNTED_BOOT=0

usage() {
  cat <<EOF
Usage:
  sudo ./update_usb.sh [path-to-flake-dir]

Defaults:
  flake dir: $FLAKE_DIR
  usb root:  $USB_ROOT_PART
  usb boot:  $USB_BOOT_DEV
EOF
}

# Self-wrap: re-exec inside nix-shell if mksquashfs is missing
if ! command -v mksquashfs >/dev/null 2>&1; then
  if [ "${USB_UPDATE_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
    REEXEC_CMD=$(printf '%q ' "$0" "$@")
    echo "Entering nix-shell for required USB update tools..."
    exec nix-shell -p "${NIX_SHELL_PACKAGES[@]}" --run "USB_UPDATE_IN_NIX_SHELL=1 ${REEXEC_CMD}"
  fi
  echo "Error: mksquashfs is missing and nix-shell is unavailable."
  echo "Run manually:"
  echo "  sudo nix-shell -p ${NIX_SHELL_PACKAGES[*]} --run './update_usb.sh'"
  exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  usage
  exit 1
fi

if [ "$#" -eq 1 ]; then
  FLAKE_DIR="$1"
fi

# Ensure we are root
if [ "$EUID" -ne 0 ]; then
  echo "Error: please run as root (sudo)"
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
  echo "Run sudo ./setup_persistent_usb.sh /dev/sdX first, then retry."
  exit 1
fi

if [ ! -e "$USB_BOOT_DEV" ]; then
  echo "Error: USB boot partition not found at $USB_BOOT_DEV"
  echo "Run sudo ./setup_persistent_usb.sh /dev/sdX first, then retry."
  exit 1
fi

if mountpoint -q "$MOUNT_POINT"; then
  echo "Error: $MOUNT_POINT is already mounted. Refusing to continue."
  echo "Please unmount it first to avoid touching the wrong filesystem."
  exit 1
fi

# Cleanup handler — always unmount and close LUKS, even on failure
cleanup() {
  echo "Cleaning up mounts..."
  if [ "$MOUNTED_BOOT" -eq 1 ]; then
    umount "$MOUNT_POINT/boot" 2>/dev/null || true
  fi
  if [ "$MOUNTED_ROOT" -eq 1 ]; then
    umount "$MOUNT_POINT" 2>/dev/null || true
  fi
  if [ "$OPENED_MAPPER" -eq 1 ]; then
    cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "=== USB Update: Opening LUKS ==="
if [ ! -e "$USB_ROOT_DEV" ]; then
  cryptsetup open "$USB_ROOT_PART" "$USB_MAPPER_NAME"
  OPENED_MAPPER=1
fi

# Unmount if already mounted elsewhere
umount "$MOUNT_POINT/boot" 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

echo "=== USB Update: Mounting ==="
mount "$USB_ROOT_DEV" "$MOUNT_POINT"
MOUNTED_ROOT=1
mkdir -p "$MOUNT_POINT/boot"
mount "$USB_BOOT_DEV" "$MOUNT_POINT/boot"
MOUNTED_BOOT=1

# Wipe stale Nix state so nixos-install starts fresh.
# Previous runs delete store paths but the db still references them,
# causing "No such file or directory" on the next install.
echo "=== USB Update: Cleaning stale Nix state ==="
rm -rf "$MOUNT_POINT/nix/var/nix/db"
rm -rf "$MOUNT_POINT/nix/var/nix/profiles"
find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

echo "=== USB Update: Installing NixOS ==="
nixos-install --flake "$FLAKE_DIR#usb" --root "$MOUNT_POINT" --no-root-passwd

# Build squashfs from the installed Nix store.
# The USB boots from this compressed read-only image (via overlayfs).
# Sequential reads from squashfs are dramatically faster than random
# ext4 reads through LUKS on USB hardware.
echo "=== USB Update: Building squashfs (this takes 15-30 minutes) ==="
rm -f "$MOUNT_POINT/nix-store.squashfs"
mksquashfs "$MOUNT_POINT/nix/store" "$MOUNT_POINT/nix-store.squashfs" \
  -comp zstd \
  -Xcompression-level 3 \
  -b 1048576 \
  -processors "$(nproc)"

SQFS_SIZE=$(du -sh "$MOUNT_POINT/nix-store.squashfs" | cut -f1)
echo "squashfs image: $SQFS_SIZE"

# Clean the ext4 store — overlay uses squashfs at boot, so these are dead weight.
# Use find to avoid ARG_MAX with 500k+ store paths.
echo "=== USB Update: Cleaning ext4 store ==="
find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
rm -rf "$MOUNT_POINT/nix/var/nix/db"

# trap EXIT handles unmount and LUKS close
echo "=== USB Update: Done ==="
echo "Boot flow: LUKS unlock → squashfs overlay on /nix/store → fast reads"
