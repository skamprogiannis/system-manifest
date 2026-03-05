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
    (pkgs.writeShellScriptBin "switch-kbdlayout" ''
      # Switch keyboard layout on the main keyboard device
      DEVICE=$(hyprctl devices -j 2>/dev/null | jq -r '.keyboards[] | select(.main == true) | .name' || echo "")
      if [ -z "$DEVICE" ]; then
        exit 1
      fi
      hyprctl switchxkblayout "$DEVICE" next
    '')
    (pkgs.writeShellScriptBin "brave-no-gpu" ''
      exec ${pkgs.brave}/bin/brave --disable-gpu --disable-software-rasterizer --disable-accelerated-2d-canvas --disable-accelerated-video-decode --disable-gpu-compositing --ignore-gpu-blacklist "$@"
    '')
    (pkgs.writeShellScriptBin "firefox-no-gpu" ''
      export MOZ_WEBRENDER=0
      exec ${pkgs.firefox}/bin/firefox "$@"
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
