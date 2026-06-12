{ctx}: let
  inherit
    (ctx)
    pkgs
    usbHostAutoStoreInitrd
    usbHostAutoStorePrepareScript
    usbInitrd
    usbRamStoreInitrd
    usbRamStorePrepareScript
    ;
in {
  usb-initrd-ordering =
    pkgs.runCommand "usb-initrd-ordering-check" {
      nativeBuildInputs = [
        pkgs.cpio
        pkgs.findutils
        pkgs.gnugrep
        pkgs.systemd
        pkgs.zstd
      ];
    } ''
      set -euo pipefail

      unpack_initrd() {
        local image="$1"
        local target="$2"
        mkdir -p "$target"
        (cd "$target" && zstdcat "$image/initrd" | cpio -id --quiet)
      }

      generate_mount_units() {
        local initrd_dir="$1"
        local generated_dir="$2"
        local fstab

        fstab="$(find "$initrd_dir/nix/store" -maxdepth 1 -type f -name '*-initrd-fstab' -print -quit)"
        if [ -z "$fstab" ]; then
          echo "Expected initrd-fstab in $initrd_dir." >&2
          find "$initrd_dir/nix/store" -maxdepth 1 -type f -print >&2
          exit 1
        fi

        mkdir -p "$generated_dir" "$generated_dir.early" "$generated_dir.late"
        SYSTEMD_IN_INITRD=1 SYSTEMD_SYSROOT_FSTAB="$fstab" \
          ${pkgs.systemd}/lib/systemd/system-generators/systemd-fstab-generator "$generated_dir" "$generated_dir.early" "$generated_dir.late"
      }

      find_unit() {
        local dir="$1"
        local pattern="$2"
        local unit

        unit="$(find "$dir" "$dir.early" "$dir.late" -type f -name "$pattern" -print -quit)"
        if [ -z "$unit" ]; then
          echo "Expected generated unit matching $pattern." >&2
          find "$dir" "$dir.early" "$dir.late" -type f -print >&2
          exit 1
        fi

        printf '%s\n' "$unit"
      }

      find_static_unit() {
        local initrd_dir="$1"
        local unit_name="$2"
        local unit

        unit="$(find "$initrd_dir" -type f -name "$unit_name" -print -quit)"
        if [ -z "$unit" ]; then
          echo "Expected static initrd unit $unit_name." >&2
          find "$initrd_dir" -type f -name '*.service' -print >&2
          exit 1
        fi

        printf '%s\n' "$unit"
      }

      assert_contains() {
        local needle="$1"
        local file="$2"
        local label="$3"

        if ! grep -Fq "$needle" "$file"; then
          echo "Expected $label to contain: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_contains_once() {
        local needle="$1"
        local file="$2"
        local label="$3"
        local count

        count="$(grep -oF "$needle" "$file" | wc -l)"
        if [ "$count" -ne 1 ]; then
          echo "Expected $label to contain exactly once: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_static_unit_count() {
        local initrd_dir="$1"
        local pattern="$2"
        local expected="$3"
        local label="$4"
        local count

        count="$(find "$initrd_dir" -type f -name "$pattern" | wc -l)"
        if [ "$count" -ne "$expected" ]; then
          echo "Expected $label count to be $expected, found $count." >&2
          find "$initrd_dir" -type f -name "$pattern" -print >&2
          exit 1
        fi
      }

      assert_default_units() {
        local generated_dir="$1"
        local ro_unit rw_unit store_unit

        ro_unit="$(find_unit "$generated_dir" 'sysroot-nix-.ro*store.mount')"
        rw_unit="$(find_unit "$generated_dir" 'sysroot-nix-.rw*store.mount')"
        store_unit="$(find_unit "$generated_dir" 'sysroot-nix-store.mount')"

        assert_contains "What=/sysroot/nix-store.squashfs" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "Where=/sysroot/nix/.ro-store" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "Type=squashfs" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "loop" "$ro_unit" "default /nix/.ro-store unit"
        assert_contains "threads=multi" "$ro_unit" "default /nix/.ro-store unit"

        assert_contains "What=tmpfs" "$rw_unit" "default /nix/.rw-store unit"
        assert_contains "Type=tmpfs" "$rw_unit" "default /nix/.rw-store unit"
        assert_contains "size=2048M" "$rw_unit" "default /nix/.rw-store unit"

        assert_contains "Type=overlay" "$store_unit" "default /nix/store unit"
        assert_contains "lowerdir=/sysroot/nix/.ro-store" "$store_unit" "default /nix/store unit"
        assert_contains "upperdir=/sysroot/nix/.rw-store/store" "$store_unit" "default /nix/store unit"
        assert_contains "workdir=/sysroot/nix/.rw-store/work" "$store_unit" "default /nix/store unit"
      }

      assert_ram_units() {
        local initrd_dir="$1"
        local generated_dir="$2"
        local ro_unit rw_unit prep_unit

        ro_unit="$(find_unit "$generated_dir" 'sysroot-nix-.ro*store.mount')"
        rw_unit="$(find_unit "$generated_dir" 'sysroot-nix-.rw*store.mount')"
        prep_unit="$(find_static_unit "$initrd_dir" 'initrd-usb-ram-store-prepare.service')"

        assert_contains "What=/sysroot/nix/.ram-store-image/nix-store.squashfs" "$ro_unit" "ram-store /nix/.ro-store unit"
        assert_contains "What=/sysroot/nix/.ram-store-rw" "$rw_unit" "ram-store /nix/.rw-store unit"
        assert_contains "Type=none" "$rw_unit" "ram-store /nix/.rw-store unit"
        assert_contains "bind" "$rw_unit" "ram-store /nix/.rw-store unit"
        assert_contains "Before=sysroot-nix-.ro\\x2dstore.mount sysroot-nix-.rw\\x2dstore.mount" "$prep_unit" "ram-store prep unit"
        assert_contains "${pkgs.util-linux}/bin/mountpoint -q" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "${pkgs.util-linux}/bin/mount -t tmpfs" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "${pkgs.coreutils}/bin/cp" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "writable-scratch-overlay-ram-lower" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "writable-scratch-overlay-usb-lower" ${usbRamStorePrepareScript} "ram-store prep script"
      }

      assert_host_auto_units() {
        local initrd_dir="$1"
        local generated_dir="$2"
        local ro_unit rw_unit store_unit prep_unit

        ro_unit="$(find_unit "$generated_dir" 'sysroot-nix-.ro*store.mount')"
        rw_unit="$(find_unit "$generated_dir" 'sysroot-nix-.rw*store.mount')"
        store_unit="$(find_unit "$generated_dir" 'sysroot-nix-store.mount')"
        prep_unit="$(find_static_unit "$initrd_dir" 'initrd-usb-host-auto-store-prepare.service')"

        assert_static_unit_count "$initrd_dir" '*host-auto-store-prepare.service' 1 "host-auto prepare service"
        assert_contains "What=/sysroot/nix/.host-store/.nixos-usb/store/nix-store.squashfs" "$ro_unit" "host-auto /nix/.ro-store unit"
        assert_contains "What=/sysroot/nix/.host-store/.nixos-usb/store/rw" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "Type=none" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "bind" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains_once "lowerdir=/sysroot/nix/.ro-store" "$store_unit" "host-auto /nix/store unit"
        assert_contains_once "upperdir=/sysroot/nix/.rw-store/store" "$store_unit" "host-auto /nix/store unit"
        assert_contains_once "workdir=/sysroot/nix/.rw-store/work" "$store_unit" "host-auto /nix/store unit"
        assert_contains "find_host_store_candidates" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.util-linux}/bin/lsblk" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.util-linux}/bin/mountpoint -q" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.util-linux}/bin/mount -o rw,noatime" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "${pkgs.coreutils}/bin/mkdir -m 0755 -p" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains ".nixos-usb/store" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "writable-host-auto-overlay" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "writable-overlay-host-auto-usb-fallback" ${usbHostAutoStorePrepareScript} "host-auto prep script"
      }

      unpack_initrd ${usbInitrd} default-initrd
      generate_mount_units default-initrd default-generated
      assert_default_units default-generated

      find_closure_unit="$(find_static_unit default-initrd 'initrd-find-nixos-closure.service')"
      assert_contains "RequiresMountsFor=/sysroot/nix/store" "$find_closure_unit" "initrd-find-nixos-closure unit"

      unpack_initrd ${usbRamStoreInitrd} ram-initrd
      generate_mount_units ram-initrd ram-generated
      assert_ram_units ram-initrd ram-generated

      unpack_initrd ${usbHostAutoStoreInitrd} host-auto-initrd
      generate_mount_units host-auto-initrd host-auto-generated
      assert_host_auto_units host-auto-initrd host-auto-generated

      touch "$out"
    '';
}
