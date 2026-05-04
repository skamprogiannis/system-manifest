{
  config,
  pkgs,
  lib,
  ...
}: let
  usb = import ../../shared/usb-constants.nix;
  cfg = config.system_manifest.scripts;
in {
  options.system_manifest.scripts = {
    enableSetupPersistentUsb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the setup-persistent-usb helper in the current host profile.";
    };

    enableUpdateUsb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the update-usb helper in the current host profile.";
    };
  };

  config.home.packages =
    lib.optionals cfg.enableSetupPersistentUsb [
      (pkgs.writeShellScriptBin "setup-persistent-usb" ''
        set -euo pipefail

        SCRIPT_NAME="$(basename "$0")"
        USB_MAPPER_NAME="${usb.mapperName}"
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
          - 1 GiB EFI partition (label: ${usb.bootLabel})
          - LUKS2 root partition (partlabel: ${usb.rootPartLabel})
          - ext4 filesystem inside LUKS (label: ${usb.rootFsLabel})
        EOF
        }

        cleanup() {
          if [ "$OPENED_MAPPER" -eq 1 ]; then
            if ! cryptsetup close "$USB_MAPPER_NAME" 2>/dev/null; then
              echo "Warning: failed to close $USB_MAPPER_NAME during cleanup; you may need to close it manually." >&2
            fi
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
            echo "Error: partition device $part did not appear."
            exit 1
          fi
        done

        echo "Formatting boot partition ($USB_BOOT_PART)..."
        mkfs.vfat -F 32 -n ${usb.bootLabel} "$USB_BOOT_PART"

        echo "Formatting root partition ($USB_CRYPT_PART) with LUKS..."
        echo "Please enter a passphrase for USB encryption when prompted."
        cryptsetup luksFormat --type luks2 "$USB_CRYPT_PART"
        echo "Opening LUKS container..."
        cryptsetup open "$USB_CRYPT_PART" "$USB_MAPPER_NAME"
        OPENED_MAPPER=1

        echo "Formatting internal ext4 filesystem..."
        mkfs.ext4 -L ${usb.rootFsLabel} "$USB_ROOT_DEV"
        cryptsetup close "$USB_MAPPER_NAME"
        OPENED_MAPPER=0

        echo "USB is partitioned and formatted."
        echo "Next step: sudo update-usb /path/to/system-manifest/main"
      '')
    ]
    ++ lib.optionals cfg.enableUpdateUsb [
      (pkgs.writeShellScriptBin "update-usb" ''
        set -euo pipefail

        SCRIPT_NAME="$(basename "$0")"
        USB_ROOT_PART="${usb.rootPartByLabel}"
        USB_BOOT_DEV="${usb.bootByLabel}"
        PREFERRED_USB_MAPPER_NAME="${usb.mapperName}"
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
        FINAL_SQUASHFS=""
        EXPECTED_CONFIG_REVISION=""
        TARGET_CONFIG_REVISION=""
        TARGET_NIXOS_VERSION=""
        TARGET_SYSTEM_TOPLEVEL=""
        TARGET_INIT_RELATIVE=""
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
          sudo update-usb /path/to/system-manifest/main
          sudo update-usb --mode prebuild /path/to/system-manifest/main
          sudo update-usb --in-place /path/to/system-manifest/main
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

        cleanup_warn() {
          echo "Cleanup warning: $1" >&2
        }

        run_cleanup_step() {
          local description="$1"
          shift
          local output=""

          if ! output=$("$@" 2>&1); then
            cleanup_warn "$description"
            if [ -n "$output" ]; then
              printf '%s\n' "$output" >&2
            fi
          fi
        }

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

        read_expected_config_revision() {
          local error_log=""
          local result=""

          error_log=$(mktemp)
          if ! result=$(nix eval --raw "$FLAKE_DIR#nixosConfigurations.usb.config.system.configurationRevision" 2>"$error_log"); then
            echo "Warning: failed to evaluate USB configurationRevision from $FLAKE_DIR" >&2
            if [ -s "$error_log" ]; then
              cat "$error_log" >&2
            fi
            rm -f "$error_log"
            return 1
          fi

          rm -f "$error_log"
          printf '%s' "$result"
        }

        version_json_field() {
          local key="$1"
          local value=""

          if ! value=$(${pkgs.jq}/bin/jq -r --arg key "$key" '.[$key] // empty' 2>/dev/null); then
            echo "Warning: failed to parse nixos-version JSON for key '$key'" >&2
            return 1
          fi

          printf '%s\n' "$value"
        }

        capture_target_system_metadata() {
          local version_json=""
          local version_error_log=""

          TARGET_SYSTEM_TOPLEVEL="$(readlink -f "$MOUNT_POINT/nix/var/nix/profiles/system" 2>/dev/null || true)"
          TARGET_INIT_RELATIVE=""
          if [ -n "$TARGET_SYSTEM_TOPLEVEL" ]; then
            TARGET_INIT_RELATIVE="''${TARGET_SYSTEM_TOPLEVEL#/nix/}/init"
          fi

          version_error_log=$(mktemp)
          if ! version_json="$(chroot "$MOUNT_POINT" /nix/var/nix/profiles/system/sw/bin/nixos-version --json 2>"$version_error_log")"; then
            echo "Warning: failed to read installed USB system metadata via nixos-version --json" >&2
            if [ -s "$version_error_log" ]; then
              cat "$version_error_log" >&2
            fi
            version_json=""
          fi
          rm -f "$version_error_log"

          TARGET_CONFIG_REVISION=""
          TARGET_NIXOS_VERSION=""
          if [ -n "$version_json" ]; then
            TARGET_CONFIG_REVISION="$(printf '%s\n' "$version_json" | version_json_field configurationRevision || true)"
            TARGET_NIXOS_VERSION="$(printf '%s\n' "$version_json" | version_json_field nixosVersion || true)"
          fi
        }

        verify_installed_revision() {
          capture_target_system_metadata

          if [ -z "$TARGET_SYSTEM_TOPLEVEL" ]; then
            echo "Error: could not resolve the installed USB system path."
            exit 1
          fi

          if [ -z "$TARGET_CONFIG_REVISION" ]; then
            echo "Error: could not read the installed USB configuration revision."
            exit 1
          fi

          if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
            echo "expected USB revision: $EXPECTED_CONFIG_REVISION"
          else
            echo "expected USB revision: unavailable (flake evaluation did not return configurationRevision)"
          fi
          echo "installed USB revision: $TARGET_CONFIG_REVISION"
          echo "installed USB system path: $TARGET_SYSTEM_TOPLEVEL"
          if [ -n "$TARGET_NIXOS_VERSION" ]; then
            echo "installed USB NixOS version: $TARGET_NIXOS_VERSION"
          fi

          if [ -n "$EXPECTED_CONFIG_REVISION" ] && [ "$TARGET_CONFIG_REVISION" != "$EXPECTED_CONFIG_REVISION" ]; then
            echo "Error: installed USB revision does not match the expected flake revision."
            exit 1
          fi
        }

        verify_squashfs_contains_system() {
          local squashfs_path="$1"

          if [ -z "$TARGET_SYSTEM_TOPLEVEL" ] || [ -z "$TARGET_INIT_RELATIVE" ]; then
            echo "Error: target system metadata was not captured before squashfs verification."
            exit 1
          fi

          if [ ! -f "$squashfs_path" ]; then
            echo "Error: squashfs image not found at $squashfs_path"
            exit 1
          fi

          if ! unsquashfs -cat "$squashfs_path" "$TARGET_INIT_RELATIVE" >/dev/null 2>&1; then
            echo "Error: $squashfs_path does not contain the installed USB system path."
            echo "Expected to find: $TARGET_SYSTEM_TOPLEVEL"
            exit 1
          fi

          echo "verified squashfs contains: $TARGET_SYSTEM_TOPLEVEL"
          echo "usb squashfs timestamp: $(stat -c '%y' "$squashfs_path")"
        }

        if ! command -v mksquashfs >/dev/null 2>&1 || ! command -v unsquashfs >/dev/null 2>&1; then
          if [ "''${USB_UPDATE_IN_NIX_SHELL:-0}" != "1" ] && command -v nix-shell >/dev/null 2>&1; then
            REEXEC_ARGS=""
            for arg in "''${ORIGINAL_ARGS[@]}"; do
              REEXEC_ARGS+=" $(printf '%q' "$arg")"
            done
            echo "Entering nix-shell for required USB update tools..."
            exec nix-shell -p "''${NIX_SHELL_PACKAGES[@]}" --run "USB_UPDATE_IN_NIX_SHELL=1 bash \"$0\"''${REEXEC_ARGS}"
          fi
          echo "Error: required squashfs tools are missing and nix-shell is unavailable."
          echo "Run manually:"
          echo "  sudo nix-shell -p ''${NIX_SHELL_PACKAGES[*]} --run '$SCRIPT_NAME /path/to/system-manifest/main'"
          exit 1
        fi

        if [ "$EUID" -ne 0 ]; then
          echo "Error: please run with sudo."
          echo "Example: sudo update-usb /path/to/system-manifest/main"
          exit 1
        fi

        for tool in nix "''${REQUIRED_TOOLS[@]}"; do
          if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Error: required tool '$tool' is not available in PATH."
            exit 1
          fi
        done

        if [ ! -d "$FLAKE_DIR" ] || [ ! -f "$FLAKE_DIR/flake.nix" ]; then
          echo "Error: flake directory '$FLAKE_DIR' is invalid (missing flake.nix)."
          echo "Pass a worktree path containing flake.nix, for example /path/to/system-manifest/main."
          exit 1
        fi

        EXPECTED_CONFIG_REVISION="$(read_expected_config_revision || true)"
        echo "Source flake dir: $FLAKE_DIR"
        if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
          echo "Source USB revision: $EXPECTED_CONFIG_REVISION"
        else
          echo "Warning: could not resolve Source USB revision from $FLAKE_DIR"
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
            run_cleanup_step "failed to unmount $MOUNT_POINT/nix/store" umount "$MOUNT_POINT/nix/store"
          fi
          if [ "$MOUNTED_BOOT" -eq 1 ]; then
            run_cleanup_step "failed to unmount $MOUNT_POINT/boot" umount "$MOUNT_POINT/boot"
          fi
          if [ "$MOUNTED_ROOT" -eq 1 ]; then
            run_cleanup_step "failed to unmount $MOUNT_POINT" umount "$MOUNT_POINT"
          fi
          if [ "$OPENED_MAPPER" -eq 1 ]; then
            run_cleanup_step "failed to close mapper $USB_MAPPER_NAME" cryptsetup close "$USB_MAPPER_NAME"
          fi

          if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
            run_cleanup_step "failed to remove temporary stage directory $STAGE_DIR" rm -rf "$STAGE_DIR"
          fi

          if [ "$CANCELED" -eq 1 ]; then
            echo "Canceled during phase: $CURRENT_PHASE"
            echo "You can safely retry: sudo update-usb /path/to/system-manifest/main"
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

        phase_begin "verifying-installed-revision" "Verifying installed revision"
        verify_installed_revision
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
          FINAL_SQUASHFS="$MOUNT_POINT/nix-store.squashfs"
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
          FINAL_SQUASHFS="$MOUNT_POINT/nix-store.squashfs"
          SQFS_SIZE="$(du -sh "$MOUNT_POINT/nix-store.squashfs" | cut -f1)"
          echo "squashfs image: $SQFS_SIZE"
          phase_end
        fi

        phase_begin "verifying-squashfs" "Verifying USB squashfs"
        verify_squashfs_contains_system "$FINAL_SQUASHFS"
        phase_end

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
        if [ -n "$EXPECTED_CONFIG_REVISION" ]; then
          echo "Expected revision: $EXPECTED_CONFIG_REVISION"
        fi
        if [ -n "$TARGET_CONFIG_REVISION" ]; then
          echo "Written revision: $TARGET_CONFIG_REVISION"
        fi
        if [ -n "$TARGET_SYSTEM_TOPLEVEL" ]; then
          echo "Written system path: $TARGET_SYSTEM_TOPLEVEL"
        fi
        print_timing_summary
        echo "Boot flow: LUKS unlock -> squashfs overlay on /nix/store -> fast reads"
        echo "After boot, verify with: nixos-version --json && readlink -f /run/current-system"
      '')
    ];
}
