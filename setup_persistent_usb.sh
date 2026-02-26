#!/usr/bin/env bash
set -e

USB_DEV="/dev/sdc"
USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

echo "WARNING: THIS WILL COMPLETELY WIPE $USB_DEV AND DESTROY ALL DATA!"
read -p "Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborting."
  exit 1
fi

echo "Unmounting existing partitions..."
umount ${USB_DEV}* 2>/dev/null || true
cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true

echo "Wiping partition table on $USB_DEV..."
wipefs -a "$USB_DEV"
sgdisk --zap-all "$USB_DEV"

echo "Creating new partitions..."
# 1GB EFI boot partition
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:NIXOS_BOOT "$USB_DEV"
# Remaining space for LUKS root
sgdisk -n 2:0:0 -t 2:8309 -c 2:NIXOS_USB_CRYPT "$USB_DEV"

# Ensure udev notices the new partitions before formatting
partprobe "$USB_DEV"
sleep 2

echo "Formatting Boot partition ($USB_DEV"1")..."
mkfs.vfat -F 32 -n NIXOS_BOOT "${USB_DEV}1"

echo "Formatting Root partition ($USB_DEV"2") with LUKS..."
echo "Please enter a password for the USB encryption (default: nixos)"
cryptsetup luksFormat --type luks2 "${USB_DEV}2"
echo "Opening LUKS container..."
cryptsetup open "${USB_DEV}2" "$USB_MAPPER_NAME"

echo "Formatting internal ext4 filesystem..."
mkfs.ext4 -L NIXOS_USB_ROOT "$USB_ROOT_DEV"

echo "USB is partitioned and formatted! Run sudo ./update_usb.sh to install NixOS."
