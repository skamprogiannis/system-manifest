{pkgs}:
pkgs.writeShellScriptBin "steam-host-scratch" ''
    set -eu

    mode_file="''${STEAM_HOST_SCRATCH_MODE_FILE:-/run/usb-host-scratch.mode}"
    steam_dir="''${STEAM_HOST_SCRATCH_STEAM_DIR:-/nix/.host-scratch/user/stefan/steam/Steam}"
    persistent_steam_dir="''${STEAM_HOST_SCRATCH_PERSISTENT_DIR:-$HOME/.local/share/Steam}"
    PGREP="''${STEAM_HOST_SCRATCH_PGREP:-${pkgs.procps}/bin/pgrep}"
    ID="''${STEAM_HOST_SCRATCH_ID:-${pkgs.coreutils}/bin/id}"

    usage() {
      ${pkgs.coreutils}/bin/cat <<'USAGE'
  Usage: steam-host-scratch [prepare|path|checkpoint|status]

  Commands:
    prepare     Create and report the temporary host-SSD Steam data root.
    path        Create the data root and print only its path.
    checkpoint  Persist account/config/userdata after Steam has exited.
    status      Report whether the encrypted host-scratch Steam root is available.
  USAGE
    }

    host_scratch_active() {
      [ -f "$mode_file" ] &&
        ${pkgs.gnugrep}/bin/grep -qx "encrypted-host-scratch" "$mode_file"
    }

    require_host_scratch() {
      if ! host_scratch_active; then
        echo "steam-host-scratch: encrypted host scratch is not active; boot the host-auto-store specialisation" >&2
        exit 1
      fi
    }

    prepare_steam_dir() {
      require_host_scratch
      ${pkgs.coreutils}/bin/mkdir -p -- "$steam_dir"
    }

    sync_persistent_state() {
      if "$PGREP" -u "$("$ID" -u)" -x steam >/dev/null 2>&1; then
        echo "steam-host-scratch: exit Steam before checkpointing its state" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/mkdir -p -- "$persistent_steam_dir"
      for state_dir in config userdata; do
        if [ -d "$steam_dir/$state_dir" ]; then
          ${pkgs.coreutils}/bin/mkdir -p "$persistent_steam_dir/$state_dir"
          ${pkgs.rsync}/bin/rsync -a \
            "$steam_dir/$state_dir/" \
            "$persistent_steam_dir/$state_dir/"
        fi
      done
      ${pkgs.rsync}/bin/rsync -a \
        --include='ssfn*' \
        --exclude='*' \
        "$steam_dir/" \
        "$persistent_steam_dir/"
    }

    cmd="''${1:-prepare}"
    if [ "$#" -gt 1 ]; then
      usage >&2
      exit 2
    fi

    case "$cmd" in
      prepare|setup)
        prepare_steam_dir
        printf 'Steam client and default library: %s\n' "$steam_dir"
        printf '%s\n' "Launch Steam normally; host-auto redirects its mutable client and default steamapps library automatically."
        printf '%s\n' "Client and game data in this directory are temporary and will be erased during shutdown."
        printf '%s\n' "Exit games and wait for Steam Cloud to report Up to date before shutting down."
        ;;
      path)
        prepare_steam_dir
        printf '%s\n' "$steam_dir"
        ;;
      checkpoint)
        prepare_steam_dir
        sync_persistent_state
        printf '%s\n' "Steam account, config, and userdata checkpointed to persistent USB home."
        ;;
      status)
        if host_scratch_active; then
          printf '%s\n' "Steam host-scratch: active"
          printf 'Client and default library: %s\n' "$steam_dir"
          if [ -d "$steam_dir" ]; then
            printf '%s\n' "State: ready"
          else
            printf '%s\n' "State: not prepared"
          fi
          printf '%s\n' "Durability: temporary; erased during shutdown"
        else
          printf '%s\n' "Steam host-scratch: inactive"
          printf '%s\n' "Boot the host-auto-store specialisation to use the temporary SSD library."
        fi
        ;;
      -h|--help|help)
        usage
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
''
