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
  steamLibrary = "${userHome}/games/SteamLibrary";
  usbHomeBacking = "${stateDir}/usb-home";
  lastSyncState = "${userHome}/.local/state/system-manifest/host-scratch-last-sync";
  lastCleanupState = "${userHome}/.local/state/system-manifest/host-scratch-last-cleanup";

  hostScratchSync = pkgs.writeShellScript "usb-host-scratch-sync" ''
    set -eu

    reason="''${1:-checkpoint}"
    scope=essential
    case "$reason" in
      checkpoint|shutdown)
        ;;
      *)
        echo "usb-host-scratch-sync: unsupported reason: $reason" >&2
        exit 2
        ;;
    esac
    shift || true
    case "''${1:-}" in
      "")
        ;;
      --include-cache)
        if [ "$reason" = shutdown ]; then
          echo "usb-host-scratch-sync: shutdown does not permit the unbounded cache scope" >&2
          exit 2
        fi
        scope=include-cache
        shift
        ;;
      *)
        echo "usb-host-scratch-sync: unsupported option: $1" >&2
        exit 2
        ;;
    esac
    if [ "$#" -ne 0 ]; then
      echo "usb-host-scratch-sync: unexpected arguments" >&2
      exit 2
    fi

    MODE_FILE="''${USB_HOST_SCRATCH_MODE_FILE:-${modeFile}}"
    STATE_DIR="''${USB_HOST_SCRATCH_STATE_DIR:-${stateDir}}"
    ATTEMPT_STATE="''${USB_HOST_SCRATCH_ATTEMPT_STATE:-/run/usb-host-scratch-last-sync}"
    USB_HOME="''${USB_HOST_SCRATCH_USB_HOME:-${usbHomeBacking}}"
    USER_ROOT="''${USB_HOST_SCRATCH_USER_ROOT:-${userRoot}}"
    LAST_SYNC_STATE="''${USB_HOST_SCRATCH_LAST_SYNC_STATE:-$USB_HOME/.local/state/system-manifest/host-scratch-last-sync}"
    FINDMNT="''${USB_HOST_SCRATCH_FINDMNT:-${pkgs.util-linux}/bin/findmnt}"
    FLOCK="''${USB_HOST_SCRATCH_FLOCK:-${pkgs.util-linux}/bin/flock}"
    RSYNC="''${USB_HOST_SCRATCH_RSYNC:-${pkgs.rsync}/bin/rsync}"
    MKDIR="''${USB_HOST_SCRATCH_MKDIR:-${pkgs.coreutils}/bin/mkdir}"
    MV="''${USB_HOST_SCRATCH_MV:-${pkgs.coreutils}/bin/mv}"
    CHOWN="''${USB_HOST_SCRATCH_CHOWN:-${pkgs.coreutils}/bin/chown}"
    CHMOD="''${USB_HOST_SCRATCH_CHMOD:-${pkgs.coreutils}/bin/chmod}"
    DATE="''${USB_HOST_SCRATCH_DATE:-${pkgs.coreutils}/bin/date}"
    SYNC="''${USB_HOST_SCRATCH_SYNC:-${pkgs.coreutils}/bin/sync}"

    "$MKDIR" -p "$STATE_DIR"
    phase=locking

    write_record() {
      target="$1"
      result="$2"
      timestamp="$("$DATE" -u +%Y-%m-%dT%H:%M:%SZ)"
      "$MKDIR" -p "''${target%/*}"
      {
        printf 'timestamp=%s\n' "$timestamp"
        printf 'reason=%s\n' "$reason"
        printf 'scope=%s\n' "$scope"
        printf 'phase=%s\n' "$phase"
        printf 'result=%s\n' "$result"
        if [ "$scope" = include-cache ]; then
          printf 'targets=%s\n' "codex,brave,cache"
          printf 'excluded=%s\n' "docker,repositories,steam-library,volatile-codex,volatile-brave"
        else
          printf 'targets=%s\n' "codex,brave"
          printf 'excluded=%s\n' "cache,docker,repositories,steam-library,volatile-codex,volatile-brave"
        fi
      } > "$target.tmp"
      "$MV" "$target.tmp" "$target"
    }

    record_failure() {
      status="$?"
      trap - EXIT
      write_record "$ATTEMPT_STATE" failed || true
      "$CHMOD" 0644 "$ATTEMPT_STATE" 2>/dev/null || true
      echo "usb-host-scratch-sync: $reason failed; USB state may be stale" >&2
      exit "$status"
    }
    trap record_failure EXIT
    write_record "$ATTEMPT_STATE" running
    "$CHMOD" 0644 "$ATTEMPT_STATE"

    exec 9>"$STATE_DIR/sync.lock"
    "$FLOCK" -x 9
    phase=validating
    write_record "$ATTEMPT_STATE" running
    "$CHMOD" 0644 "$ATTEMPT_STATE"

    if [ ! -f "$MODE_FILE" ] || ! ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$MODE_FILE"; then
      echo "usb-host-scratch-sync: encrypted host scratch is not active" >&2
      exit 1
    fi
    if ! "$FINDMNT" -rn -M "$USB_HOME" >/dev/null 2>&1; then
      echo "usb-host-scratch-sync: underlying USB home bind is unavailable: $USB_HOME" >&2
      exit 1
    fi

    ensure_user_dir() {
      target="$1"
      "$MKDIR" -p "$target"
      "$CHOWN" ${userName}:${userGroup} "$target"
      "$CHMOD" u+rwx "$target"
    }

    sync_one() {
      label="$1"
      source="$2"
      target="$3"
      shift 3
      if [ ! -d "$source" ]; then
        echo "usb-host-scratch-sync: missing $label source: $source" >&2
        return 1
      fi
      echo "usb-host-scratch-sync: syncing $label to USB" >&2
      ensure_user_dir "$target"
      "$RSYNC" -a --delete "$@" "$source/" "$target/"
    }

    phase=codex
    write_record "$ATTEMPT_STATE" running
    sync_one codex "$USER_ROOT/codex" "$USB_HOME/.codex" \
      --exclude=/auth.json \
      --exclude=/config.toml \
      --exclude=/AGENTS.md \
      --exclude=/skills/ \
      --exclude=/agents/ \
      --exclude=/cache/ \
      --exclude=/log/ \
      --exclude=/logs/ \
      --exclude=/.tmp/ \
      '--exclude=/logs*.sqlite*' \
      --exclude=/models_cache.json \
      --exclude=/version.json \
      --exclude=/installation_id \
      '--exclude=*/files/alt-nix-store/***' \
      --exclude=/plugins/cache/
    ensure_user_dir "$USB_HOME/.config"
    phase=brave
    write_record "$ATTEMPT_STATE" running
    sync_one brave "$USER_ROOT/brave-config" "$USB_HOME/.config/BraveSoftware" \
      --delete-excluded \
      '--exclude=/**/Cache/***' \
      '--exclude=/**/Code Cache/***' \
      '--exclude=/**/GPUCache/***' \
      '--exclude=/**/DawnCache/***' \
      '--exclude=/**/DawnGraphiteCache/***' \
      '--exclude=/**/DawnWebGPUCache/***' \
      '--exclude=/**/GPUPersistentCache/***' \
      '--exclude=/**/GraphiteDawnCache/***' \
      '--exclude=/**/GrShaderCache/***' \
      '--exclude=/**/ShaderCache/***' \
      '--exclude=/**/Service Worker/CacheStorage/***' \
      '--exclude=/**/Service Worker/ScriptCache/***' \
      '--exclude=/Crash Reports/***' \
      '--exclude=/Crashpad/***' \
      '--exclude=/component_crx_cache/***' \
      '--exclude=/extensions_crx_cache/***'
    if [ "$scope" = include-cache ]; then
      phase=cache
      write_record "$ATTEMPT_STATE" running
      sync_one cache "$USER_ROOT/cache" "$USB_HOME/.cache"
    fi

    for state_path in "$USB_HOME/.local" "$USB_HOME/.local/state" "$USB_HOME/.local/state/system-manifest"; do
      ensure_user_dir "$state_path"
    done
    phase=flushing
    write_record "$ATTEMPT_STATE" running
    "$SYNC" -f "$USB_HOME"
    phase=complete
    write_record "$ATTEMPT_STATE" success
    "$CHMOD" 0644 "$ATTEMPT_STATE"
    write_record "$LAST_SYNC_STATE" success
    "$CHOWN" ${userName}:${userGroup} "$LAST_SYNC_STATE"
    "$SYNC" -f "$USB_HOME"
    trap - EXIT
    echo "usb-host-scratch-sync: $reason complete; essential Codex and Brave state is durable on USB" >&2
    if [ "$scope" = include-cache ]; then
      echo "usb-host-scratch-sync: full user cache is also durable on USB" >&2
    else
      echo "usb-host-scratch-sync: full user cache was skipped; use checkpoint --include-cache for the slow scope" >&2
    fi
    echo "usb-host-scratch-sync: Docker state, repositories, and the Steam library remain temporary and are not copied" >&2
  '';

  hostScratchStart = pkgs.writeShellScript "usb-host-scratch-start" ''
    set -eu

    active_root=${hostScratchMount}
    docker_root=${dockerRoot}
    mode_file=${modeFile}
    state_dir=${stateDir}
    user_root=${userRoot}
    repo_root=${repoRoot}
    usb_home=${usbHomeBacking}

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

    ${pkgs.coreutils}/bin/mkdir -p "$user_root/cache" "$user_root/codex" "$user_root/brave-config" "$user_root/steam-library" "$repo_root" "$active_root/docker"
    ${pkgs.coreutils}/bin/chown -R ${userName}:${userGroup} "$user_root" "$repo_root"
    ${pkgs.coreutils}/bin/chmod 700 "$user_root" "$repo_root" "$active_root/docker"

    sync_to_scratch "${userHome}/.cache" "$user_root/cache"
    sync_to_scratch "${userHome}/.codex" "$user_root/codex"
    sync_to_scratch "${userHome}/.config/BraveSoftware" "$user_root/brave-config"

    bind_mount "${userHome}" "$usb_home"
    ${pkgs.util-linux}/bin/mount --make-private "$usb_home"
    bind_mount "$user_root/steam-library" "${steamLibrary}"
    bind_mount "$user_root/cache" "${userHome}/.cache"
    bind_mount "$user_root/codex" "${userHome}/.codex"
    bind_mount "$user_root/brave-config" "${userHome}/.config/BraveSoftware"
    bind_mount "$active_root/docker" "$docker_root"

    printf '%s\n' "encrypted-host-scratch" > "$mode_file"
    echo "usb-host-scratch: using encrypted host scratch at $active_root" >&2
  '';

  hostScratchStop = pkgs.writeShellScript "usb-host-scratch-stop" ''
    set -u

    docker_root="''${USB_HOST_SCRATCH_DOCKER_ROOT:-${dockerRoot}}"
    mode_file="''${USB_HOST_SCRATCH_MODE_FILE:-${modeFile}}"
    usb_home="''${USB_HOST_SCRATCH_USB_HOME:-${usbHomeBacking}}"
    FINDMNT="''${USB_HOST_SCRATCH_FINDMNT:-${pkgs.util-linux}/bin/findmnt}"
    UMOUNT="''${USB_HOST_SCRATCH_UMOUNT:-${pkgs.util-linux}/bin/umount}"
    SYNC_HELPER="''${USB_HOST_SCRATCH_SYNC_HELPER:-${hostScratchSync}}"
    TIMEOUT="''${USB_HOST_SCRATCH_TIMEOUT:-${pkgs.coreutils}/bin/timeout}"
    RM="''${USB_HOST_SCRATCH_RM:-${pkgs.coreutils}/bin/rm}"
    GREP="''${USB_HOST_SCRATCH_GREP:-${pkgs.gnugrep}/bin/grep}"
    shutdown_budget="''${USB_HOST_SCRATCH_SHUTDOWN_BUDGET_SECONDS:-50}"
    kill_grace="''${USB_HOST_SCRATCH_KILL_GRACE_SECONDS:-5}"
    stop_status=0
    cleanup_ran=0

    is_mounted() {
      target="$1"
      "$FINDMNT" -rn -M "$target" >/dev/null 2>&1
    }

    unmount_target() {
      target="$1"

      if ! is_mounted "$target"; then
        return 0
      fi

      echo "usb-host-scratch: unmounting $target" >&2
      if ! "$UMOUNT" "$target"; then
        echo "usb-host-scratch: warning: normal unmount failed for $target" >&2
        stop_status=1
        return 1
      fi

      if is_mounted "$target"; then
        echo "usb-host-scratch: warning: $target is still mounted after normal unmount" >&2
        stop_status=1
        return 1
      fi

      return 0
    }

    cleanup() {
      [ "$cleanup_ran" -eq 0 ] || return 0
      cleanup_ran=1
      unmount_target "$docker_root" || true
      unmount_target "${steamLibrary}" || true
      unmount_target "${userHome}/.config/BraveSoftware" || true
      unmount_target "${userHome}/.codex" || true
      unmount_target "${userHome}/.cache" || true
      unmount_target "$usb_home" || true
    }
    on_exit() {
      cleanup
    }
    on_signal() {
      stop_status=1
      exit 1
    }
    trap on_exit EXIT
    trap on_signal HUP INT TERM

    if [ -f "$mode_file" ] && "$GREP" -qx "encrypted-host-scratch" "$mode_file"; then
      unmount_target "$docker_root" || true
      unmount_target "${steamLibrary}" || true
      unmount_target "${userHome}/.config/BraveSoftware" || true
      unmount_target "${userHome}/.codex" || true
      unmount_target "${userHome}/.cache" || true

      if ! "$TIMEOUT" --signal=TERM --kill-after="$kill_grace" "$shutdown_budget" "$SYNC_HELPER" shutdown; then
        echo "usb-host-scratch: shutdown sync failed; keeping failure evidence for status and cleanup" >&2
        stop_status=1
      fi
    fi

    cleanup
    trap - EXIT HUP INT TERM

    if [ "$stop_status" -eq 0 ]; then
      "$RM" -f "$mode_file"
    else
      echo "usb-host-scratch: warning: stop completed with sync or unmount failures; keeping $mode_file for shutdown cleanup evidence" >&2
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
    CLEANUP_STATE_RELATIVE="''${USB_HOST_SCRATCH_CLEANUP_STATE_RELATIVE:-${lastCleanupState}}"
    DATE="''${USB_HOST_SCRATCH_DATE:-${pkgs.coreutils}/bin/date}"
    MKDIR="''${USB_HOST_SCRATCH_MKDIR:-${pkgs.coreutils}/bin/mkdir}"
    MV="''${USB_HOST_SCRATCH_MV:-${pkgs.coreutils}/bin/mv}"
    cleanup_status=success

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
      cleanup_status=failed
      return 1
    }

    unmount_tree() {
      target="$1"
      mounts="$(list_mount_tree "$target" | "$SORT" -r)"
      [ -n "$mounts" ] || return 0

      for mounted_target in $mounts; do
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
      if ! "$RM" -rf "$session_dir"; then
        cleanup_status=failed
        log "warning: failed to remove $session_dir"
      fi
    }

    write_cleanup_record() {
      prefix="$1"
      target="$(path_under_prefix "$prefix" "$CLEANUP_STATE_RELATIVE")"
      parent="''${target%/*}"
      [ -d "$(path_under_prefix "$prefix" ${userHome})" ] || return 0
      "$MKDIR" -p "$parent" || return 0
      {
        printf 'timestamp=%s\n' "$("$DATE" -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'result=%s\n' "$cleanup_status"
        printf 'phase=%s\n' complete
        printf 'scope=%s\n' late-shutdown
      } > "$target.tmp"
      "$MV" "$target.tmp" "$target"
    }

    if ! has_host_scratch_evidence; then
      log "no encrypted host scratch evidence found; nothing to clean"
      exit 0
    fi

    for prefix in $PREFIXES; do
      unmount_tree "$(path_under_prefix "$prefix" ${dockerRoot})"
      unmount_tree "$(path_under_prefix "$prefix" ${steamLibrary})"
      unmount_tree "$(path_under_prefix "$prefix" ${userHome}/.config/BraveSoftware)"
      unmount_tree "$(path_under_prefix "$prefix" ${userHome}/.codex)"
      unmount_tree "$(path_under_prefix "$prefix" ${userHome}/.cache)"
      unmount_tree "$(path_under_prefix "$prefix" ${usbHomeBacking})"
      unmount_tree "$(path_under_prefix "$prefix" ${nixStoreMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${rwStoreMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${roStoreMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${hostStoreRwMount})"
      unmount_tree "$(path_under_prefix "$prefix" ${hostScratchMount})"
    done

    if [ -e "$MAPPER_DEVICE" ]; then
      log "closing $MAPPER_NAME"
      if ! "$CRYPTSETUP" close "$MAPPER_NAME"; then
        cleanup_status=failed
        log "warning: failed to close $MAPPER_NAME"
      fi
    fi

    for prefix in $PREFIXES; do
      cleanup_root "$(path_under_prefix "$prefix" ${hostStoreMount})"
    done

    for prefix in $PREFIXES; do
      unmount_tree "$(path_under_prefix "$prefix" ${hostStoreMount})"
    done

    for prefix in $PREFIXES; do
      write_cleanup_record "$prefix"
    done
  '';
in {
  systemd.tmpfiles.rules = [
    "d /var/lib/docker 0700 root root - -"
    "d /run/usb-host-scratch 0700 root root - -"
  ];

  # These mounts are created dynamically in the initrd. Leave them mounted
  # through umount.target so the shutdown-ramfs hook can close the scratch
  # mapper between unmounting the scratch filesystem and its host backing.
  systemd.units = {
    "nix-.host-scratch.mount" = {
      overrideStrategy = "asDropin";
      text = ''
        [Unit]
        DefaultDependencies=no
      '';
    };
    "nix-.host-store.mount" = {
      overrideStrategy = "asDropin";
      text = ''
        [Unit]
        DefaultDependencies=no
      '';
    };
  };

  systemd.services.usb-host-scratch = {
    description = "USB encrypted host scratch storage";
    after = ["local-fs.target"];
    wants = ["local-fs.target"];
    before = [
      "display-manager.service"
      "docker.service"
      "user@1000.service"
    ];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = hostScratchStart;
      ExecStop = hostScratchStop;
      TimeoutStartSec = "10min";
      TimeoutStopSec = "60s";
    };
  };

  systemd.services.usb-host-scratch-checkpoint = {
    description = "Checkpoint USB host scratch state to persistent USB storage";
    after = ["usb-host-scratch.service"];
    requires = ["usb-host-scratch.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${hostScratchSync} checkpoint";
      TimeoutStartSec = "15min";
    };
  };

  systemd.services.usb-host-scratch-checkpoint-cache = {
    description = "Checkpoint USB host scratch state and full cache to persistent USB storage";
    after = ["usb-host-scratch.service"];
    requires = ["usb-host-scratch.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${hostScratchSync} checkpoint --include-cache";
      TimeoutStartSec = "infinity";
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
      print_file "last sync attempt" /run/usb-host-scratch-last-sync
      print_file "last successful sync" ${lastSyncState}
      print_file "previous late cleanup" ${lastCleanupState}

      printf '== mounts ==\n'
      print_mount ${hostStoreMount}
      print_mount ${hostScratchMount}
      print_mount ${usbHomeBacking}
      print_mount ${dockerRoot}
      print_mount ${steamLibrary}
      print_mount ${userHome}/.cache
      print_mount ${userHome}/.codex
      print_mount ${userHome}/.config/BraveSoftware
      printf '\n'

      if [ -d ${repoRoot} ]; then
        printf '== repositories ==\n'
        printf '%s\n\n' ${repoRoot}
      fi

      printf '== durability ==\n'
      printf '%s\n' "Automatic and default checkpoints persist essential Codex and Brave state."
      printf '%s\n' "Use usb-host-scratch checkpoint --include-cache to persist the full user cache explicitly."
      printf '%s\n\n' "Docker state, repositories, and the Steam library are temporary and are not copied to USB."

      if ${pkgs.systemd}/bin/journalctl --version >/dev/null 2>&1; then
        printf '== services ==\n'
        ${pkgs.systemd}/bin/journalctl -b -u usb-host-scratch.service -u usb-host-scratch-checkpoint.service -u usb-host-scratch-checkpoint-cache.service --no-pager -n 80 || true
      fi
    '')
  ];
}
