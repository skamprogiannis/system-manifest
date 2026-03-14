#!/usr/bin/env bash
set -e

USB_DEV="/dev/sdc"
USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
FLAKE_DIR="/home/stefan/system-manifest"

echo "Updating NixOS USB Persistent Drive..."

# Ensure we are root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Ensure mksquashfs is available
if ! command -v mksquashfs &>/dev/null; then
  echo "mksquashfs not found. Run with:"
  echo "  sudo nix-shell -p squashfsTools --run ./update_usb.sh"
  exit 1
fi

# Check if LUKS is open
if [ ! -e "$USB_ROOT_DEV" ]; then
    echo "Opening LUKS container on $USB_ROOT_PART..."
    cryptsetup open "$USB_ROOT_PART" "$USB_MAPPER_NAME"
fi

# Unmount if already mounted elsewhere
echo "Unmounting existing mounts for USB..."
umount $MOUNT_POINT/boot 2>/dev/null || true
umount $MOUNT_POINT 2>/dev/null || true

# Mount Root
echo "Mounting Root ($USB_ROOT_DEV) to $MOUNT_POINT..."
mount $USB_ROOT_DEV $MOUNT_POINT

# Mount Boot
echo "Mounting Boot ($USB_BOOT_DEV) to $MOUNT_POINT/boot..."
mkdir -p $MOUNT_POINT/boot
mount $USB_BOOT_DEV $MOUNT_POINT/boot

# Install / Update (populates /nix/store on ext4 as staging area)
echo "Running nixos-install..."
nixos-install --flake "$FLAKE_DIR#usb" --root $MOUNT_POINT --no-root-passwd

# Build squashfs from the installed Nix store.
# This compressed, read-only image is what the USB actually boots from
# (via overlayfs). Sequential reads from squashfs are dramatically faster
# than random ext4 reads through LUKS on USB hardware.
echo "Building squashfs image of Nix store (this takes a few minutes)..."
rm -f $MOUNT_POINT/nix-store.squashfs
mksquashfs $MOUNT_POINT/nix/store $MOUNT_POINT/nix-store.squashfs \
  -comp zstd \
  -Xcompression-level 3 \
  -b 1048576 \
  -no-progress \
  -processors $(nproc)

SQFS_SIZE=$(du -sh $MOUNT_POINT/nix-store.squashfs | cut -f1)
echo "squashfs image created: $SQFS_SIZE"

# Clean up the ext4 store — the overlay uses squashfs at boot, so these
# files are dead weight. Keeping /nix/store dir structure intact for nixos-install.
echo "Cleaning ext4 store (overlay uses squashfs at boot)..."
rm -rf $MOUNT_POINT/nix/store/*

# Cleanup
echo "Unmounting..."
umount $MOUNT_POINT/boot
umount $MOUNT_POINT
cryptsetup close "$USB_MAPPER_NAME"

echo "Done! The USB drive has been updated."
echo "Boot flow: LUKS unlock → squashfs overlay on /nix/store → fast reads from compressed image"
