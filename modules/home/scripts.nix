{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "setup-persistent-usb" ''
      exec ${pkgs.bash}/bin/bash ${./scripts/setup_persistent_usb.sh} "$@"
    '')
    (pkgs.writeShellScriptBin "update-usb" ''
      exec ${pkgs.bash}/bin/bash ${./scripts/update_usb.sh} "$@"
    '')
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "copilot-sessions-sync" ''
      set -e
      MODE="''${1:-to-usb}"
      LUKS_DEVICE="/dev/disk/by-partlabel/NIXOS_USB_CRYPT"
      MAPPER="usb-sync-root"
      MOUNT="/mnt/usb-sync"
      LOCAL="$HOME/.copilot/session-state"
      REMOTE="$MOUNT/home/stefan/.copilot/session-state"

      if [ ! -e "$LUKS_DEVICE" ]; then
        echo "USB not found. Plug in the USB drive and try again."
        exit 1
      fi

      sudo ${pkgs.cryptsetup}/bin/cryptsetup luksOpen "$LUKS_DEVICE" "$MAPPER"
      sudo mkdir -p "$MOUNT"
      sudo mount "/dev/mapper/$MAPPER" "$MOUNT"
      sudo mkdir -p "$REMOTE"

      case "$MODE" in
        to-usb)
          echo "Syncing desktop → USB..."
          sudo ${pkgs.rsync}/bin/rsync -av --update "$LOCAL/" "$REMOTE/"
          ;;
        from-usb)
          echo "Syncing USB → desktop..."
          ${pkgs.rsync}/bin/rsync -av --update "$REMOTE/" "$LOCAL/"
          ;;
        *)
          echo "Usage: copilot-sessions-sync [to-usb|from-usb]"
          sudo umount "$MOUNT"
          sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
          exit 1
          ;;
      esac

      sudo umount "$MOUNT"
      sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
      echo "Done."
    '')
    (pkgs.writeShellScriptBin "transmission-port-sync" ''
      set -e
      CONFIG_DIR="$HOME/.config/fragments"
      SETTINGS_FILE="$CONFIG_DIR/settings.json"

      if [ -z "$1" ]; then
          echo "Usage: $0 <port>"
          exit 1
      fi
    '')
    (pkgs.writeShellScriptBin "hypr-nav" ''
      DIRECTION=$1
      BEFORE=$(hyprctl activewindow -j | jq -r '.address')
      hyprctl dispatch movefocus $DIRECTION
      AFTER=$(hyprctl activewindow -j | jq -r '.address')

      if [ "$BEFORE" == "$AFTER" ] || [ "$BEFORE" == "null" ]; then
          CURR=$(hyprctl activeworkspace -j | jq '.id')
          if [ "$DIRECTION" == "r" ]; then
              NEXT=$(( (CURR % 10) + 1 ))
              hyprctl dispatch workspace $NEXT
          elif [ "$DIRECTION" == "l" ]; then
              NEXT=$(( CURR - 1 ))
              [ $NEXT -lt 1 ] && NEXT=10
              hyprctl dispatch workspace $NEXT
          fi
      fi
    '')
    (pkgs.writeShellScriptBin "hypr-quit-active" ''
      set -euo pipefail

      active=$(hyprctl activewindow -j 2>/dev/null || true)
      pid=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.pid // empty')
      app_class=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.class // empty')
      app_title=$(printf '%s' "$active" | ${pkgs.jq}/bin/jq -r '.title // empty')

      if [ -z "$pid" ] || [ "$pid" = "null" ]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Quit active app" "No active window to quit."
        exit 1
      fi

      resolve_root_pid() {
        local candidate="$1"
        local exe
        exe=$(readlink -f "/proc/$candidate/exe" 2>/dev/null || true)
        [ -n "$exe" ] || {
          printf '%s\n' "$candidate"
          return
        }

        while true; do
          local ppid
          local parent_exe

          ppid=$(${pkgs.procps}/bin/ps -o ppid= -p "$candidate" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')
          [ -n "$ppid" ] || break
          [ "$ppid" -le 1 ] && break

          parent_exe=$(readlink -f "/proc/$ppid/exe" 2>/dev/null || true)
          [ "$parent_exe" = "$exe" ] || break

          candidate="$ppid"
        done

        printf '%s\n' "$candidate"
      }

      target_pid=$(resolve_root_pid "$pid")
      label="$app_class"
      [ -n "$label" ] || label="$app_title"
      [ -n "$label" ] || label="PID $target_pid"

      kill -TERM "$target_pid"

      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ! kill -0 "$target_pid" 2>/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      ${pkgs.libnotify}/bin/notify-send -u low "Quit active app" "Force killing $label"
      kill -KILL "$target_pid"
    '')
    (pkgs.writeShellScriptBin "screenshot-path-copy" ''
      # Wraps dms screenshot to copy the FILE PATH to clipboard instead of the image
      dest=$(dms screenshot "$@" --no-clipboard --no-notify)
      if [ -n "$dest" ] && [ -f "$dest" ]; then
          echo -n "$dest" | ${pkgs.wl-clipboard}/bin/wl-copy
          ${pkgs.libnotify}/bin/notify-send -u low -i "$dest" "Screenshot" "Path copied: $dest"
      fi
    '')
  ];
}
