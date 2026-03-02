{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "sync-transmission-port" ''
      set -e
      CONFIG_DIR="$HOME/.config/fragments"
      SETTINGS_FILE="$CONFIG_DIR/settings.json"

      if [ -z "$1" ]; then
          echo "Usage: $0 <port>"
          exit 1
      fi

      NEW_PORT="$1"
      echo "Updating Transmission port to $NEW_PORT..."
      sed -i "s/\"peer-port\": [0-9]*/\"peer-port\": $NEW_PORT/" "$SETTINGS_FILE"
      echo "Restarting transmission-daemon..."
      pkill -f transmission-daemon || true
      sleep 2
      transmission-daemon --no-auth -g "$CONFIG_DIR" -p 9091 &
      sleep 3
      echo "Done! Port $NEW_PORT is now active."
    '')
    (pkgs.writeShellScriptBin "screenshot-path" ''
      MODE="''${1:-region}"
      TYPE="''${2:-path}"
      dest="$HOME/pictures/screenshots/$(date +%s).png"
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
