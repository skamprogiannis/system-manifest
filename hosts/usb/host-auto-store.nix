{
  pkgs,
  lib,
  ...
}: let
  mountUnit = path: "${lib.strings.replaceStrings ["/" "-"] ["-" "\\x2d"] (lib.strings.removePrefix "/" path)}.mount";
  roStoreMount = mountUnit "/sysroot/nix/.ro-store";
  rwStoreMount = mountUnit "/sysroot/nix/.rw-store";
  coreutils = "${pkgs.coreutils}/bin";
  utilLinux = "${pkgs.util-linux}/bin";
in {
  boot.initrd.systemd.enable = true;

  # The base USB profile creates a volatile tmpfs overlay in postMountCommands.
  # host-auto-store uses initrd systemd mounts instead so the upperdir can live
  # on a prepared host filesystem when one is available.
  boot.initrd.postMountCommands = lib.mkForce "";

  fileSystems."/nix/.ro-store" = {
    device = "/sysroot/nix/.host-store/.nixos-usb/store/nix-store.squashfs";
    fsType = "squashfs";
    neededForBoot = true;
    options = ["x-initrd.mount" "loop" "ro" "threads=multi"];
  };

  fileSystems."/nix/.rw-store" = {
    device = "/nix/.host-store/.nixos-usb/store/rw";
    fsType = "none";
    neededForBoot = true;
    options = ["x-initrd.mount" "bind"];
  };

  fileSystems."/nix/store" = {
    device = "overlay";
    fsType = "overlay";
    neededForBoot = true;
    options = [
      "lowerdir=/sysroot/nix/.ro-store"
      "upperdir=/sysroot/nix/.rw-store/store"
      "workdir=/sysroot/nix/.rw-store/work"
      "x-initrd.mount"
      "x-systemd.requires-mounts-for=/sysroot/nix/.ro-store"
      "x-systemd.requires-mounts-for=/sysroot/nix/.rw-store/store"
      "x-systemd.requires-mounts-for=/sysroot/nix/.rw-store/work"
    ];
  };

  boot.initrd.systemd.services.usb-host-auto-store-prepare = {
    description = "Prepare host-auto USB squashfs store paths";
    requires = ["sysroot.mount"];
    requiredBy = [roStoreMount rwStoreMount];
    after = ["sysroot.mount"];
    before = [roStoreMount rwStoreMount];
    unitConfig.DefaultDependencies = false;
    path = with pkgs; [
      bash
      coreutils
      gnused
      util-linux
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu

      lower_store_image=/sysroot/nix-store.squashfs
      host_store_mount=/sysroot/nix/.host-store
      host_store_root="$host_store_mount/.nixos-usb/store"
      host_store_image="$host_store_root/nix-store.squashfs"
      host_store_stamp="$host_store_root/nix-store.squashfs.source"
      host_rw_root="$host_store_root/rw"
      upper_size_mib=2048

      log() {
        echo "usb-host-auto-store: $*" >&2
      }

      if [ ! -f "$lower_store_image" ]; then
        log "missing $lower_store_image"
        exit 1
      fi

      source_stamp() {
        ${coreutils}/stat -c '%s:%Y' "$lower_store_image"
      }

      find_host_store_candidates() {
        min_bytes="$1"

        ${utilLinux}/lsblk -pnrbo PATH,TYPE,RM,FSTYPE,SIZE |
          while IFS=' ' read -r path type removable fstype size; do
            case "$type:$removable:$fstype" in
              part:0:ext4 | part:0:ext3 | part:0:ext2 | part:0:xfs | part:0:btrfs)
                if [ "$size" -ge "$min_bytes" ]; then
                  printf '%s\t%s\t%s\n' "$size" "$path" "$fstype"
                fi
                ;;
            esac
          done |
          ${coreutils}/sort -nr
      }

      prepare_rw_dirs() {
        ${coreutils}/rm -rf "$host_rw_root/store" "$host_rw_root/work"
        ${coreutils}/mkdir -m 0755 -p "$host_rw_root/store" "$host_rw_root/work"
      }

      prepare_usb_tmpfs_fallback() {
        if ${utilLinux}/mountpoint -q "$host_store_mount"; then
          ${utilLinux}/umount "$host_store_mount" || true
        fi
        ${coreutils}/rm -rf "$host_store_mount"
        ${coreutils}/mkdir -p "$host_store_mount"
        ${utilLinux}/mount -t tmpfs -o "mode=0755,size=''${upper_size_mib}M" tmpfs "$host_store_mount"
        ${coreutils}/mkdir -p "$host_store_root" "$host_rw_root"
        ${coreutils}/ln -sfn "$lower_store_image" "$host_store_image"
        printf '%s\n' "$(source_stamp)" > "$host_store_stamp"
        prepare_rw_dirs
        printf '%s\n' "writable-overlay-host-auto-tmpfs-fallback" > /run/nixos-usb-store-mode
      }

      copy_store_image_if_needed() {
        current_stamp="$(source_stamp)"
        if [ -f "$host_store_image" ] \
          && [ -f "$host_store_stamp" ] \
          && [ "$(${coreutils}/cat "$host_store_stamp")" = "$current_stamp" ]; then
          return 0
        fi

        ${coreutils}/rm -f "$host_store_image.tmp"
        ${coreutils}/cp "$lower_store_image" "$host_store_image.tmp"
        ${coreutils}/mv "$host_store_image.tmp" "$host_store_image"
        printf '%s\n' "$current_stamp" > "$host_store_stamp"
      }

      image_bytes="$(${coreutils}/stat -c %s "$lower_store_image")"
      min_bytes=$((image_bytes + (upper_size_mib + 1024) * 1024 * 1024))
      candidate_file=/run/nixos-usb-host-store-candidates

      ${coreutils}/mkdir -p /run "$host_store_mount"
      find_host_store_candidates "$min_bytes" > "$candidate_file"

      while IFS='	' read -r _size device fstype; do
        [ -n "$device" ] || continue

        if ! ${utilLinux}/mount -o rw,noatime "$device" "$host_store_mount"; then
          log "failed to mount $device ($fstype)"
          continue
        fi

        ${coreutils}/mkdir -p "$host_store_root" "$host_rw_root"

        if copy_store_image_if_needed; then
          prepare_rw_dirs
          printf '%s\n' "writable-host-auto-overlay" > /run/nixos-usb-store-mode
          exit 0
        fi

        log "failed to prepare squashfs image on $device ($fstype)"
        ${coreutils}/rm -f "$host_store_image.tmp"
        ${utilLinux}/umount "$host_store_mount" || true
      done < "$candidate_file"

      log "using tmpfs fallback; no eligible unencrypted host filesystem found"
      prepare_usb_tmpfs_fallback
    '';
  };
}
