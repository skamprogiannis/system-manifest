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
      description = "Size of the disposable tmpfs upper layer for /nix/store (used only when not in ram-store mode).";
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
    # Writes go to tmpfs by default, or to an ext4 scratch area in ram-store mode
    # to avoid keeping both the squashfs image and overlay upper layer in RAM.
    #
    # When the ram-store specialisation is selected, initrd first copies the
    # squashfs image into tmpfs and mounts the RAM copy as the lower layer. If
    # the host does not have enough free memory headroom, it falls back to the
    # default USB-backed lower mount and still boots successfully.
    boot.initrd.systemd.services.initrd-usb-overlay-store = {
      description = "Prepare USB squashfs-backed /nix/store overlay";
      requires = ["sysroot.mount"];
      after = ["sysroot.mount"];
      requiredBy = ["initrd-fs.target"];
      before = ["initrd-fs.target"];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      path = with pkgs; [
        coreutils
        util-linux
      ];
      script = ''
        set -eu

        lower_store_image=/sysroot/nix-store.squashfs
        lower_mount_source="$lower_store_image"
        store_mode=${lib.escapeShellArg usbStore.mode}
        upper_size_mib=${toString usbStore.upperSizeMiB}
        ram_image_tmpfs_percent=${toString usbStore.ramImageTmpfsPercent}
        ram_mode_safety_mib=${toString usbStore.ramModeSafetyMiB}
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

        mkdir -p /sysroot/nix/.ro-store /sysroot/nix/.rw-store

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
              echo "initrd-usb-overlay-store: using RAM-backed lower store image"
            else
              echo "initrd-usb-overlay-store: RAM copy failed, falling back to USB-backed squashfs" >&2
              rm -f "$ram_store_image"
              umount /sysroot/nix/.ram-store-image || true
            fi
          else
            echo "initrd-usb-overlay-store: insufficient memory for RAM-backed lower store, falling back to USB-backed squashfs" >&2
          fi
        fi

        mount_read_only_store() {
          echo "initrd-usb-overlay-store: falling back to read-only squashfs /nix/store" >&2
          mkdir -p /sysroot/nix/store
          mount --bind /sysroot/nix/.ro-store /sysroot/nix/store || {
            echo "initrd-usb-overlay-store: failed to mount read-only store at /sysroot/nix/store" >&2
            return 1
          }
        }

        mount_overlay_store() {
          mkdir -p /sysroot/nix/store
          mount -t overlay overlay \
            -o lowerdir=/sysroot/nix/.ro-store,upperdir=/sysroot/nix/.rw-store/upper,workdir=/sysroot/nix/.rw-store/work \
            /sysroot/nix/store || {
            echo "initrd-usb-overlay-store: failed to mount writable overlay store" >&2
            return 1
          }
        }

        prepare_upper_dirs() {
          mkdir -p /sysroot/nix/.rw-store/upper /sysroot/nix/.rw-store/work || {
            echo "initrd-usb-overlay-store: failed to create overlay upper/work directories" >&2
            return 1
          }
          chmod 0755 /sysroot/nix/.rw-store/upper /sysroot/nix/.rw-store/work || {
            echo "initrd-usb-overlay-store: failed to set overlay upper/work directory permissions" >&2
            return 1
          }
        }

        cleanup_tmpfs_upper() {
          if ! umount /sysroot/nix/.rw-store; then
            echo "initrd-usb-overlay-store: warning: tmpfs cleanup failed" >&2
            if mountpoint -q /sysroot/nix/.rw-store; then
              echo "initrd-usb-overlay-store: warning: tmpfs remains mounted and consuming RAM" >&2
            fi
            return 1
          fi
        }

        reset_scratch_upper() {
          # Defensive cleanup for initrd retries or switching from the tmpfs-backed path.
          if mountpoint -q /sysroot/nix/.rw-store; then
            umount /sysroot/nix/.rw-store || {
              echo "initrd-usb-overlay-store: failed to unmount stale scratch upper mount" >&2
              return 1
            }
          fi
          rm -rf /sysroot/nix/.rw-store || {
            echo "initrd-usb-overlay-store: failed to reset scratch upper store" >&2
            return 1
          }
          prepare_upper_dirs
        }

        if ! mount -t squashfs -o loop,ro "$lower_mount_source" /sysroot/nix/.ro-store; then
          echo "initrd-usb-overlay-store: failed to mount squashfs lower store" >&2
          exit 1
        fi

        if [ "$upper_store_kind" = "scratch" ]; then
          echo "initrd-usb-overlay-store: ram-store using disk-backed scratch upper store"
          if reset_scratch_upper; then
            if ! mount_overlay_store; then
              echo "initrd-usb-overlay-store: overlay mount failed" >&2
              mount_read_only_store || exit 1
            fi
          else
            mount_read_only_store || exit 1
          fi
        elif mount -t tmpfs -o mode=0755,size=''${upper_size_mib}M tmpfs /sysroot/nix/.rw-store; then
          if prepare_upper_dirs; then
            if ! mount_overlay_store; then
              echo "initrd-usb-overlay-store: overlay mount failed" >&2
              if ! cleanup_tmpfs_upper; then
                :
              fi
              mount_read_only_store || exit 1
            fi
          else
            if ! cleanup_tmpfs_upper; then
              :
            fi
            mount_read_only_store || exit 1
          fi
        else
          echo "initrd-usb-overlay-store: tmpfs upper mount failed" >&2
          mount_read_only_store || exit 1
        fi
      '';
    };

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
