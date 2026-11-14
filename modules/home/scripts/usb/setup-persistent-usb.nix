{
  pkgs,
  usb,
}:
pkgs.writeShellScriptBin "setup-persistent-usb" ''
  set -euo pipefail
  # shellcheck disable=SC2034

  SCRIPT_NAME="$(basename "$0")"
  USB_MAPPER_NAME="${usb.mapperName}"
  USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
  NIX_SHELL_PACKAGES=(gptfdisk parted cryptsetup dosfstools e2fsprogs util-linux)
  REQUIRED_TOOLS=(lsblk wipefs sgdisk partprobe udevadm mkfs.vfat cryptsetup mkfs.ext4)
  OPENED_MAPPER=0
  ASSUME_YES=0

  # TTY & NO_COLOR aware ANSI palette
  if [ -t 1 ] && [ "''${TERM:-}" != "dumb" ] && [ -z "''${NO_COLOR:-}" ]; then
    BOLD="\033[1m"
    GREEN="\033[0;32m"
    BLUE="\033[0;34m"
    YELLOW="\033[0;33m"
    RED="\033[0;31m"
    NC="\033[0m"
  else
    BOLD=""
    GREEN=""
    BLUE=""
    YELLOW=""
    RED=""
    NC=""
  fi

  log_info() { printf "%b\n" "''${BLUE}''${BOLD}[INFO]''${NC} $*"; }
  log_step() { printf "\n%b\n" "''${BOLD}==>''${NC} ''${BOLD}$*''${NC}"; }
  log_ok()   { printf "%b\n" "''${GREEN}''${BOLD}[OK]''${NC} $*"; }
  log_warn() { printf "%b\n" "''${YELLOW}''${BOLD}[WARN]''${NC} $*"; }
  log_err()  { printf "%b\n" "''${RED}''${BOLD}[ERROR]''${NC} $*" >&2; }

  usage() {
    cat <<'EOF'
Usage:
  sudo setup-persistent-usb [OPTIONS] /dev/sdX
  sudo setup-persistent-usb [OPTIONS] sdX

Creates a fresh persistent NixOS USB with:
  - GPT partition table
  - 1 GiB EFI partition (label: ${usb.bootLabel})
  - LUKS2 root partition (partlabel: ${usb.rootPartLabel})
  - ext4 filesystem inside LUKS (label: ${usb.rootFsLabel})

Options:
  -y, --yes          Bypass confirmation prompt (for automation)
  -h, --help         Show this help message
EOF
  }

  cleanup() {
    if [ "$OPENED_MAPPER" -eq 1 ]; then
      if ! cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null; then
        log_warn "Failed to close $USB_MAPPER_NAME during cleanup; you may need to close it manually."
      fi
    fi
  }
  trap cleanup EXIT

  USB_INPUT=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      --)
        shift
        USB_INPUT="''${1:-}"
        break
        ;;
      -*)
        log_err "Unknown option '$1'."
        usage
        exit 1
        ;;
      *)
        if [ -n "$USB_INPUT" ]; then
          log_err "Unexpected argument '$1'. Only one target drive may be specified."
          usage
          exit 1
        fi
        USB_INPUT="$1"
        shift
        ;;
    esac
  done

  if [ -z "$USB_INPUT" ]; then
    usage
    exit 1
  fi

  if [ "$EUID" -ne 0 ]; then
    log_err "Please run with sudo."
    echo "Example: sudo setup-persistent-usb /dev/sdX" >&2
    exit 1
  fi

  if [[ "$USB_INPUT" != /dev/* ]]; then
    USB_DEV="/dev/$USB_INPUT"
  else
    USB_DEV="$USB_INPUT"
  fi

  MISSING_TOOLS=()
  for tool in "''${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      MISSING_TOOLS+=("$tool")
    fi
  done

  if [ "''${#MISSING_TOOLS[@]}" -gt 0 ]; then
    if [ "''${USB_SETUP_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
      REEXEC_ARGS=$(printf ' %q' "$@")
      log_info "Missing required tools (''${MISSING_TOOLS[*]}). Re-running inside nix-shell..."
      exec nix-shell -p "''${NIX_SHELL_PACKAGES[@]}" --run "USB_SETUP_IN_NIX_SHELL=1 bash \"$0\"''${REEXEC_ARGS}"
    fi

    log_err "Missing required tools: ''${MISSING_TOOLS[*]}"
    echo "Run manually:" >&2
    echo "  sudo nix-shell -p ''${NIX_SHELL_PACKAGES[*]} --run '$SCRIPT_NAME /dev/sdX'" >&2
    exit 1
  fi

  if [ ! -b "$USB_DEV" ]; then
    log_err "$USB_DEV is not a block device."
    exit 1
  fi

  if [ "$(lsblk -ndo TYPE "$USB_DEV")" != "disk" ]; then
    log_err "$USB_DEV is not a disk (expected TYPE=disk)."
    exit 1
  fi

  if lsblk -nrpo MOUNTPOINT "$USB_DEV" | awk '$1 ~ "^/($|boot($|/)|nix($|/))" {found=1} END {exit found?0:1}'; then
    log_err "$USB_DEV appears to host mounted system paths (/boot, /nix, or /). Refusing to continue."
    exit 1
  fi

  if [[ "$USB_DEV" =~ [0-9]$ ]]; then
    USB_PART_PREFIX="''${USB_DEV}p"
  else
    USB_PART_PREFIX="''${USB_DEV}"
  fi

  USB_BOOT_PART="''${USB_PART_PREFIX}1"
  USB_CRYPT_PART="''${USB_PART_PREFIX}2"

  log_info "Target disk summary:"
  lsblk -dno NAME,SIZE,MODEL,VENDOR,TRAN "$USB_DEV" 2>/dev/null | sed 's/^/  /' || lsblk -dno NAME,SIZE,MODEL,TRAN "$USB_DEV" | sed 's/^/  /'
  
  if [ "$ASSUME_YES" -eq 0 ]; then
    echo
    log_warn "THIS WILL COMPLETELY WIPE $USB_DEV AND DESTROY ALL DATA!"
    read -r -p "Type 'YES' or the exact device path ($USB_DEV) to confirm: " CONFIRM
    if [ "$CONFIRM" != "YES" ] && [ "$CONFIRM" != "$USB_DEV" ]; then
      log_info "Aborting setup. Device was not modified."
      exit 1
    fi
  fi

  log_step "Step 1/6: Unmounting existing partitions on $USB_DEV..."
  mapfile -t MOUNTED_PARTS < <(lsblk -nrpo NAME,MOUNTPOINT "$USB_DEV" | awk '$2 != "" {print $1}')
  for part in "''${MOUNTED_PARTS[@]}"; do
    log_info "Unmounting $part"
    umount "$part"
  done

  cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null || true

  log_step "Step 2/6: Wiping partition signatures and creating GPT table..."
  wipefs -af "$USB_DEV"
  sgdisk --zap-all "$USB_DEV"

  log_step "Step 3/6: Creating EFI and LUKS2 partitions..."
  sgdisk -n 1:0:+1G -t 1:ef00 -c 1:${usb.bootLabel} "$USB_DEV"
  sgdisk -n 2:0:0 -t 2:8309 -c 2:${usb.rootPartLabel} "$USB_DEV"

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
      log_err "Partition device $part did not appear."
      exit 1
    fi
  done

  log_step "Step 4/6: Formatting boot partition ($USB_BOOT_PART) as FAT32..."
  mkfs.vfat -F 32 -n ${usb.bootLabel} "$USB_BOOT_PART"

  log_step "Step 5/6: Initializing LUKS2 encryption on $USB_CRYPT_PART..."
  log_info "Please enter a passphrase for USB encryption when prompted."
  cryptsetup luksFormat --type luks2 "$USB_CRYPT_PART"
  log_info "Opening LUKS container..."
  cryptsetup open "$USB_CRYPT_PART" "$USB_MAPPER_NAME"
  OPENED_MAPPER=1

  log_step "Step 6/6: Formatting internal ext4 filesystem..."
  mkfs.ext4 -L ${usb.rootFsLabel} "$USB_ROOT_DEV"
  cryptsetup close "$USB_MAPPER_NAME"
  OPENED_MAPPER=0

  log_ok "USB partition and encryption setup complete!"
  log_info "Next step: sudo update-usb /path/to/system-manifest"
''
