{pkgs, ...}: {
  systemd.services.system-manifest-host-fingerprint = {
    description = "Publish a privacy-preserving physical host fingerprint";
    wantedBy = ["display-manager.service"];
    before = ["display-manager.service"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "system-manifest";
      RuntimeDirectoryMode = "0755";
    };

    script = ''
      set -eu

      dmi_uuid_file="''${SYSTEM_MANIFEST_DMI_UUID_FILE:-/sys/class/dmi/id/product_uuid}"
      product_serial_file="''${SYSTEM_MANIFEST_PRODUCT_SERIAL_FILE:-/sys/class/dmi/id/product_serial}"
      board_serial_file="''${SYSTEM_MANIFEST_BOARD_SERIAL_FILE:-/sys/class/dmi/id/board_serial}"
      chassis_serial_file="''${SYSTEM_MANIFEST_CHASSIS_SERIAL_FILE:-/sys/class/dmi/id/chassis_serial}"
      output_file="''${SYSTEM_MANIFEST_HOST_FINGERPRINT_FILE:-/run/system-manifest/host-fingerprint}"
      identity=""

      read_normalized_serial() {
        serial_file="$1"
        serial=""
        if [ -r "$serial_file" ]; then
          IFS= read -r serial < "$serial_file" || true
          serial="$(
            printf '%s' "$serial" |
              ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]' |
              ${pkgs.gnused}/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
          )"
        fi
        case "$serial" in
          ""|"0"|"none"|"unknown"|"default string"|"not specified"|"system serial number"|"to be filled by o.e.m."|"to be filled by oem")
            return 1
            ;;
        esac
        if printf '%s\n' "$serial" | ${pkgs.gnugrep}/bin/grep -Eq '^(0+|f+|-+)$'; then
          return 1
        fi
        printf '%s' "$serial"
      }

      if [ -r "$dmi_uuid_file" ]; then
        dmi_uuid="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < "$dmi_uuid_file" | ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]')"
        if printf '%s\n' "$dmi_uuid" | ${pkgs.gnugrep}/bin/grep -Eq \
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' &&
          [ "$dmi_uuid" != "00000000-0000-0000-0000-000000000000" ] &&
          [ "$dmi_uuid" != "ffffffff-ffff-ffff-ffff-ffffffffffff" ]; then
          identity="dmi:$dmi_uuid"
        fi
      fi

      if [ -z "$identity" ]; then
        product_serial="$(read_normalized_serial "$product_serial_file" || true)"
        board_serial="$(read_normalized_serial "$board_serial_file" || true)"
        chassis_serial="$(read_normalized_serial "$chassis_serial_file" || true)"
        if [ -n "$product_serial$board_serial$chassis_serial" ]; then
          identity="serials:product=$product_serial|board=$board_serial|chassis=$chassis_serial"
        fi
      fi

      output_dir="$(${pkgs.coreutils}/bin/dirname "$output_file")"
      ${pkgs.coreutils}/bin/mkdir -p -- "$output_dir"
      ${pkgs.coreutils}/bin/rm -f -- "$output_file"
      if [ -z "$identity" ]; then
        exit 0
      fi
      output_tmp="$(${pkgs.coreutils}/bin/mktemp "$output_file.tmp.XXXXXX")"
      printf '%s' "$identity" |
        ${pkgs.coreutils}/bin/sha256sum |
        ${pkgs.coreutils}/bin/cut -d ' ' -f 1 > "$output_tmp"
      ${pkgs.coreutils}/bin/chmod 0444 "$output_tmp"
      ${pkgs.coreutils}/bin/mv -f -- "$output_tmp" "$output_file"
    '';
  };
}
