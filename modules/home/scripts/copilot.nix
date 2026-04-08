{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "copilot-sessions-sync" ''
      set -euo pipefail
      MODE="''${1:-to-usb}"
      SYNC_USER="''${SUDO_USER:-''${USER:-$(${pkgs.coreutils}/bin/id -un)}}"
      SYNC_GROUP="$(${pkgs.coreutils}/bin/id -gn "$SYNC_USER")"
      USER_HOME="$(${pkgs.gawk}/bin/awk -F: -v user="$SYNC_USER" '$1 == user { print $6; exit }' /etc/passwd)"
      LUKS_DEVICE="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
      PREFERRED_MAPPER="NIXOS_USB_CRYPT"
      MAPPER="$PREFERRED_MAPPER"
      MAPPER_DEV="/dev/mapper/$MAPPER"
      MOUNT="/mnt/usb-sync"
      LOCAL="$USER_HOME/.copilot/session-state"
      REMOTE="$MOUNT$USER_HOME/.copilot/session-state"
      OPENED_MAPPER=0
      MOUNTED=0

      run_root() {
        if [ "$EUID" -eq 0 ]; then
          "$@"
        else
          sudo "$@"
        fi
      }

      refresh_mapper() {
        local existing_mapper=""
        existing_mapper=$(${pkgs.util-linux}/bin/lsblk -nrpo NAME,TYPE "$LUKS_DEVICE" 2>/dev/null | ${pkgs.gnused}/bin/sed -n '/ crypt$/ { s/ crypt$//; p; q; }')
        if [ -n "$existing_mapper" ]; then
          MAPPER_DEV="$existing_mapper"
          MAPPER="''${existing_mapper##*/}"
        else
          MAPPER="$PREFERRED_MAPPER"
          MAPPER_DEV="/dev/mapper/$MAPPER"
        fi
      }

      cleanup() {
        local rc=$?
        trap - EXIT INT TERM

        if [ "$MOUNTED" -eq 1 ] && run_root ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT"; then
          run_root ${pkgs.util-linux}/bin/umount -R "$MOUNT" 2>/dev/null || true
          MOUNTED=0
        fi

        if [ "$OPENED_MAPPER" -eq 1 ]; then
          sync
          for _ in 1 2 3; do
            if run_root ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER" 2>/dev/null; then
              OPENED_MAPPER=0
              break
            fi
            sleep 1
          done

          if [ "$OPENED_MAPPER" -eq 1 ]; then
            echo "Warning: failed to close $MAPPER; close it manually with: sudo cryptsetup luksClose $MAPPER" >&2
            if [ "$rc" -eq 0 ]; then
              rc=1
            fi
          fi
        fi

        exit "$rc"
      }

      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      if [ -z "$USER_HOME" ]; then
        echo "Unable to resolve a home directory for $SYNC_USER."
        exit 1
      fi

      if [ ! -e "$LUKS_DEVICE" ]; then
        echo "USB not found. Plug in the USB drive and try again."
        exit 1
      fi

      refresh_mapper
      if [ ! -e "$MAPPER_DEV" ]; then
        run_root ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$LUKS_DEVICE" "$PREFERRED_MAPPER"
        OPENED_MAPPER=1
        refresh_mapper
      elif ! ${pkgs.util-linux}/bin/findmnt -rn -S "$MAPPER_DEV" >/dev/null 2>&1; then
        OPENED_MAPPER=1
      fi

      run_root mkdir -p "$MOUNT"
      if run_root ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT"; then
        run_root ${pkgs.util-linux}/bin/umount -R "$MOUNT"
      fi
      run_root mount "$MAPPER_DEV" "$MOUNT"
      MOUNTED=1
      run_root mkdir -p "$USER_HOME/.copilot" "$LOCAL" "$MOUNT$USER_HOME/.copilot" "$REMOTE"
      run_root chown "$SYNC_USER:$SYNC_GROUP" "$USER_HOME/.copilot" "$LOCAL" "$MOUNT$USER_HOME/.copilot" "$REMOTE"

      case "$MODE" in
        to-usb)
          echo "Syncing desktop → USB..."
          run_root ${pkgs.rsync}/bin/rsync -av --update --chown="$SYNC_USER:$SYNC_GROUP" "$LOCAL/" "$REMOTE/"
          ;;
        from-usb)
          echo "Syncing USB → desktop..."
          run_root ${pkgs.rsync}/bin/rsync -av --update --chown="$SYNC_USER:$SYNC_GROUP" "$REMOTE/" "$LOCAL/"
          ;;
        *)
          echo "Usage: copilot-sessions-sync [to-usb|from-usb]"
          exit 1
          ;;
      esac

      echo "Done."
    '')
  ];
}
