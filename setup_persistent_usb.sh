#!/usr/bin/env bash
set -e

# ==============================================================================
# WARNING: THIS SCRIPT WILL COMPLETELY WIPE THE USB DRIVE AT /dev/sdc
# ==============================================================================

USB_DEV="/dev/sdc"
RESERVED_MB=45000  # Leave ~12GB for Ventoy ISOs, reserve 45GB for NixOS

echo "================================================================================"
echo "WARNING: This will DESTROY ALL DATA on $USB_DEV (including Ventoy ISOs)."
echo "It will install a fresh Ventoy with $RESERVED_MB MB reserved space,"
echo "and then install a persistent NixOS in that space."
echo "================================================================================"
read -p "Are you absolutely sure you want to wipe $USB_DEV? (type 'yes' to continue): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborting."
    exit 1
fi

# 1. Download and install Ventoy
echo "[1/6] Downloading Ventoy..."
wget -q -c https://github.com/ventoy/Ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz -O ventoy.tar.gz
tar -xzf ventoy.tar.gz
cd ventoy-1.0.99

echo "[2/6] Installing Ventoy to $USB_DEV with $RESERVED_MB MB reserved space..."
sudo sh Ventoy2Disk.sh -i -g -r $RESERVED_MB $USB_DEV
cd ..
rm -rf ventoy-1.0.99 ventoy.tar.gz

# Wait for kernel to re-read partition table
sleep 3

# 2. Partition the reserved space (sdc3 for Boot, sdc4 for Root)
echo "[3/6] Partitioning reserved space for NixOS..."
# Ventoy creates sdc1 (exfat) and sdc2 (EFI). 
# We add sdc3 (NIXOS_BOOT, 1GB) and sdc4 (NIXOS_USB_CRYPT, rest)
sudo parted -a optimal $USB_DEV -- mkpart primary fat32 100% -44000MB
sudo parted -a optimal $USB_DEV -- name 3 NIXOS_BOOT
sudo parted -a optimal $USB_DEV -- set 3 esp on

sudo parted -a optimal $USB_DEV -- mkpart primary ext4 -44000MB 100%
sudo parted -a optimal $USB_DEV -- name 4 NIXOS_USB_CRYPT

# Reload partition table
sudo partprobe $USB_DEV
sleep 3

# 3. Format Partitions
echo "[4/6] Formatting partitions..."
sudo mkfs.vfat -F 32 -n NIXOS_BOOT ${USB_DEV}3

echo "Setting up LUKS encryption for root (you will be prompted for a new password)..."
sudo cryptsetup luksFormat ${USB_DEV}4
sudo cryptsetup open ${USB_DEV}4 root

sudo mkfs.ext4 -L nixos /dev/mapper/root

# 4. Mount for installation
echo "[5/6] Mounting partitions to /mnt..."
sudo mount /dev/mapper/root /mnt
sudo mkdir -p /mnt/boot
sudo mount ${USB_DEV}3 /mnt/boot

# 5. Install NixOS
echo "[6/6] Installing NixOS (this will take a while)..."
# Using --no-root-passwd as the config sets a default password 'nixos' for user 'stefan'
sudo nixos-install --flake /home/stefan/system_manifest#usb --root /mnt --no-root-passwd

# Cleanup
echo "Cleaning up..."
sudo umount /mnt/boot
sudo umount /mnt
sudo cryptsetup close root

echo "Done! The USB drive is now a persistent Ventoy + NixOS hybrid."
