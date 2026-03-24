#!/usr/bin/env bash
set -euo pipefail

USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
NIX_SHELL_PACKAGES=(gptfdisk parted cryptsetup dosfstools e2fsprogs util-linux)
REQUIRED_TOOLS=(lsblk wipefs sgdisk partprobe udevadm mkfs.vfat cryptsetup mkfs.ext4)
OPENED_MAPPER=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./setup_persistent_usb.sh /dev/sdX

Creates a fresh persistent NixOS USB with:
  - GPT partition table
  - 1 GiB EFI partition (label: NIXOS_BOOT)
  - LUKS2 root partition (partlabel: NIXOS_USB_CRYPT)
  - ext4 filesystem inside LUKS (label: NIXOS_USB_ROOT)
EOF
}

cleanup() {
  if [ "$OPENED_MAPPER" -eq 1 ]; then
    cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: please run as root (sudo)"
  exit 1
fi

USB_DEV="$1"

MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [ "${#MISSING_TOOLS[@]}" -gt 0 ]; then
  if [ "${USB_SETUP_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
    REEXEC_CMD=$(printf '%q ' "$0" "$@")
    echo "Missing required tools (${MISSING_TOOLS[*]}). Re-running inside nix-shell..."
    exec nix-shell -p "${NIX_SHELL_PACKAGES[@]}" --run "USB_SETUP_IN_NIX_SHELL=1 ${REEXEC_CMD}"
  fi

  echo "Error: missing required tools: ${MISSING_TOOLS[*]}"
  echo "Run manually:"
  echo "  sudo nix-shell -p ${NIX_SHELL_PACKAGES[*]} --run './setup_persistent_usb.sh /dev/sdX'"
  exit 1
fi

if [ ! -b "$USB_DEV" ]; then
  echo "Error: $USB_DEV is not a block device."
  exit 1
fi

if [ "$(lsblk -ndo TYPE "$USB_DEV")" != "disk" ]; then
  echo "Error: $USB_DEV is not a disk (expected TYPE=disk)."
  exit 1
fi

if lsblk -nrpo MOUNTPOINT "$USB_DEV" | awk '$1 ~ "^/($|boot($|/)|nix($|/))" {found=1} END {exit found?0:1}'; then
  echo "Error: $USB_DEV appears to host mounted system paths (/boot, /nix, or /). Refusing to continue."
  exit 1
fi

if [[ "$USB_DEV" =~ [0-9]$ ]]; then
  USB_PART_PREFIX="${USB_DEV}p"
else
  USB_PART_PREFIX="${USB_DEV}"
fi

USB_BOOT_PART="${USB_PART_PREFIX}1"
USB_CRYPT_PART="${USB_PART_PREFIX}2"

echo "Target disk:"
lsblk -dno NAME,SIZE,MODEL,TRAN "$USB_DEV" | sed 's/^/  /'
echo
echo "WARNING: THIS WILL COMPLETELY WIPE $USB_DEV AND DESTROY ALL DATA!"
read -r -p "Type the exact device path to confirm: " CONFIRM
if [ "$CONFIRM" != "$USB_DEV" ]; then
  echo "Aborting."
  exit 1
fi

echo "Unmounting existing partitions on $USB_DEV..."
mapfile -t MOUNTED_PARTS < <(lsblk -nrpo NAME,MOUNTPOINT "$USB_DEV" | awk '$2 != "" {print $1}')
for part in "${MOUNTED_PARTS[@]}"; do
  echo "  unmounting $part"
  umount "$part"
done

cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true

echo "Wiping partition table on $USB_DEV..."
wipefs -af "$USB_DEV"
sgdisk --zap-all "$USB_DEV"

echo "Creating new partitions..."
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:NIXOS_BOOT "$USB_DEV"
sgdisk -n 2:0:0 -t 2:8309 -c 2:NIXOS_USB_CRYPT "$USB_DEV"

partprobe "$USB_DEV"
udevadm settle

for part in "$USB_BOOT_PART" "$USB_CRYPT_PART"; do
  for _ in {1..10}; do
    if [ -b "$part" ]; then
      break
    fi
    sleep 1
  done
  if [ ! -b "$part" ]; then
    echo "Error: partition device $part did not appear."
    exit 1
  fi
done

echo "Formatting boot partition ($USB_BOOT_PART)..."
mkfs.vfat -F 32 -n NIXOS_BOOT "$USB_BOOT_PART"

echo "Formatting root partition ($USB_CRYPT_PART) with LUKS..."
echo "Please enter a passphrase for USB encryption when prompted."
cryptsetup luksFormat --type luks2 "$USB_CRYPT_PART"
echo "Opening LUKS container..."
cryptsetup open "$USB_CRYPT_PART" "$USB_MAPPER_NAME"
OPENED_MAPPER=1

echo "Formatting internal ext4 filesystem..."
mkfs.ext4 -L NIXOS_USB_ROOT "$USB_ROOT_DEV"
cryptsetup close "$USB_MAPPER_NAME"
OPENED_MAPPER=0

echo "USB is partitioned and formatted."
echo "Next step: sudo ./update_usb.sh"
