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
      boot_id_file="''${SYSTEM_MANIFEST_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
      output_file="''${SYSTEM_MANIFEST_HOST_FINGERPRINT_FILE:-/run/system-manifest/host-fingerprint}"
      identity=""

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
        if [ -r "$boot_id_file" ]; then
          boot_id="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < "$boot_id_file" | ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]')"
        else
          boot_id=""
        fi
        if [ -z "$boot_id" ]; then
          boot_id="$(${pkgs.coreutils}/bin/od -An -N32 -tx1 /dev/urandom | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
        fi
        identity="boot:$boot_id"
      fi

      output_dir="$(${pkgs.coreutils}/bin/dirname "$output_file")"
      ${pkgs.coreutils}/bin/mkdir -p -- "$output_dir"
      output_tmp="$(${pkgs.coreutils}/bin/mktemp "$output_file.tmp.XXXXXX")"
      printf '%s' "$identity" |
        ${pkgs.coreutils}/bin/sha256sum |
        ${pkgs.coreutils}/bin/cut -d ' ' -f 1 > "$output_tmp"
      ${pkgs.coreutils}/bin/chmod 0444 "$output_tmp"
      ${pkgs.coreutils}/bin/mv -f -- "$output_tmp" "$output_file"
    '';
  };
}
