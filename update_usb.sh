#!/usr/bin/env bash
set -e

# Self-wrap: re-exec inside nix-shell if mksquashfs is missing
if ! command -v mksquashfs &>/dev/null; then
  echo "Entering nix-shell for squashfs-tools..."
  exec nix-shell -p squashfsTools --run "$0 $*"
fi

USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
FLAKE_DIR="/home/stefan/system-manifest"

# Ensure we are root
if [ "$EUID" -ne 0 ]; then
  echo "Error: please run as root (sudo)"
  exit 1
fi

# Cleanup handler — always unmount and close LUKS, even on failure
cleanup() {
  echo "Cleaning up mounts..."
  umount "$MOUNT_POINT/boot" 2>/dev/null || true
  umount "$MOUNT_POINT" 2>/dev/null || true
  cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== USB Update: Opening LUKS ==="
if [ ! -e "$USB_ROOT_DEV" ]; then
  cryptsetup open "$USB_ROOT_PART" "$USB_MAPPER_NAME"
fi

# Unmount if already mounted elsewhere
umount "$MOUNT_POINT/boot" 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

echo "=== USB Update: Mounting ==="
mount "$USB_ROOT_DEV" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/boot"
mount "$USB_BOOT_DEV" "$MOUNT_POINT/boot"

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

# trap EXIT handles unmount and LUKS close
echo "=== USB Update: Done ==="
echo "Boot flow: LUKS unlock → squashfs overlay on /nix/store → fast reads"
