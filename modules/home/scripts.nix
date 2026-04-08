{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "setup-persistent-usb" ''
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
NIX_SHELL_PACKAGES=(gptfdisk parted cryptsetup dosfstools e2fsprogs util-linux)
REQUIRED_TOOLS=(lsblk wipefs sgdisk partprobe udevadm mkfs.vfat cryptsetup mkfs.ext4)
OPENED_MAPPER=0

usage() {
  cat <<'EOF'
Usage:
  sudo setup-persistent-usb /dev/sdX
  sudo setup-persistent-usb sdX

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

if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: please run with sudo."
  echo "Example: sudo setup-persistent-usb /dev/sdX"
  exit 1
fi

USB_INPUT="$1"
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
    echo "Missing required tools (''${MISSING_TOOLS[*]}). Re-running inside nix-shell..."
    exec nix-shell -p "''${NIX_SHELL_PACKAGES[@]}" --run "USB_SETUP_IN_NIX_SHELL=1 bash \"$0\"''${REEXEC_ARGS}"
  fi

  echo "Error: missing required tools: ''${MISSING_TOOLS[*]}"
  echo "Run manually:"
  echo "  sudo nix-shell -p ''${NIX_SHELL_PACKAGES[*]} --run '$SCRIPT_NAME /dev/sdX'"
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
  USB_PART_PREFIX="''${USB_DEV}p"
else
  USB_PART_PREFIX="''${USB_DEV}"
fi

USB_BOOT_PART="''${USB_PART_PREFIX}1"
USB_CRYPT_PART="''${USB_PART_PREFIX}2"

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
for part in "''${MOUNTED_PARTS[@]}"; do
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
echo "Next step: sudo update-usb /path/to/system-manifest/checkouts/<worktree>"
    '')
    (pkgs.writeShellScriptBin "update-usb" ''
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
USB_ROOT_PART="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
USB_BOOT_DEV="/dev/disk/by-label/NIXOS_BOOT"
PREFERRED_USB_MAPPER_NAME="NIXOS_USB_CRYPT"
USB_MAPPER_NAME="$PREFERRED_USB_MAPPER_NAME"
USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
MOUNT_POINT="/mnt"
DEFAULT_MODE="prebuild"
MODE="$DEFAULT_MODE"
FLAKE_DIR="$PWD"
NIX_SHELL_PACKAGES=(squashfsTools cryptsetup util-linux coreutils findutils gnused)
REQUIRED_TOOLS=(nixos-install cryptsetup mount umount find rm du cut nproc mountpoint sed mktemp cp mv date chroot lsblk)
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
        local mode_value="''${1#*=}"
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

  if [ "''${#positional[@]}" -gt 1 ]; then
    usage
    exit 1
  fi

  if [ "''${#positional[@]}" -eq 1 ]; then
    FLAKE_DIR="''${positional[0]}"
  fi
}

parse_args "$@"

refresh_usb_mapper() {
  local existing_mapper=""
  existing_mapper=$(lsblk -nrpo NAME,TYPE "$USB_ROOT_PART" 2>/dev/null | sed -n '/ crypt$/ { s/ crypt$//; p; q; }')
  if [ -n "$existing_mapper" ]; then
    USB_ROOT_DEV="$existing_mapper"
    USB_MAPPER_NAME="''${existing_mapper##*/}"
  else
    USB_MAPPER_NAME="$PREFERRED_USB_MAPPER_NAME"
    USB_ROOT_DEV="/dev/mapper/$USB_MAPPER_NAME"
  fi
}

if ! command -v mksquashfs >/dev/null 2>&1; then
  if [ "''${USB_UPDATE_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
    REEXEC_ARGS=""
    for arg in "''${ORIGINAL_ARGS[@]}"; do
      REEXEC_ARGS+=" $(printf '%q' "$arg")"
    done
    echo "Entering nix-shell for required USB update tools..."
    exec nix-shell -p "''${NIX_SHELL_PACKAGES[@]}" --run "USB_UPDATE_IN_NIX_SHELL=1 bash \"$0\"''${REEXEC_ARGS}"
  fi
  echo "Error: mksquashfs is missing and nix-shell is unavailable."
  echo "Run manually:"
  echo "  sudo nix-shell -p ''${NIX_SHELL_PACKAGES[*]} --run '$SCRIPT_NAME /path/to/system-manifest/checkouts/<worktree>'"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: please run with sudo."
  echo "Example: sudo update-usb /path/to/system-manifest/checkouts/<worktree>"
  exit 1
fi

for tool in "''${REQUIRED_TOOLS[@]}"; do
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
  if [ "''${#TIMINGS[@]}" -eq 0 ]; then
    return
  fi

  local total=0
  echo "=== USB Update: Timing Summary ==="
  for timing in "''${TIMINGS[@]}"; do
    local label="''${timing%%|*}"
    local seconds="''${timing##*|}"
    total=$((total + seconds))
    printf '  - %s: %ss\n' "$label" "$seconds"
  done
  printf '  - total: %ss\n' "$total"
}

phase_begin "opening-luks" "Opening LUKS"
refresh_usb_mapper
if [ ! -e "$USB_ROOT_DEV" ]; then
  cryptsetup open "$USB_ROOT_PART" "$PREFERRED_USB_MAPPER_NAME"
  OPENED_MAPPER=1
  refresh_usb_mapper
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
if [ "$MODE" = "in-place" ]; then
  find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
else
  echo "Prebuild mode: skipping ext4 /nix/store wipe (slow USB random I/O)."
fi
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

phase_begin "installing-nixos" "Installing NixOS (''${MODE})"
nixos-install --flake "$FLAKE_DIR#usb" --root "$MOUNT_POINT" --no-root-passwd
phase_end

phase_begin "verifying-home-manager" "Verifying Home Manager"
HM_SERVICE="$MOUNT_POINT/etc/systemd/system/home-manager-stefan.service"
if [ -f "$HM_SERVICE" ]; then
  echo "Home Manager service found. It will activate on first boot."
else
  echo "Warning: Home Manager service not found at $HM_SERVICE"
  echo "First boot may not have the full user environment."
fi
phase_end

phase_begin "preparing-home-manager-state" "Preparing Home Manager state"
# Home Manager's first-boot activation writes GC roots and per-user profiles
# under ~/.local/state. Seed the directories in the target root now so the
# activation service can succeed on a fresh USB image.
chroot "$MOUNT_POINT" /nix/var/nix/profiles/system/sw/bin/install -d -m 0755 -o stefan -g users \
  /home/stefan/.local/state/home-manager \
  /home/stefan/.local/state/home-manager/gcroots \
  /home/stefan/.local/state/nix \
  /home/stefan/.local/state/nix/profiles
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
if [ "$MODE" = "in-place" ]; then
  find "$MOUNT_POINT/nix/store" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
else
  echo "Prebuild mode: leaving ext4 /nix/store untouched."
fi
# Preserve the target Nix DB. The booted squashfs store still needs valid DB
# registration so Home Manager can realize its generation and add GC roots.
phase_end

CURRENT_PHASE="done"
echo "=== USB Update: Done ==="
echo "Mode used: $MODE"
print_timing_summary
echo "Boot flow: LUKS unlock -> squashfs overlay on /nix/store -> fast reads"
    '')
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "copilot-sessions-sync" ''
      set -euo pipefail
      MODE="''${1:-to-usb}"
      SYNC_USER="''${SUDO_USER:-''${USER:-$(${pkgs.coreutils}/bin/id -un)}}"
      SYNC_GROUP="$(${pkgs.coreutils}/bin/id -gn "$SYNC_USER")"
      USER_HOME="$(${pkgs.gawk}/bin/awk -F: -v user="$SYNC_USER" '$1 == user { print $6; exit }' /etc/passwd)"
      LUKS_DEVICE="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
      PREFERRED_MAPPER="NIXOS_USB_CRYPT"
      MAPPER="$PREFERRED_MAPPER"
      MAPPER_DEV="/dev/mapper/$MAPPER"
      MOUNT="/mnt/usb-sync"
      LOCAL="$USER_HOME/.copilot/session-state"
      REMOTE="$MOUNT$USER_HOME/.copilot/session-state"
      OPENED_MAPPER=0
      MOUNTED=0

      run_root() {
        if [ "$EUID" -eq 0 ]; then
          "$@"
        else
          sudo "$@"
        fi
      }

      refresh_mapper() {
        local existing_mapper=""
        existing_mapper=$(${pkgs.util-linux}/bin/lsblk -nrpo NAME,TYPE "$LUKS_DEVICE" 2>/dev/null | ${pkgs.gnused}/bin/sed -n '/ crypt$/ { s/ crypt$//; p; q; }')
        if [ -n "$existing_mapper" ]; then
          MAPPER_DEV="$existing_mapper"
          MAPPER="''${existing_mapper##*/}"
        else
          MAPPER="$PREFERRED_MAPPER"
          MAPPER_DEV="/dev/mapper/$MAPPER"
        fi
      }

      cleanup() {
        local rc=$?
        trap - EXIT INT TERM

        if [ "$MOUNTED" -eq 1 ] && run_root ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT"; then
          run_root ${pkgs.util-linux}/bin/umount -R "$MOUNT" 2>/dev/null || true
          MOUNTED=0
        fi

        if [ "$OPENED_MAPPER" -eq 1 ]; then
          local attempt
          sync
          for attempt in 1 2 3; do
            if run_root ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER" 2>/dev/null; then
              OPENED_MAPPER=0
              break
            fi
            sleep 1
          done

          if [ "$OPENED_MAPPER" -eq 1 ]; then
            echo "Warning: failed to close $MAPPER; close it manually with: sudo cryptsetup luksClose $MAPPER" >&2
            if [ "$rc" -eq 0 ]; then
              rc=1
            fi
          fi
        fi

        exit "$rc"
      }

      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      if [ -z "$USER_HOME" ]; then
        echo "Unable to resolve a home directory for $SYNC_USER."
        exit 1
      fi

      if [ ! -e "$LUKS_DEVICE" ]; then
        echo "USB not found. Plug in the USB drive and try again."
        exit 1
      fi

      refresh_mapper
      if [ ! -e "$MAPPER_DEV" ]; then
        run_root ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$LUKS_DEVICE" "$PREFERRED_MAPPER"
        OPENED_MAPPER=1
        refresh_mapper
      elif ! ${pkgs.util-linux}/bin/findmnt -rn -S "$MAPPER_DEV" >/dev/null 2>&1; then
        OPENED_MAPPER=1
      fi

      run_root mkdir -p "$MOUNT"
      if run_root ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT"; then
        run_root ${pkgs.util-linux}/bin/umount -R "$MOUNT"
      fi
      run_root mount "$MAPPER_DEV" "$MOUNT"
      MOUNTED=1
      run_root mkdir -p "$USER_HOME/.copilot" "$LOCAL" "$MOUNT$USER_HOME/.copilot" "$REMOTE"
      run_root chown "$SYNC_USER:$SYNC_GROUP" "$USER_HOME/.copilot" "$LOCAL" "$MOUNT$USER_HOME/.copilot" "$REMOTE"

      case "$MODE" in
        to-usb)
          echo "Syncing desktop → USB..."
          run_root ${pkgs.rsync}/bin/rsync -av --update --chown="$SYNC_USER:$SYNC_GROUP" "$LOCAL/" "$REMOTE/"
          ;;
        from-usb)
          echo "Syncing USB → desktop..."
          run_root ${pkgs.rsync}/bin/rsync -av --update --chown="$SYNC_USER:$SYNC_GROUP" "$REMOTE/" "$LOCAL/"
          ;;
        *)
          echo "Usage: copilot-sessions-sync [to-usb|from-usb]"
          exit 1
          ;;
      esac

      echo "Done."
    '')
    (pkgs.writeShellScriptBin "transmission-port-sync" ''
      set -e
      CONFIG_DIR="$HOME/.config/fragments"
      SETTINGS_FILE="$CONFIG_DIR/settings.json"

      if [ -z "$1" ]; then
          echo "Usage: $0 <port>"
          exit 1
      fi
    '')
    (pkgs.writeShellScriptBin "hypr-nav" ''
      DIRECTION=$1
      BEFORE=$(hyprctl activewindow -j | jq -r '.address')
      hyprctl dispatch movefocus $DIRECTION
      AFTER=$(hyprctl activewindow -j | jq -r '.address')

      if [ "$BEFORE" == "$AFTER" ] || [ "$BEFORE" == "null" ]; then
          CURR=$(hyprctl activeworkspace -j | jq '.id')
          if [ "$DIRECTION" == "r" ]; then
              NEXT=$(( (CURR % 10) + 1 ))
              hyprctl dispatch workspace $NEXT
          elif [ "$DIRECTION" == "l" ]; then
              NEXT=$(( CURR - 1 ))
              [ $NEXT -lt 1 ] && NEXT=10
              hyprctl dispatch workspace $NEXT
          fi
      fi
    '')
    (pkgs.writeShellScriptBin "hypr-quit-active" ''
      set -euo pipefail

      active=$(hyprctl activewindow -j 2>/dev/null || true)
      pid=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.pid // empty')
      app_class=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.class // empty')
      app_title=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.title // empty')

      if [ -z "$pid" ] || [ "$pid" = "null" ]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Quit active app" "No active window to quit."
        exit 1
      fi

      resolve_root_pid() {
        local candidate="$1"
        local exe
        exe=$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)
        [ -n "$exe" ] || {
          printf '%s\n' "$candidate"
          return
        }

        while true; do
          local ppid
          local parent_exe

          ppid=$(${pkgs.procps}/bin/ps -o ppid= -p "$candidate" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')
          [ -n "$ppid" ] || break
          [ "$ppid" -le 1 ] && break

          parent_exe=$(readlink -f "/proc/$ppid/exe" 2>/dev/null || true)
          [ "$parent_exe" = "$exe" ] || break

          candidate="$ppid"
        done

        printf '%s\n' "$candidate"
      }

      target_pid=$(resolve_root_pid "$pid")
      label="$app_class"
      [ -n "$label" ] || label="$app_title"
      [ -n "$label" ] || label="PID $target_pid"

      kill -TERM "$target_pid"

      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ! kill -0 "$target_pid" 2>/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      ${pkgs.libnotify}/bin/notify-send -u low "Quit active app" "Force killing $label"
      kill -KILL "$target_pid"
    '')
    (pkgs.writeShellScriptBin "screenshot-path-copy" ''
      dest=$(dms screenshot "$@" --dir ~/pictures/screenshots --no-clipboard --no-notify)
      if [ -n "$dest" ] && [ -f "$dest" ]; then
          echo -n "$dest" | ${pkgs.wl-clipboard}/bin/wl-copy
          ${pkgs.libnotify}/bin/notify-send -u low -i "$dest" "Screenshot" "Path copied: $dest"
      fi
    '')
    (pkgs.writeShellScriptBin "gsr-record" ''
      MODE="''${1:-region}"
      AUDIO=1
      [ "''${2:-}" = "--no-audio" ] && AUDIO=0

      PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/gsr-record.pid"
      OUTDIR="$HOME/videos/screencasts"
      mkdir -p "$OUTDIR"

      if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
          kill -INT "$PID"
          ${pkgs.libnotify}/bin/notify-send -u low "Screen Recording" "Recording stopped"
          rm -f "$PIDFILE"
          exit 0
        fi
        rm -f "$PIDFILE"
      fi

      OUTFILE="$OUTDIR/screencast_$(date +%Y-%m-%d_%H-%M-%S).mp4"

      case "$MODE" in
        region)     WINDOW=region ;;
        fullscreen) WINDOW=$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[0].name') ;;
        window)     WINDOW=focused ;;
        *)          WINDOW=region ;;
      esac

      AUDIO_ARGS=()
      [ "$AUDIO" -eq 1 ] && AUDIO_ARGS=(-a default_output)

      gpu-screen-recorder -w "$WINDOW" -f 60 -c mp4 "''${AUDIO_ARGS[@]}" -o "$OUTFILE" &
      echo $! > "$PIDFILE"
      ${pkgs.libnotify}/bin/notify-send -u low "Screen Recording" "Recording started (press again to stop)"
    '')
  ];
}
