{pkgs, ...}: let
  userName = "stefan";
  userGroup = "users";
  userHome = "/home/${userName}";
  hostScratchMount = "/nix/.host-scratch";
  hostStoreMount = "/nix/.host-store";
  hostStoreRwMount = "/nix/.host-store-rw";
  nixStoreMount = "/nix/store";
  roStoreMount = "/nix/.ro-store";
  rwStoreMount = "/nix/.rw-store";
  dockerRoot = "/var/lib/docker";
  modeFile = "/run/usb-host-scratch.mode";
  stateDir = "/run/usb-host-scratch";
  scratchMapperName = "nixos-usb-host-scratch";
  scratchMapperDevice = "/dev/mapper/${scratchMapperName}";
  hostSessionRelative = ".nixos-usb/session";
  userRoot = "${hostScratchMount}/user/${userName}";
  repoRoot = "${hostScratchMount}/repositories";

  hostScratchStart = pkgs.writeShellScript "usb-host-scratch-start" ''
    set -eu

    active_root=${hostScratchMount}
    docker_root=${dockerRoot}
    mode_file=${modeFile}
    state_dir=${stateDir}
    user_root=${userRoot}
    repo_root=${repoRoot}

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

    docker_root=${dockerRoot}
    mode_file=${modeFile}
    user_root=${userRoot}
    stop_status=0

    is_mounted() {
      target="$1"
      ${pkgs.util-linux}/bin/findmnt -rn -M "$target" >/dev/null 2>&1
    }

    unmount_for_sync() {
      target="$1"

      if ! is_mounted "$target"; then
        return 0
      fi

      echo "usb-host-scratch: unmounting $target before USB sync" >&2
      if ! ${pkgs.util-linux}/bin/umount "$target"; then
        echo "usb-host-scratch: warning: normal unmount failed for $target; leaving it mounted and skipping sync for this path" >&2
        stop_status=1
        return 1
      fi

      if is_mounted "$target"; then
        echo "usb-host-scratch: warning: $target is still mounted after normal unmount; skipping sync for this path" >&2
        stop_status=1
        return 1
      fi

      return 0
    }

    sync_to_usb() {
      source="$1"
      target="$2"
      if [ -d "$source" ]; then
        echo "usb-host-scratch: syncing $source back to $target" >&2
        ${pkgs.coreutils}/bin/mkdir -p "$target"
        ${pkgs.rsync}/bin/rsync -a --delete "$source/" "$target/"
        ${pkgs.coreutils}/bin/chown -R ${userName}:${userGroup} "$target"
      fi
    }

    unmount_for_sync "$docker_root" || true

    if [ -f "$mode_file" ] && ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$mode_file"; then
      if unmount_for_sync "${userHome}/.config/BraveSoftware"; then
        sync_to_usb "$user_root/brave-config" "${userHome}/.config/BraveSoftware"
      fi
      if unmount_for_sync "${userHome}/.codex"; then
        sync_to_usb "$user_root/codex" "${userHome}/.codex"
      fi
      if unmount_for_sync "${userHome}/.cache"; then
        sync_to_usb "$user_root/cache" "${userHome}/.cache"
      fi
    fi

    if [ "$stop_status" -eq 0 ]; then
      ${pkgs.coreutils}/bin/rm -f "$mode_file"
    else
      echo "usb-host-scratch: warning: stop completed with unsynced mounted paths; keeping $mode_file for shutdown cleanup evidence" >&2
      exit "$stop_status"
    fi
  '';

  shutdownCleanup = pkgs.writeShellScript "usb-host-scratch-shutdown-cleanup" ''
    set -eu

    FINDMNT="''${USB_HOST_SCRATCH_FINDMNT:-${pkgs.util-linux}/bin/findmnt}"
    UMOUNT="''${USB_HOST_SCRATCH_UMOUNT:-${pkgs.util-linux}/bin/umount}"
    CRYPTSETUP="''${USB_HOST_SCRATCH_CRYPTSETUP:-${pkgs.cryptsetup}/bin/cryptsetup}"
    RM="''${USB_HOST_SCRATCH_RM:-${pkgs.coreutils}/bin/rm}"
    CHMOD="''${USB_HOST_SCRATCH_CHMOD:-${pkgs.coreutils}/bin/chmod}"
    SORT="''${USB_HOST_SCRATCH_SORT:-${pkgs.coreutils}/bin/sort}"
    GREP="''${USB_HOST_SCRATCH_GREP:-${pkgs.gnugrep}/bin/grep}"
    MAPPER_NAME="''${USB_HOST_SCRATCH_MAPPER_NAME:-${scratchMapperName}}"
    MAPPER_DEVICE="''${USB_HOST_SCRATCH_MAPPER_DEVICE:-${scratchMapperDevice}}"
    PREFIXES="''${USB_HOST_SCRATCH_PREFIXES:-/oldroot /}"

    log() {
      printf '%s\n' "usb-host-scratch-cleanup: $*" >&2
    }

    path_under_prefix() {
      prefix="$1"
      path="$2"
      if [ "$prefix" = "/" ]; then
        printf '%s\n' "$path"
      else
        printf '%s%s\n' "$prefix" "$path"
      fi
    }

    is_mounted() {
      target="$1"
      "$FINDMNT" -rn -M "$target" >/dev/null 2>&1
    }

    list_mount_tree() {
      target="$1"
      if ! "$FINDMNT" -Rrn --target "$target" -o TARGET 2>/dev/null; then
        if is_mounted "$target"; then
          printf '%s\n' "$target"
        fi
      fi
    }

    unmount_one() {
      target="$1"
      if ! is_mounted "$target"; then
        return 0
      fi

      log "unmounting $target"
      if "$UMOUNT" "$target"; then
        return 0
      fi

      log "normal unmount failed for $target; trying lazy unmount"
      if "$UMOUNT" -l "$target"; then
        return 0
      fi

      log "warning: failed to unmount $target"
      return 1
    }

    unmount_tree() {
      target="$1"
      mounts="$(list_mount_tree "$target" | "$SORT" -r)"
      [ -n "$mounts" ] || return 0

      printf '%s\n' "$mounts" | while IFS= read -r mounted_target; do
        [ -n "$mounted_target" ] || continue
        unmount_one "$mounted_target" || true
      done
    }

    mode_indicates_host_scratch() {
      mode_path="$1"
      [ -f "$mode_path" ] || return 1
      "$GREP" -qx "encrypted-host-scratch" "$mode_path" 2>/dev/null
    }

    store_mode_indicates_host_scratch() {
      mode_path="$1"
      [ -f "$mode_path" ] || return 1
      "$GREP" -qx "writable-encrypted-host-auto-overlay" "$mode_path" 2>/dev/null
    }

    has_host_scratch_evidence() {
      [ -e "$MAPPER_DEVICE" ] && return 0
      mode_indicates_host_scratch "${modeFile}" && return 0
      store_mode_indicates_host_scratch /run/nixos-usb-store-mode && return 0

      for prefix in $PREFIXES; do
        mode_path="$(path_under_prefix "$prefix" ${modeFile})"
        store_mode_path="$(path_under_prefix "$prefix" /run/nixos-usb-store-mode)"
        host_store="$(path_under_prefix "$prefix" ${hostStoreMount})"
        host_scratch="$(path_under_prefix "$prefix" ${hostScratchMount})"
        mode_indicates_host_scratch "$mode_path" && return 0
        store_mode_indicates_host_scratch "$store_mode_path" && return 0
        [ -d "$host_store/${hostSessionRelative}" ] && return 0
        is_mounted "$host_store" && return 0
        is_mounted "$host_scratch" && return 0
      done

      return 1
    }

    cleanup_root() {
      root="$1"
      session_dir="$root/${hostSessionRelative}"
      [ -d "$session_dir" ] || return 0

      log "removing $session_dir"
      if "$RM" -rf "$session_dir"; then
        return 0
      fi

      log "direct removal failed for $session_dir; retrying after chmod"
      "$CHMOD" -R u+w "$session_dir" 2>/dev/null || true
      "$RM" -rf "$session_dir" || log "warning: failed to remove $session_dir"
    }

    if ! has_host_scratch_evidence; then
      log "no encrypted host scratch evidence found; nothing to clean"
      exit 0
    fi

    for prefix in $PREFIXES; do
      unmount_tree "$(path_under_prefix "$prefix" ${nixStoreMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${rwStoreMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${roStoreMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${hostStoreRwMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${hostScratchMount})"
    done

    if [ -e "$MAPPER_DEVICE" ]; then
      log "closing $MAPPER_NAME"
      "$CRYPTSETUP" close "$MAPPER_NAME" || log "warning: failed to close $MAPPER_NAME"
    fi

    for prefix in $PREFIXES; do
      cleanup_root "$(path_under_prefix "$prefix" ${hostStoreMount})"
    done

    for prefix in $PREFIXES; do
      unmount_tree "$(path_under_prefix "$prefix" ${hostStoreMount})"
    done
  '';
in {
  systemd.tmpfiles.rules = [
    "d /var/lib/docker 0700 root root - -"
    "d /run/usb-host-scratch 0700 root root - -"
  ];

  systemd.services.usb-host-scratch = {
    description = "USB encrypted host scratch storage";
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
  systemd.shutdownRamfs.storePaths = [
    "${pkgs.util-linux}/bin"
    "${pkgs.cryptsetup}/bin"
    "${pkgs.gnugrep}/bin"
  ];

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
      print_mount ${hostStoreMount}
      print_mount ${hostScratchMount}
      print_mount ${dockerRoot}
      print_mount ${userHome}/.cache
      print_mount ${userHome}/.codex
      print_mount ${userHome}/.config/BraveSoftware
      printf '\n'

      if [ -d ${repoRoot} ]; then
        printf '== repositories ==\n'
        printf '%s\n\n' ${repoRoot}
      fi

      if ${pkgs.systemd}/bin/journalctl --version >/dev/null 2>&1; then
        printf '== services ==\n'
        ${pkgs.systemd}/bin/journalctl -b -u usb-host-scratch.service --no-pager -n 60 || true
      fi
    '')
  ];
}
