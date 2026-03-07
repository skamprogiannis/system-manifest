{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "specify" ''
      exec ${pkgs.uv}/bin/uvx --from git+https://github.com/github/spec-kit.git specify "$@"
    '')
    (pkgs.writeShellScriptBin "sync-copilot-sessions" ''
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
          echo "Usage: sync-copilot-sessions [to-usb|from-usb]"
          sudo umount "$MOUNT"
          sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
          exit 1
          ;;
      esac

      sudo umount "$MOUNT"
      sudo ${pkgs.cryptsetup}/bin/cryptsetup luksClose "$MAPPER"
      echo "Done."
    '')
    (pkgs.writeShellScriptBin "sync-transmission-port" ''
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
    (pkgs.writeShellScriptBin "screenshot-path" ''

      MODE="''${1:-region}"
      TYPE="''${2:-path}"
      dest="$HOME/pictures/screenshots/screenshot_$(date +%F_%H-%M-%S).png"
      mkdir -p "$(dirname "$dest")"

      
      case "$MODE" in
          "full")
              ${pkgs.grim}/bin/grim "$dest"
              ;;
          "window")
              ${pkgs.grim}/bin/grim -g "$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" "$dest"
              ;;
          *)
              ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$dest"
              ;;
      esac

      if [ -f "$dest" ]; then
          if [ "$TYPE" = "image" ]; then
              ${pkgs.wl-clipboard}/bin/wl-copy < "$dest"
              ${pkgs.libnotify}/bin/notify-send -u low -i "$dest" "Screenshot ($MODE)" "Image copied to clipboard"
          else
              echo -n "$dest" | ${pkgs.wl-clipboard}/bin/wl-copy
              ${pkgs.libnotify}/bin/notify-send -u low -i "$dest" "Screenshot ($MODE)" "Path copied to clipboard"
          fi
      fi
    '')
    (pkgs.writeShellScriptBin "screenrecord" ''
      LOCK="/tmp/screenrecord.lock"

      if [ -f "$LOCK" ]; then
          PID=$(head -1 "$LOCK")
          SAVED=$(tail -1 "$LOCK")
          if kill -0 "$PID" 2>/dev/null; then
              kill "$PID"
              rm -f "$LOCK"
              ${pkgs.libnotify}/bin/notify-send -u low "Recording stopped" "$SAVED"
              exit 0
          else
              rm -f "$LOCK"
          fi
      fi

      DEST="$HOME/videos/screencasts/screencast_$(date +%F_%H-%M-%S).mp4"
      mkdir -p "$(dirname "$DEST")"
      MODE="''${1:-region}"
      case "$MODE" in
          full)
              ${pkgs.wf-recorder}/bin/wf-recorder --audio -f "$DEST" &
              ;;
          *)
              ${pkgs.wf-recorder}/bin/wf-recorder --audio -g "$(${pkgs.slurp}/bin/slurp)" -f "$DEST" &
              ;;
      esac
      printf '%s\n%s\n' "$!" "$DEST" > "$LOCK"
      ${pkgs.libnotify}/bin/notify-send -u low "Recording started" "Mode: $MODE — press Super+R again to stop"
    '')
  ];

  home.file."scripts/screenshot-path.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # This script is managed by Home Manager
      screenshot-path "$@"
    '';
  };
}
