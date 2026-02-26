#!/usr/bin/env bash
set -e

USB_DEV="/dev/sdc"
USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
FLAKE_DIR="/home/stefan/system_manifest"

echo "Updating NixOS USB Persistent Drive..."

# Ensure we are root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
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

# Install / Update
echo "Running nixos-install..."
nixos-install --flake "$FLAKE_DIR#usb" --root $MOUNT_POINT --no-root-passwd

# Cleanup
echo "Unmounting..."
umount $MOUNT_POINT/boot
umount $MOUNT_POINT
cryptsetup close "$USB_MAPPER_NAME"

echo "Done! The USB drive has been updated."
