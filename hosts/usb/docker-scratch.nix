{
  pkgs,
  ...
}: let
  dockerScratchStart = pkgs.writeShellScript "docker-host-scratch-start" ''
    set -eu

    scratch_mount=/var/lib/docker-host-scratch
    docker_root=/var/lib/docker
    mount_error=/run/docker-host-scratch.mount.err

    mkdir -p "$scratch_mount" "$docker_root"
    rm -f "$mount_error"

    if ${pkgs.util-linux}/bin/findmnt -rn -M "$docker_root" >/dev/null 2>&1; then
      exit 0
    fi

    find_candidates() {
      pattern="$1"
      ${pkgs.util-linux}/bin/lsblk -pnrbo PATH,TYPE,RM,FSTYPE,SIZE \
        | ${pkgs.gawk}/bin/awk -v pattern="$pattern" '
            $2 == "part" && $3 == "0" && $4 ~ pattern && $5 > 20000000000 {
              print $5 "\t" $1 "\t" $4
            }
          ' \
        | ${pkgs.coreutils}/bin/sort -nr
    }

    try_candidates() {
      candidates="$1"
      candidate_file="$(mktemp)"
      if [ -z "$candidates" ]; then
        rm -f "$candidate_file"
        return 1
      fi

      printf '%s\n' "$candidates" > "$candidate_file"

      while IFS=$'\t' read -r _size device _fstype; do
        [ -n "$device" ] || continue
        if ${pkgs.util-linux}/bin/mount -o rw "$device" "$scratch_mount" 2>"$mount_error"; then
          rm -f "$candidate_file"
          printf '%s\n' "$device"
          return 0
        fi
      done < "$candidate_file"

      rm -f "$candidate_file"
      return 1
    }

    linux_candidates="$(find_candidates '^(ext4|ext3|ext2|xfs|btrfs)$')"
    other_candidates="$(find_candidates '^(ntfs|ntfs3|exfat)$')"

    selected_device="$(try_candidates "$linux_candidates" || true)"
    if [ -z "$selected_device" ]; then
      selected_device="$(try_candidates "$other_candidates" || true)"
    fi

    if [ -z "$selected_device" ]; then
      echo "docker-host-scratch: no writable host-local partition was mountable for Docker scratch" >&2
      if [ -s "$mount_error" ]; then
        cat "$mount_error" >&2
      fi
      exit 1
    fi

    mkdir -p "$scratch_mount/.nixos-usb" "$scratch_mount/.nixos-usb/docker"
    chmod 700 "$scratch_mount/.nixos-usb" "$scratch_mount/.nixos-usb/docker"
    ${pkgs.util-linux}/bin/mount --bind "$scratch_mount/.nixos-usb/docker" "$docker_root"
    printf '%s\n' "$selected_device" > /run/docker-host-scratch.device
    echo "docker-host-scratch: using $selected_device for /var/lib/docker" >&2
  '';

  dockerScratchStop = pkgs.writeShellScript "docker-host-scratch-stop" ''
    set -eu

    docker_root=/var/lib/docker
    scratch_mount=/var/lib/docker-host-scratch

    if ${pkgs.util-linux}/bin/findmnt -rn -M "$docker_root" >/dev/null 2>&1; then
      ${pkgs.util-linux}/bin/umount "$docker_root"
    fi

    if ${pkgs.util-linux}/bin/findmnt -rn -M "$scratch_mount" >/dev/null 2>&1; then
      ${pkgs.util-linux}/bin/umount "$scratch_mount"
    fi

    rm -f /run/docker-host-scratch.device /run/docker-host-scratch.mount.err
  '';
in {
  systemd.tmpfiles.rules = [
    "d /var/lib/docker-host-scratch 0700 root root - -"
  ];

  systemd.services.docker-host-scratch = {
    description = "Prepare host-local scratch storage for Docker on USB boots";
    after = ["local-fs.target"];
    wants = ["local-fs.target"];
    before = ["docker.service"];
    partOf = ["docker.service"];
    requiredBy = ["docker.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = dockerScratchStart;
      ExecStop = dockerScratchStop;
    };
  };

  systemd.services.docker = {
    after = ["docker-host-scratch.service"];
    requires = ["docker-host-scratch.service"];
  };
}
