{pkgs, ...}: let
  userName = "stefan";
  userGroup = "users";
  userHome = "/home/${userName}";

  hostScratchStart = pkgs.writeShellScript "usb-host-scratch-start" ''
    set -eu

    active_root=/nix/.host-scratch
    docker_root=/var/lib/docker
    mode_file=/run/usb-host-scratch.mode
    state_dir=/run/usb-host-scratch
    user_root="$active_root/user/${userName}"
    repo_root="$active_root/repositories"

    ${pkgs.coreutils}/bin/mkdir -p "$state_dir" "$docker_root"
    ${pkgs.coreutils}/bin/rm -f "$mode_file"

    bind_mount() {
      source="$1"
      target="$2"
      ${pkgs.coreutils}/bin/mkdir -p "$source" "$target"
      if ${pkgs.util-linux}/bin/findmnt -rn -M "$target" >/dev/null 2>&1; then
        return 0
      fi
      ${pkgs.util-linux}/bin/mount --bind "$source" "$target"
    }

    sync_to_scratch() {
      source="$1"
      target="$2"
      ${pkgs.coreutils}/bin/mkdir -p "$source" "$target"
      ${pkgs.rsync}/bin/rsync -a --delete "$source/" "$target/"
    }

    if ! ${pkgs.util-linux}/bin/findmnt -rn -M "$active_root" >/dev/null 2>&1; then
      echo "usb-host-scratch: encrypted host scratch is unavailable; leaving user cache on USB and using tmpfs for Docker" >&2
      if ! ${pkgs.util-linux}/bin/findmnt -rn -M "$docker_root" >/dev/null 2>&1; then
        ${pkgs.util-linux}/bin/mount -t tmpfs -o size=35%,mode=700 tmpfs "$docker_root"
      fi
      printf '%s\n' "inactive-tmpfs-docker" > "$mode_file"
      exit 0
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$user_root/cache" "$user_root/codex" "$user_root/brave-config" "$repo_root" "$active_root/docker"
    ${pkgs.coreutils}/bin/chown -R ${userName}:${userGroup} "$user_root" "$repo_root"
    ${pkgs.coreutils}/bin/chmod 700 "$user_root" "$repo_root" "$active_root/docker"

    sync_to_scratch "${userHome}/.cache" "$user_root/cache"
    sync_to_scratch "${userHome}/.codex" "$user_root/codex"
    sync_to_scratch "${userHome}/.config/BraveSoftware" "$user_root/brave-config"

    bind_mount "$user_root/cache" "${userHome}/.cache"
    bind_mount "$user_root/codex" "${userHome}/.codex"
    bind_mount "$user_root/brave-config" "${userHome}/.config/BraveSoftware"
    bind_mount "$active_root/docker" "$docker_root"

    printf '%s\n' "encrypted-host-scratch" > "$mode_file"
    echo "usb-host-scratch: using encrypted host scratch at $active_root" >&2
  '';

  hostScratchStop = pkgs.writeShellScript "usb-host-scratch-stop" ''
    set -eu

    active_root=/nix/.host-scratch
    docker_root=/var/lib/docker
    mode_file=/run/usb-host-scratch.mode
    user_root="$active_root/user/${userName}"

    unmount_if_mounted() {
      target="$1"
      if ${pkgs.util-linux}/bin/findmnt -rn -M "$target" >/dev/null 2>&1; then
        ${pkgs.util-linux}/bin/umount "$target"
      fi
    }

    sync_to_usb() {
      source="$1"
      target="$2"
      if [ -d "$source" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$target"
        ${pkgs.rsync}/bin/rsync -a --delete "$source/" "$target/"
        ${pkgs.coreutils}/bin/chown -R ${userName}:${userGroup} "$target"
      fi
    }

    unmount_if_mounted "$docker_root"

    if [ -f "$mode_file" ] && ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$mode_file"; then
      unmount_if_mounted "${userHome}/.config/BraveSoftware"
      unmount_if_mounted "${userHome}/.codex"
      unmount_if_mounted "${userHome}/.cache"

      sync_to_usb "$user_root/cache" "${userHome}/.cache"
      sync_to_usb "$user_root/codex" "${userHome}/.codex"
      sync_to_usb "$user_root/brave-config" "${userHome}/.config/BraveSoftware"
    fi

    ${pkgs.coreutils}/bin/rm -f "$mode_file"
  '';

  shutdownCleanup = pkgs.writeShellScript "usb-host-scratch-shutdown-cleanup" ''
    set -eu

    cleanup_root() {
      root="$1"
      [ -d "$root/.nixos-usb/session" ] || return 0
      /bin/chmod -R u+w "$root/.nixos-usb/session" 2>/dev/null || true
      /bin/rm -rf "$root/.nixos-usb/session"
    }

    cleanup_root /oldroot/nix/.host-store
    cleanup_root /nix/.host-store
  '';
in {
  systemd.tmpfiles.rules = [
    "d /var/lib/docker 0700 root root - -"
    "d /run/usb-host-scratch 0700 root root - -"
  ];

  systemd.services.usb-host-scratch = {
    description = "Prepare encrypted host-local scratch storage for USB boots";
    after = ["local-fs.target"];
    wants = ["local-fs.target"];
    before = [
      "display-manager.service"
      "docker.service"
    ];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = hostScratchStart;
      ExecStop = hostScratchStop;
      TimeoutStartSec = "10min";
      TimeoutStopSec = "15min";
    };
  };

  systemd.services.docker = {
    after = ["usb-host-scratch.service"];
    requires = ["usb-host-scratch.service"];
  };

  systemd.shutdownRamfs.contents."/lib/systemd/system-shutdown/usb-host-scratch-cleanup".source = shutdownCleanup;

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nixos-usb-host-scratch-status" ''
      set -eu

      print_file() {
        label="$1"
        path="$2"
        printf '== %s ==\n' "$label"
        if [ -e "$path" ]; then
          ${pkgs.coreutils}/bin/cat "$path"
        else
          printf 'missing: %s\n' "$path"
        fi
        printf '\n'
      }

      print_mount() {
        path="$1"
        if ${pkgs.util-linux}/bin/findmnt -rn -M "$path" >/dev/null 2>&1; then
          ${pkgs.util-linux}/bin/findmnt -M "$path"
        else
          printf 'not mounted: %s\n' "$path"
        fi
      }

      print_file "scratch mode" /run/usb-host-scratch.mode

      printf '== mounts ==\n'
      print_mount /nix/.host-store
      print_mount /nix/.host-scratch
      print_mount /var/lib/docker
      print_mount ${userHome}/.cache
      print_mount ${userHome}/.codex
      print_mount ${userHome}/.config/BraveSoftware
      printf '\n'

      if [ -d /nix/.host-scratch/repositories ]; then
        printf '== repositories ==\n'
        printf '%s\n\n' /nix/.host-scratch/repositories
      fi

      if ${pkgs.systemd}/bin/journalctl --version >/dev/null 2>&1; then
        printf '== services ==\n'
        ${pkgs.systemd}/bin/journalctl -b -u usb-host-scratch.service --no-pager -n 60 || true
      fi
    '')
  ];
}
