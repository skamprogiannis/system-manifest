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
  hostScratchMount = "/nix/.host-scratch";
  hostStoreRwMount = "/nix/.host-store-rw";
  roStoreMount = "/nix/.ro-store";
  rwStoreMount = "/nix/.rw-store";
  storeMount = "/nix/store";
  roStoreDevice =
    if usbStore.mode == "ram-backed"
    then "/sysroot/nix/.ram-store-image/nix-store.squashfs"
    else if usbStore.mode == "host-auto"
    then "/sysroot/nix/.host-scratch/store/nix-store.squashfs"
    else "/sysroot/nix-store.squashfs";
  roStoreMountUnit = "${utils.escapeSystemdPath "/sysroot/nix/.ro-store"}.mount";
  rwStoreMountUnit = "${utils.escapeSystemdPath "/sysroot/nix/.rw-store"}.mount";
  hostAutoRoStoreDepends = lib.optionals (usbStore.mode == "host-auto") [
    hostScratchMount
  ];
  hostAutoRwStoreDepends = lib.optionals (usbStore.mode == "host-auto") [
    hostStoreRwMount
    hostScratchMount
  ];
  overlayStoreDepends = [
    roStoreMount
    rwStoreMount
  ];
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
        or tries to use a writable host partition for the squashfs image
        and, when the filesystem supports OverlayFS upperdirs, the writable
        overlay layer.
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

    hostScratchMinFreeMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8192;
      description = ''
        Extra host partition capacity required before host-auto creates an
        encrypted scratch image for the copied squashfs, writable store overlay,
        Docker state, local caches, Codex state, Brave profile, and repositories.
      '';
    };

    hostScratchMaxSizeMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 65536;
      description = "Maximum size of the sparse encrypted host scratch image created by host-auto mode.";
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
    boot.initrd.kernelModules =
      ["loop" "squashfs" "overlay"]
      ++ lib.optionals (usbStore.mode == "host-auto") ["ntfs3" "exfat"];
    boot.initrd.supportedFilesystems = lib.mkIf (usbStore.mode == "host-auto") [
      "ext2"
      "ext3"
      "ext4"
      "xfs"
      "btrfs"
      "ntfs3"
      "exfat"
    ];
    boot.initrd.systemd.emergencyAccess = true;
    boot.initrd.systemd.extraBin = lib.mkIf (usbStore.mode == "ram-backed" || usbStore.mode == "host-auto") (lib.mapAttrs (_: lib.mkDefault) {
      cat = "${pkgs.coreutils}/bin/cat";
      chmod = "${pkgs.coreutils}/bin/chmod";
      cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
      cp = "${pkgs.coreutils}/bin/cp";
      dd = "${pkgs.coreutils}/bin/dd";
      ln = "${pkgs.coreutils}/bin/ln";
      lsblk = "${pkgs.util-linux}/bin/lsblk";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      "mkfs.ext4" = "${pkgs.e2fsprogs}/bin/mkfs.ext4";
      mount = "${pkgs.util-linux}/bin/mount";
      mountpoint = "${pkgs.util-linux}/bin/mountpoint";
      mv = "${pkgs.coreutils}/bin/mv";
      rm = "${pkgs.coreutils}/bin/rm";
      sort = "${pkgs.coreutils}/bin/sort";
      stat = "${pkgs.coreutils}/bin/stat";
      sync = "${pkgs.coreutils}/bin/sync";
      truncate = "${pkgs.coreutils}/bin/truncate";
      umount = "${pkgs.util-linux}/bin/umount";
      wc = "${pkgs.coreutils}/bin/wc";
    });
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
    fileSystems.${roStoreMount} = {
      device = roStoreDevice;
      fsType = "squashfs";
      depends = hostAutoRoStoreDepends;
      options =
        [
          "loop"
        ]
        ++ lib.optional (config.boot.kernelPackages.kernel.kernelAtLeast "6.2") "threads=multi";
      neededForBoot = true;
    };

    fileSystems.${rwStoreMount} =
      if usbStore.mode == "ram-backed"
      then {
        device = "/nix/.ram-store-rw";
        fsType = "none";
        options = ["bind"];
        neededForBoot = true;
      }
      else if usbStore.mode == "host-auto"
      then {
        device = hostStoreRwMount;
        fsType = "none";
        depends = hostAutoRwStoreDepends;
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

    fileSystems.${storeMount} = {
      overlay = {
        lowerdir = [roStoreMount];
        upperdir = "${rwStoreMount}/store";
        workdir = "${rwStoreMount}/work";
      };
      depends = overlayStoreDepends;
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
            diagnostics_file=/run/nixos-usb-store-diagnostics

            write_diag() {
              printf '%s=%s\n' "$1" "$2" >> "$diagnostics_file"
            }

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
              reason="$1"
              if /bin/mountpoint -q "$ram_store_dir"; then
                /bin/umount "$ram_store_dir" || true
              fi
              /bin/rm -rf "$ram_store_dir"
              /bin/mkdir -p "$ram_store_dir"
              /bin/ln -sfn "$lower_store_image" "$ram_store_image"
              printf '%s\n' "writable-scratch-overlay-usb-lower" > /run/nixos-usb-store-mode
              write_diag fallback_reason "$reason"
              write_diag selected_lower usb
              write_diag selected_rw usb-root-scratch
            }

            /bin/mkdir -p /run "$ram_store_dir" "$scratch_store_dir"
            /bin/rm -rf "$scratch_store_dir/store" "$scratch_store_dir/work"
            : > "$diagnostics_file"
            write_diag requested_mode ram-backed
            write_diag store_image "$lower_store_image"

            image_bytes="$(/bin/stat -c %s "$lower_store_image")"
            mem_available_kib="$(read_meminfo_kib MemAvailable || read_meminfo_kib MemTotal)"
            available_bytes=$((mem_available_kib * 1024))
            required_bytes=$((image_bytes + ${toString usbStore.ramModeSafetyMiB} * 1024 * 1024))
            write_diag image_bytes "$image_bytes"
            write_diag mem_available_kib "$mem_available_kib"
            write_diag available_bytes "$available_bytes"
            write_diag required_bytes "$required_bytes"
            write_diag ram_tmpfs_percent ${toString usbStore.ramImageTmpfsPercent}
            write_diag ram_safety_mib ${toString usbStore.ramModeSafetyMiB}

            if [ "$available_bytes" -lt "$required_bytes" ]; then
              echo "initrd-usb-ram-store-prepare: insufficient memory, using USB lower image" >&2
              fall_back_to_usb_image insufficient-memory
              exit 0
            fi

            if /bin/mount -t tmpfs -o mode=0755,size=${toString usbStore.ramImageTmpfsPercent}% tmpfs "$ram_store_dir" \
              && /bin/cp "$lower_store_image" "$ram_store_image"; then
              printf '%s\n' "writable-scratch-overlay-ram-lower" > /run/nixos-usb-store-mode
              write_diag selected_lower ram
              write_diag selected_rw usb-root-scratch
            else
              echo "initrd-usb-ram-store-prepare: RAM copy failed, using USB lower image" >&2
              fall_back_to_usb_image ram-copy-failed
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
            host_scratch_mount=/sysroot/nix/.host-scratch
            host_session_root="$host_store_mount/.nixos-usb/session"
            boot_id="$(/bin/cat /proc/sys/kernel/random/boot_id)"
            host_boot_root="$host_session_root/$boot_id"
            host_scratch_image="$host_boot_root/scratch.img"
            host_scratch_key=/run/nixos-usb-host-scratch.key
            host_scratch_mapper=nixos-usb-host-scratch
            host_scratch_device="/dev/mapper/$host_scratch_mapper"
            host_store_root="$host_scratch_mount/store"
            host_store_image="$host_store_root/nix-store.squashfs"
            host_rw_root="$host_store_root/rw"
            rw_store_root=/sysroot/nix/.host-store-rw
            upper_size_mib=${toString usbStore.upperSizeMiB}
            scratch_min_free_mib=${toString usbStore.hostScratchMinFreeMiB}
            scratch_max_size_mib=${toString usbStore.hostScratchMaxSizeMiB}
            diagnostics_file=/run/nixos-usb-store-diagnostics
            mount_error=/run/nixos-usb-host-store-mount.err

            write_diag() {
              printf '%s=%s\n' "$1" "$2" >> "$diagnostics_file"
            }

            if [ ! -f "$lower_store_image" ]; then
              echo "initrd-usb-host-auto-store-prepare: missing $lower_store_image" >&2
              exit 1
            fi

            find_host_store_candidates() {
              min_bytes="$1"

              /bin/lsblk -pnrbo PATH,TYPE,RM,FSTYPE,SIZE |
                while IFS=' ' read -r path type removable fstype size; do
                  case "$type:$removable:$fstype" in
                    part:0:ext4 | part:0:ext3 | part:0:ext2 | part:0:xfs | part:0:btrfs)
                      if [ "$size" -ge "$min_bytes" ]; then
                        printf '10\t%s\t%s\t%s\t%s\n' "$size" "$path" "$fstype" "$fstype"
                      fi
                      ;;
                    part:0:ntfs | part:0:ntfs3)
                      if [ "$size" -ge "$min_bytes" ]; then
                        printf '20\t%s\t%s\t%s\tntfs3\n' "$size" "$path" "$fstype"
                      fi
                      ;;
                    part:0:exfat)
                      if [ "$size" -ge "$min_bytes" ]; then
                        printf '30\t%s\t%s\t%s\texfat\n' "$size" "$path" "$fstype"
                      fi
                      ;;
                  esac
                done |
                /bin/sort -k1,1n -k2,2nr
            }

            prepare_rw_dirs() {
              rw_root="$1"
              /bin/rm -rf "$rw_root/store" "$rw_root/work"
              /bin/mkdir -m 0755 -p "$rw_root/store" "$rw_root/work"
            }

            prepare_host_rw() {
              prepare_rw_dirs "$host_rw_root"
              /bin/mkdir -p "$rw_store_root"
              if /bin/mountpoint -q "$rw_store_root"; then
                /bin/umount "$rw_store_root" || true
              fi
              /bin/mount --bind "$host_rw_root" "$rw_store_root"
            }

            read_host_available_bytes() {
              stat_output="$(/bin/stat -f -c '%a %S' "$host_store_mount")" || return 1
              set -- $stat_output
              printf '%s\n' "$(($1 * $2))"
            }

            prepare_encrypted_host_scratch() {
              available_bytes="$(read_host_available_bytes)" || return 1
              write_diag attempted_available_bytes "$available_bytes"
              if [ "$available_bytes" -lt "$min_bytes" ]; then
                return 1
              fi

              /bin/rm -rf "$host_session_root" "$host_store_mount/.nixos-usb/store" "$host_store_mount/.nixos-usb/docker" "$host_store_mount/.nixos-usb/cache" "$host_store_mount/.nixos-usb/codex" "$host_store_mount/.nixos-usb/brave" "$host_store_mount/.nixos-usb/repositories"
              /bin/mkdir -p "$host_boot_root" "$host_scratch_mount"

              scratch_size_mib=$((available_bytes / 1024 / 1024 - 1024))
              if [ "$scratch_size_mib" -gt "$scratch_max_size_mib" ]; then
                scratch_size_mib="$scratch_max_size_mib"
              fi
              if [ "$scratch_size_mib" -lt "$scratch_min_free_mib" ]; then
                return 1
              fi

              /bin/dd if=/dev/urandom of="$host_scratch_key" bs=64 count=1 || return 1
              /bin/chmod 0400 "$host_scratch_key" || return 1
              /bin/truncate -s "$scratch_size_mib"M "$host_scratch_image" || return 1
              /bin/cryptsetup --batch-mode --key-file "$host_scratch_key" luksFormat "$host_scratch_image" || return 1
              /bin/cryptsetup open --key-file "$host_scratch_key" "$host_scratch_image" "$host_scratch_mapper" || return 1
              /bin/mkfs.ext4 -F -q "$host_scratch_device" || return 1
              /bin/mount -t ext4 -o rw,noatime "$host_scratch_device" "$host_scratch_mount" || return 1
              /bin/mkdir -p "$host_store_root" || return 1

              write_diag encrypted_scratch_image "$host_scratch_image"
              write_diag encrypted_scratch_size_mib "$scratch_size_mib"
              write_diag encrypted_scratch_mapper "$host_scratch_mapper"
            }

            prepare_usb_rw() {
              if /bin/mountpoint -q "$rw_store_root"; then
                /bin/umount "$rw_store_root" || true
              fi
              /bin/mkdir -p "$rw_store_root"
              prepare_rw_dirs "$rw_store_root"
            }

            prepare_usb_fallback() {
              reason="$1"
              if /bin/mountpoint -q "$host_scratch_mount"; then
                /bin/umount "$host_scratch_mount" || true
              fi
              if [ -e "$host_scratch_device" ]; then
                /bin/cryptsetup close "$host_scratch_mapper" || true
              fi
              if /bin/mountpoint -q "$host_store_mount"; then
                /bin/umount "$host_store_mount" || true
              fi
              /bin/rm -rf "$host_store_mount" "$host_scratch_mount"
              /bin/mkdir -p "$host_store_root" "$host_rw_root"
              /bin/ln -sfn "$lower_store_image" "$host_store_image"
              prepare_usb_rw
              printf '%s\n' "writable-overlay-host-auto-usb-fallback" > /run/nixos-usb-store-mode
              write_diag fallback_reason "$reason"
              write_diag selected_lower usb
              write_diag selected_rw usb-root-scratch
            }

            image_bytes="$(/bin/stat -c %s "$lower_store_image")"
            min_bytes=$((image_bytes + (upper_size_mib + scratch_min_free_mib + 1024) * 1024 * 1024))
            candidate_file=/run/nixos-usb-host-store-candidates

            /bin/mkdir -p /run "$host_store_mount" "$host_scratch_mount" "$rw_store_root"
            : > "$diagnostics_file"
            : > "$mount_error"
            write_diag requested_mode host-auto
            write_diag store_image "$lower_store_image"
            write_diag image_bytes "$image_bytes"
            write_diag upper_size_mib "$upper_size_mib"
            write_diag scratch_min_free_mib "$scratch_min_free_mib"
            write_diag scratch_max_size_mib "$scratch_max_size_mib"
            write_diag min_candidate_bytes "$min_bytes"
            find_host_store_candidates "$min_bytes" > "$candidate_file"
            write_diag candidate_count "$(/bin/wc -l < "$candidate_file")"

            if [ ! -s "$candidate_file" ]; then
              echo "initrd-usb-host-auto-store-prepare: no host store candidates found" >&2
              prepare_usb_fallback no-candidates
              exit 0
            fi

            while IFS='	' read -r _priority size device fstype mount_type; do
              [ -n "$device" ] || continue
              write_diag attempted_device "$device"
              write_diag attempted_fstype "$fstype"
              write_diag attempted_mount_type "$mount_type"

              if ! /bin/mount -t "$mount_type" -o rw,noatime "$device" "$host_store_mount" 2>"$mount_error"; then
                echo "initrd-usb-host-auto-store-prepare: failed to mount $device ($fstype)" >&2
                if [ -s "$mount_error" ]; then
                  /bin/cat "$mount_error" >&2
                fi
                continue
              fi

              if ! prepare_encrypted_host_scratch "$size"; then
                echo "initrd-usb-host-auto-store-prepare: failed to prepare encrypted host scratch on $device ($fstype)" >&2
                if /bin/mountpoint -q "$host_scratch_mount"; then
                  /bin/umount "$host_scratch_mount" || true
                fi
                if [ -e "$host_scratch_device" ]; then
                  /bin/cryptsetup close "$host_scratch_mapper" || true
                fi
                /bin/rm -f "$host_scratch_image"
                /bin/umount "$host_store_mount" || true
                continue
              fi

              /bin/mkdir -p "$host_store_root" "$host_rw_root"
              /bin/rm -f "$host_store_image.tmp"

              if /bin/cp "$lower_store_image" "$host_store_image.tmp" && /bin/mv "$host_store_image.tmp" "$host_store_image"; then
                if ! prepare_host_rw; then
                  echo "initrd-usb-host-auto-store-prepare: failed to prepare encrypted host rw overlay on $device ($fstype)" >&2
                  /bin/umount "$host_scratch_mount" || true
                  /bin/cryptsetup close "$host_scratch_mapper" || true
                  /bin/rm -f "$host_scratch_image"
                  /bin/umount "$host_store_mount" || true
                  continue
                fi
                printf '%s\n' "writable-encrypted-host-auto-overlay" > /run/nixos-usb-store-mode
                write_diag selected_rw encrypted-host
                write_diag selected_device "$device"
                write_diag selected_fstype "$fstype"
                write_diag selected_mount_type "$mount_type"
                write_diag selected_lower encrypted-host
                exit 0
              fi

              echo "initrd-usb-host-auto-store-prepare: failed to copy squashfs to $device ($fstype)" >&2
              /bin/rm -f "$host_store_image.tmp"
              /bin/umount "$host_scratch_mount" || true
              /bin/cryptsetup close "$host_scratch_mapper" || true
              /bin/rm -f "$host_scratch_image"
              /bin/umount "$host_store_mount" || true
            done < "$candidate_file"

            echo "initrd-usb-host-auto-store-prepare: using USB-root fallback" >&2
            prepare_usb_fallback all-candidates-failed
          '';
        };
      })
    ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
