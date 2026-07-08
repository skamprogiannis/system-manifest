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

      assert_unit_mount_dependency() {
        local dependent_unit="$1"
        local required_path="$2"
        local label="$3"

        if ! ${pkgs.gnugrep}/bin/grep -F 'RequiresMountsFor=' "$dependent_unit" | ${pkgs.gnugrep}/bin/grep -Fq -- "$required_path"; then
          echo "Expected $label to require mount path: $required_path" >&2
          ${pkgs.gnused}/bin/sed 's/^/  /' "$dependent_unit" >&2
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

      assert_initrd_bins() {
        local initrd_dir="$1"
        local label="$2"
        local bin_dir
        shift 2

        bin_dir="$initrd_dir/bin"
        if [ -L "$bin_dir" ]; then
          bin_dir="$initrd_dir$(readlink "$bin_dir")"
        fi

        for name in "$@"; do
          local bin_path="$bin_dir/$name"
          local target_path="$bin_path"

          if [ -L "$bin_path" ]; then
            local link_target
            link_target="$(readlink "$bin_path")"
            case "$link_target" in
              /nix/store/*)
                target_path="$initrd_dir$link_target"
                ;;
            esac
          fi

          if [ ! -e "$target_path" ]; then
            echo "Expected $label initrd to contain /bin/$name." >&2
            find "$bin_dir" -maxdepth 1 \( -type f -o -type l \) | sort >&2
            exit 1
          fi
        done
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
        assert_contains "/bin/mountpoint -q" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "/bin/mount -t tmpfs" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "/bin/cp" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "nixos-usb-store-diagnostics" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "image_bytes" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "required_bytes" ${usbRamStorePrepareScript} "ram-store prep script"
        assert_contains "fallback_reason" ${usbRamStorePrepareScript} "ram-store prep script"
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
        assert_contains "What=/sysroot/nix/.host-scratch/store/nix-store.squashfs" "$ro_unit" "host-auto /nix/.ro-store unit"
        assert_contains "What=/sysroot/nix/.host-store-rw" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "Type=none" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains "bind" "$rw_unit" "host-auto /nix/.rw-store unit"
        assert_contains_once "lowerdir=/sysroot/nix/.ro-store" "$store_unit" "host-auto /nix/store unit"
        assert_contains_once "upperdir=/sysroot/nix/.rw-store/store" "$store_unit" "host-auto /nix/store unit"
        assert_contains_once "workdir=/sysroot/nix/.rw-store/work" "$store_unit" "host-auto /nix/store unit"
        assert_unit_mount_dependency "$ro_unit" "/sysroot/nix/.host-scratch" "host-auto /nix/.ro-store unit"
        assert_unit_mount_dependency "$rw_unit" "/sysroot/nix/.host-store-rw" "host-auto /nix/.rw-store unit"
        assert_unit_mount_dependency "$rw_unit" "/sysroot/nix/.host-scratch" "host-auto /nix/.rw-store unit"
        assert_unit_mount_dependency "$store_unit" "/sysroot/nix/.ro-store" "host-auto /nix/store unit"
        assert_unit_mount_dependency "$store_unit" "/sysroot/nix/.rw-store" "host-auto /nix/store unit"
        assert_contains "find_host_store_candidates" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "/bin/lsblk" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "printf '10\\t%s\\t%s\\t%s\\t%s\\n'" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "/bin/stat -f -c '%a %S'" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "/bin/mountpoint -q" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains '/bin/mount -t "$mount_type" -o rw,noatime' ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "/bin/mkdir -m 0755 -p" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains ".nixos-usb/session" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "luksFormat" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "writable-encrypted-host-auto-overlay" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "part:0:ntfs | part:0:ntfs3)" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "part:0:exfat)" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "/bin/mount --bind" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "/bin/sort -k1,1n -k2,2nr" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "nixos-usb-store-diagnostics" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "candidate_count" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "attempted_available_bytes" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "fallback_reason" ${usbHostAutoStorePrepareScript} "host-auto prep script"
        assert_contains "writable-overlay-host-auto-usb-fallback" ${usbHostAutoStorePrepareScript} "host-auto prep script"
      }

      unpack_initrd ${usbInitrd} default-initrd
      generate_mount_units default-initrd default-generated
      assert_default_units default-generated

      find_closure_unit="$(find_static_unit default-initrd 'initrd-find-nixos-closure.service')"
      assert_contains "RequiresMountsFor=/sysroot/nix/store" "$find_closure_unit" "initrd-find-nixos-closure unit"

      unpack_initrd ${usbRamStoreInitrd} ram-initrd
      generate_mount_units ram-initrd ram-generated
      assert_initrd_bins ram-initrd ram-store cat cp ln lsblk mkdir mount mountpoint mv rm sort stat umount wc
      assert_ram_units ram-initrd ram-generated

      unpack_initrd ${usbHostAutoStoreInitrd} host-auto-initrd
      generate_mount_units host-auto-initrd host-auto-generated
      assert_initrd_bins host-auto-initrd host-auto cat chmod cryptsetup cp dd ln lsblk mkdir mkfs.ext4 mount mountpoint mv rm sort stat sync truncate umount wc
      assert_host_auto_units host-auto-initrd host-auto-generated

      touch "$out"
    '';
}
