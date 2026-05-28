{
  pkgs,
  lib,
  modulesPath,
  config,
  utils,
  ...
}: let
  usb = import ../../modules/shared/usb-constants.nix;
  usbStore = config.systemManifest.usb.store;
  roStoreDevice =
    if usbStore.mode == "ram-backed"
    then "/sysroot/nix/.ram-store-image/nix-store.squashfs"
    else if usbStore.mode == "host-auto"
    then "/sysroot/nix/.host-store/.nixos-usb/store/nix-store.squashfs"
    else "/sysroot/nix-store.squashfs";
  roStoreMountUnit = "${utils.escapeSystemdPath "/sysroot/nix/.ro-store"}.mount";
  rwStoreMountUnit = "${utils.escapeSystemdPath "/sysroot/nix/.rw-store"}.mount";
in {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  options.systemManifest.usb.store = {
    mode = lib.mkOption {
      type = lib.types.enum ["usb-backed" "ram-backed" "host-auto"];
      default = "usb-backed";
      description = ''
        Select whether the USB host mounts the lower /nix/store squashfs image
        directly from the USB root, first copies the squashfs image into RAM,
        or tries to use a writable host Linux partition for the squashfs image
        and writable overlay layer.
      '';
    };

    upperSizeMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2048;
      description = "Size of the disposable tmpfs upper layer for /nix/store in usb-backed mode.";
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
    # Keep the store filesystems available before initrd closure lookup.
    boot.initrd.kernelModules = ["loop" "squashfs" "overlay"];
    boot.initrd.supportedFilesystems = lib.mkIf (usbStore.mode == "host-auto") [
      "ext2"
      "ext3"
      "ext4"
      "xfs"
      "btrfs"
    ];
    boot.initrd.systemd.emergencyAccess = true;
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

    # NixOS-native squashfs store: the initrd systemd fstab generator mounts
    # these before initrd-find-nixos-closure.service resolves the boot closure.
    fileSystems."/nix/.ro-store" = {
      device = roStoreDevice;
      fsType = "squashfs";
      options =
        [
          "loop"
        ]
        ++ lib.optional (config.boot.kernelPackages.kernel.kernelAtLeast "6.2") "threads=multi";
      neededForBoot = true;
    };

    fileSystems."/nix/.rw-store" =
      if usbStore.mode == "ram-backed"
      then {
        device = "/nix/.ram-store-rw";
        fsType = "none";
        options = ["bind"];
        neededForBoot = true;
      }
      else if usbStore.mode == "host-auto"
      then {
        device = "/nix/.host-store/.nixos-usb/store/rw";
        fsType = "none";
        options = ["bind"];
        neededForBoot = true;
      }
      else {
        fsType = "tmpfs";
        options = [
          "mode=0755"
          "size=${toString usbStore.upperSizeMiB}M"
        ];
        neededForBoot = true;
      };

    fileSystems."/nix/store" = {
      overlay = {
        lowerdir = ["/nix/.ro-store"];
        upperdir = "/nix/.rw-store/store";
        workdir = "/nix/.rw-store/work";
      };
      neededForBoot = true;
    };

    boot.initrd.systemd.services = lib.mkMerge [
      (lib.mkIf (usbStore.mode == "ram-backed") {
        initrd-usb-ram-store-prepare = {
          description = "Prepare RAM-backed USB squashfs store image";
          requires = ["sysroot.mount"];
          after = ["sysroot.mount"];
          requiredBy = [
            roStoreMountUnit
            rwStoreMountUnit
          ];
          before = [
            roStoreMountUnit
            rwStoreMountUnit
          ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          path = with pkgs; [
            coreutils
            util-linux
          ];
          script = ''
            set -eu

            lower_store_image=/sysroot/nix-store.squashfs
            ram_store_dir=/sysroot/nix/.ram-store-image
            ram_store_image="$ram_store_dir/nix-store.squashfs"
            scratch_store_dir=/sysroot/nix/.ram-store-rw

            if [ ! -f "$lower_store_image" ]; then
              echo "initrd-usb-ram-store-prepare: missing $lower_store_image" >&2
              exit 1
            fi

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

            fall_back_to_usb_image() {
              if mountpoint -q "$ram_store_dir"; then
                umount "$ram_store_dir" || true
              fi
              rm -rf "$ram_store_dir"
              mkdir -p "$ram_store_dir"
              ln -sfn "$lower_store_image" "$ram_store_image"
              printf '%s\n' "writable-scratch-overlay-usb-lower" > /run/nixos-usb-store-mode
            }

            mkdir -p /run "$ram_store_dir" "$scratch_store_dir"
            rm -rf "$scratch_store_dir/store" "$scratch_store_dir/work"

            image_bytes="$(stat -c %s "$lower_store_image")"
            mem_available_kib="$(read_meminfo_kib MemAvailable || read_meminfo_kib MemTotal)"
            available_bytes=$((mem_available_kib * 1024))
            required_bytes=$((image_bytes + ${toString usbStore.ramModeSafetyMiB} * 1024 * 1024))

            if [ "$available_bytes" -lt "$required_bytes" ]; then
              echo "initrd-usb-ram-store-prepare: insufficient memory, using USB lower image" >&2
              fall_back_to_usb_image
              exit 0
            fi

            if mount -t tmpfs -o mode=0755,size=${toString usbStore.ramImageTmpfsPercent}% tmpfs "$ram_store_dir" \
              && cp "$lower_store_image" "$ram_store_image"; then
              printf '%s\n' "writable-scratch-overlay-ram-lower" > /run/nixos-usb-store-mode
            else
              echo "initrd-usb-ram-store-prepare: RAM copy failed, using USB lower image" >&2
              fall_back_to_usb_image
            fi
          '';
        };
      })

      (lib.mkIf (usbStore.mode == "host-auto") {
        initrd-usb-host-auto-store-prepare = {
          description = "Prepare host-auto USB squashfs store paths";
          requires = ["sysroot.mount"];
          after = ["sysroot.mount"];
          requiredBy = [
            roStoreMountUnit
            rwStoreMountUnit
          ];
          before = [
            roStoreMountUnit
            rwStoreMountUnit
          ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          path = with pkgs; [
            coreutils
            util-linux
          ];
          script = ''
            set -eu

            lower_store_image=/sysroot/nix-store.squashfs
            host_store_mount=/sysroot/nix/.host-store
            host_store_root="$host_store_mount/.nixos-usb/store"
            host_store_image="$host_store_root/nix-store.squashfs"
            host_rw_root="$host_store_root/rw"
            upper_size_mib=${toString usbStore.upperSizeMiB}

            if [ ! -f "$lower_store_image" ]; then
              echo "initrd-usb-host-auto-store-prepare: missing $lower_store_image" >&2
              exit 1
            fi

            find_host_store_candidates() {
              min_bytes="$1"

              lsblk -pnrbo PATH,TYPE,RM,FSTYPE,SIZE |
                while IFS=' ' read -r path type removable fstype size; do
                  case "$type:$removable:$fstype" in
                    part:0:ext4 | part:0:ext3 | part:0:ext2 | part:0:xfs | part:0:btrfs)
                      if [ "$size" -ge "$min_bytes" ]; then
                        printf '%s\t%s\t%s\n' "$size" "$path" "$fstype"
                      fi
                      ;;
                  esac
                done |
                sort -nr
            }

            prepare_usb_fallback() {
              if mountpoint -q "$host_store_mount"; then
                umount "$host_store_mount" || true
              fi
              rm -rf "$host_store_mount"
              mkdir -p "$host_store_root" "$host_rw_root"
              ln -sfn "$lower_store_image" "$host_store_image"
              rm -rf "$host_rw_root/store" "$host_rw_root/work"
              printf '%s\n' "writable-overlay-host-auto-usb-fallback" > /run/nixos-usb-store-mode
            }

            image_bytes="$(stat -c %s "$lower_store_image")"
            min_bytes=$((image_bytes + (upper_size_mib + 1024) * 1024 * 1024))
            candidate_file=/run/nixos-usb-host-store-candidates

            mkdir -p /run "$host_store_mount"
            find_host_store_candidates "$min_bytes" > "$candidate_file"

            while IFS='	' read -r _size device fstype; do
              [ -n "$device" ] || continue

              if ! mount -o rw,noatime "$device" "$host_store_mount"; then
                echo "initrd-usb-host-auto-store-prepare: failed to mount $device ($fstype)" >&2
                continue
              fi

              mkdir -p "$host_store_root" "$host_rw_root"
              rm -f "$host_store_image.tmp"

              if cp "$lower_store_image" "$host_store_image.tmp" && mv "$host_store_image.tmp" "$host_store_image"; then
                rm -rf "$host_rw_root/store" "$host_rw_root/work"
                printf '%s\n' "writable-host-auto-overlay" > /run/nixos-usb-store-mode
                exit 0
              fi

              echo "initrd-usb-host-auto-store-prepare: failed to copy squashfs to $device ($fstype)" >&2
              rm -f "$host_store_image.tmp"
              umount "$host_store_mount" || true
            done < "$candidate_file"

            echo "initrd-usb-host-auto-store-prepare: using USB-root fallback" >&2
            prepare_usb_fallback
          '';
        };
      })
    ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
