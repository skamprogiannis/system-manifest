{
  pkgs,
  lib,
  modulesPath,
  config,
  ...
}: let
  usb = import ../../modules/shared/usb-constants.nix;
  usbStore = config.systemManifest.usb.store;
in {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  options.systemManifest.usb.store = {
    mode = lib.mkOption {
      type = lib.types.enum ["usb-backed" "ram-backed"];
      default = "usb-backed";
      description = ''
        Select whether the USB host mounts the lower /nix/store squashfs image
        directly from the USB root or first copies the squashfs image into RAM.
      '';
    };

    upperSizeMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2048;
      description = "Size of the disposable tmpfs upper layer for /nix/store (used only in usb-backed mode; ram-backed mode uses USB-root ext4 scratch instead).";
    };

    ramImageTmpfsPercent = lib.mkOption {
      type = lib.types.ints.between 1 95;
      default = 75;
      description = ''
        Maximum tmpfs size percentage reserved for the RAM-backed squashfs image
        when the ram-backed USB specialisation is selected.
      '';
    };

    ramModeSafetyMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2048;
      description = ''
        Extra memory headroom required before the ram-backed store mode will copy
        the squashfs image into RAM.
      '';
    };
  };

  config = {
    # Generic hardware support for portability across lab machines
    boot.initrd.availableKernelModules = [
      "xhci_pci"
      "ehci_pci"
      "ohci_pci"
      "uhci_hcd"
      "ahci"
      "usb_storage"
      "sd_mod"
      "usbhid"
      "hid_generic"
      "nvme"
      "uas"
      "virtio_pci"
      "virtio_blk"
      "sdhci_pci"
      "ata_piix"
      "ata_generic"
    ];
    # Force-load squashfs/loop/overlay so they are active before
    # postMountCommands tries to mount the squashfs store image.
    # availableKernelModules only bundles them in the initrd — it does
    # not guarantee they are loaded when postMountCommands executes.
    boot.initrd.kernelModules = ["loop" "squashfs" "overlay"];
    boot.initrd.systemd.emergencyAccess = true;
    boot.initrd.systemd.initrdBin = [
      config.boot.initrd.systemd.package.util-linux
    ];
    hardware.enableAllFirmware = true;

    # Enable LUKS support
    boot.initrd.luks.devices."root" = {
      device = usb.rootPartByLabel;
      preLVM = true;
    };

    # File Systems
    fileSystems."/" = {
      device = usb.rootFsByLabel;
      fsType = "ext4";
      options = ["noatime" "nodiratime"];
    };

    fileSystems."/boot" = {
      device = usb.bootByLabel;
      fsType = "vfat";
    };

    # Hybrid squashfs Nix store: compressed read-only image + writable overlay.
    # Reads come from the squashfs (sequential, compressed, fast on USB).
    # Writes go to tmpfs by default (usb-backed mode), or to an ext4 scratch
    # area on the USB root in ram-backed mode to avoid keeping both the squashfs
    # RAM copy and an overlay upper layer in RAM simultaneously.
    #
    # The service is structured in three explicit phases:
    #   1. Choose lower source (USB squashfs or RAM copy).
    #   2. Mount the squashfs lower store (hard failure — no squashfs, no boot).
    #   3. Prepare and mount the writable upper, falling back to a read-only
    #      bind mount of the lower store if overlay setup fails.
    #
    # On fallback, the marker /run/nixos-usb-store-mode is written with the
    # value "read-only-fallback" so that userspace can detect the degraded state.
    boot.initrd.systemd.services.initrd-usb-overlay-store = {
      description = "Prepare USB squashfs-backed /nix/store overlay";
      requires = ["sysroot.mount"];
      after = ["sysroot.mount"];
      requiredBy = [
        "initrd-find-nixos-closure.service"
        "initrd-fs.target"
      ];
      before = [
        "initrd-find-nixos-closure.service"
        "initrd-fs.target"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      path = with pkgs; [
        coreutils
        kmod
        util-linux
      ];
      script = ''
        set -eu

        mkdir -p /run /sysroot/var/log
        log_file=/sysroot/var/log/initrd-usb-overlay-store.log
        if ! : > "$log_file"; then
          log_file=/run/initrd-usb-overlay-store.log
          : > "$log_file"
        fi

        log() {
          printf 'initrd-usb-overlay-store: %s\n' "$1" | tee -a "$log_file"
        }

        warn() {
          printf 'initrd-usb-overlay-store: %s\n' "$1" | tee -a "$log_file" >&2
        }

        fatal() {
          warn "FATAL: $1"
          exit 1
        }

        lower_store_image=/sysroot/nix-store.squashfs
        lower_mount_source="$lower_store_image"
        store_mode=${lib.escapeShellArg usbStore.mode}
        upper_size_mib=${toString usbStore.upperSizeMiB}
        ram_image_tmpfs_percent=${toString usbStore.ramImageTmpfsPercent}
        ram_mode_safety_mib=${toString usbStore.ramModeSafetyMiB}
        # "tmpfs" in usb-backed mode, "scratch" in ram-backed mode.
        upper_store_kind=tmpfs

        read_meminfo_kib() {
          key="$1"
          while IFS=' ' read -r name value _; do
            if [ "$name" = "$key:" ]; then
              printf '%s\n' "$value"
              return 0
            fi
          done < /proc/meminfo
          return 1
        }

        # --- Phase 1: Choose lower source ---

        if [ ! -f "$lower_store_image" ]; then
          fatal "squashfs image not found at $lower_store_image"
        fi

        mkdir -p /sysroot/nix/.ro-store
        modprobe loop || warn "loop module load failed or was already handled"
        modprobe squashfs || warn "squashfs module load failed or was already handled"
        modprobe overlay || warn "overlay module load failed or was already handled"

        if [ "$store_mode" = "ram-backed" ]; then
          upper_store_kind=scratch
          image_bytes="$(stat -c %s "$lower_store_image")"
          mem_available_kib="$(read_meminfo_kib MemAvailable || read_meminfo_kib MemTotal)"
          available_bytes=$((mem_available_kib * 1024))
          required_bytes=$((image_bytes + ram_mode_safety_mib * 1024 * 1024))

          if [ "$available_bytes" -ge "$required_bytes" ]; then
            mkdir -p /sysroot/nix/.ram-store-image
            mount -t tmpfs -o mode=0755,size=''${ram_image_tmpfs_percent}% tmpfs /sysroot/nix/.ram-store-image
            ram_store_image=/sysroot/nix/.ram-store-image/nix-store.squashfs
            if cp "$lower_store_image" "$ram_store_image"; then
              lower_mount_source="$ram_store_image"
              log "squashfs image copied to RAM"
            else
              warn "RAM copy failed, falling back to USB-backed squashfs"
              rm -f "$ram_store_image"
              umount /sysroot/nix/.ram-store-image || true
            fi
          else
            warn "insufficient memory for RAM-backed lower store, falling back to USB-backed squashfs"
          fi
        fi

        # --- Phase 2: Mount lower store (hard failure) ---

        loop_device="$(losetup --find --show --read-only "$lower_mount_source")" || {
          fatal "failed to allocate read-only loop device for $lower_mount_source"
        }

        if ! mount -t squashfs -o ro "$loop_device" /sysroot/nix/.ro-store; then
          losetup -d "$loop_device" || true
          fatal "failed to mount squashfs lower store from $lower_mount_source through $loop_device"
        fi
        printf '%s\n' "$loop_device" > /run/nixos-usb-store-loopdev
        log "lower store mounted from $lower_mount_source through $loop_device"

        # --- Phase 3 helpers ---

        write_store_mode_marker() {
          local mode_value="$1"
          mkdir -p /run
          printf '%s\n' "$mode_value" > /run/nixos-usb-store-mode
        }

        mount_read_only_store() {
          warn "falling back to read-only squashfs /nix/store"
          mkdir -p /sysroot/nix/store
          if mount --bind /sysroot/nix/.ro-store /sysroot/nix/store; then
            write_store_mode_marker "read-only-fallback"
          else
            warn "FATAL: failed to mount read-only store at /sysroot/nix/store"
            return 1
          fi
        }

        mount_overlay_store() {
          mkdir -p /sysroot/nix/store
          if mount -t overlay overlay \
            -o lowerdir=/sysroot/nix/.ro-store,upperdir=/sysroot/nix/.rw-store/upper,workdir=/sysroot/nix/.rw-store/work \
            /sysroot/nix/store; then
            return 0
          else
            warn "failed to mount writable overlay store"
            return 1
          fi
        }

        prepare_upper_dirs() {
          if ! mkdir -p /sysroot/nix/.rw-store/upper /sysroot/nix/.rw-store/work; then
            warn "failed to create overlay upper/work directories"
            return 1
          fi
          if ! chmod 0755 /sysroot/nix/.rw-store/upper /sysroot/nix/.rw-store/work; then
            warn "failed to set overlay upper/work directory permissions"
            return 1
          fi
        }

        cleanup_tmpfs_upper() {
          if ! umount /sysroot/nix/.rw-store; then
            warn "warning: tmpfs upper cleanup failed"
            if mountpoint -q /sysroot/nix/.rw-store; then
              warn "warning: tmpfs remains mounted and consuming RAM"
            fi
            return 1
          fi
        }

        # Prepare USB-root ext4 scratch dirs for the overlay upper/work area.
        # The USB root partition is already mounted at /sysroot, so this avoids
        # a second tmpfs allocation — the image copy and the scratch area do not
        # compete for the same RAM budget.
        reset_scratch_upper() {
          if mountpoint -q /sysroot/nix/.rw-store; then
            umount /sysroot/nix/.rw-store || {
              warn "failed to unmount unexpected mount at /sysroot/nix/.rw-store"
              return 1
            }
          fi
          rm -rf /sysroot/nix/.rw-store || {
            warn "failed to reset scratch upper store"
            return 1
          }
          prepare_upper_dirs
        }

        # --- Phase 3: Mount writable overlay or fall back to read-only ---

        if [ "$upper_store_kind" = "scratch" ]; then
          log "using USB-root ext4 scratch for overlay upper"
          if reset_scratch_upper; then
            if mount_overlay_store; then
              write_store_mode_marker "writable-scratch-overlay"
            else
              mount_read_only_store || exit 1
            fi
          else
            mount_read_only_store || exit 1
          fi
        elif mkdir -p /sysroot/nix/.rw-store && mount -t tmpfs -o mode=0755,size=''${upper_size_mib}M tmpfs /sysroot/nix/.rw-store; then
          if prepare_upper_dirs; then
            if mount_overlay_store; then
              write_store_mode_marker "writable-overlay"
            else
              if ! cleanup_tmpfs_upper; then
                warn "continuing with read-only fallback after tmpfs cleanup failure"
              fi
              mount_read_only_store || exit 1
            fi
          else
            if ! cleanup_tmpfs_upper; then
              warn "continuing with read-only fallback after tmpfs cleanup failure"
            fi
            mount_read_only_store || exit 1
          fi
        else
          warn "tmpfs upper mount failed"
          mount_read_only_store || exit 1
        fi
      '';
    };

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
