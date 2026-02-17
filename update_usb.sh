#!/usr/bin/env bash
set -e

# Define paths and devices
USB_ROOT_DEV="/dev/mapper/luks-51e2d6a1-27ac-4721-933b-eb37c40a59df"
USB_BOOT_DEV="/dev/sdc1"
MOUNT_POINT="/mnt"
FLAKE_DIR="/home/stefan/system_manifest"

echo "Updating NixOS USB Persistent Drive..."

# Ensure we are root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Unmount if already mounted elsewhere
echo "Unmounting existing mounts for USB..."
umount /run/media/stefan/NIXOS_USB_ROOT 2>/dev/null || true
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
# We use --no-root-passwd to avoid setting a new root password (rely on config)
# We use --root to specify target
nixos-install --flake "$FLAKE_DIR#usb" --root $MOUNT_POINT --no-root-passwd

# Cleanup
echo "Unmounting..."
umount $MOUNT_POINT/boot
umount $MOUNT_POINT

echo "Done! The USB drive has been updated."
