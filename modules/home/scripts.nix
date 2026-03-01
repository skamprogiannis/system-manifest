{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "wallpaper-hook" ''
      LOCKFILE="/tmp/wallpaper-hook.lock"
      exec 9>"$LOCKFILE"
      if ! flock -n 9; then
        echo "Another instance of wallpaper-hook is already running."
        exit 1
      fi

      # Function to clean up on exit
      cleanup() {
        pkill -f "mpvpaper-loop" || true
        pkill mpvpaper || true
        rm -f "$LOCKFILE"
      }
      trap cleanup EXIT SIGTERM

      # Monitor DMS for wallpaper changes and launch mpvpaper if a video exists
      CURRENT_WALL=""

      # Wait for DMS to be ready and Matugen to settle
      sleep 0.5
      until dms ipc wallpaper get &>/dev/null; do
          sleep 0.2
      done

      # Initial check on startup
      NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)
      if [ -n "$NEW_WALL" ]; then
          # Force an update even if CURRENT_WALL is empty
          CURRENT_WALL="FORCE_UPDATE"
      fi

      while true; do
          # Get current wallpaper path from DMS
          NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)

          if [ -z "$NEW_WALL" ]; then
              sleep 2
              continue
          fi

          if [ "$NEW_WALL" != "$CURRENT_WALL" ]; then
              CURRENT_WALL="$NEW_WALL"
              
              # Check if the wallpaper is a thumbnail in the hidden folder
              if echo "$NEW_WALL" | grep -q ".thumbnails/"; then
                  BASE_NAME=$(basename "''${NEW_WALL%.*}")
                  PARENT_DIR=$(dirname "$(dirname "$NEW_WALL")")
                  MP4_WALL="''${PARENT_DIR}/''${BASE_NAME}.mp4"
              else
                  BASE_NAME="''${NEW_WALL%.*}"
                  MP4_WALL="''${BASE_NAME}.mp4"
              fi
              
               if [ -f "$MP4_WALL" ]; then
                   echo "Video wallpaper detected: $MP4_WALL"
                   
                # Kill any existing restarter script and mpvpaper process
                pkill -f "mpvpaper-loop" || true
                pkill mpvpaper || true
                sleep 1.5
                   
                   # Run a loop that restarts mpvpaper every 600s (10 minutes) with a hard kill to avoid Wayland buffer crash
                   bash -c 'exec -a mpvpaper-loop bash -c "trap \"kill 0\" EXIT SIGTERM; while true; do mpvpaper -o \"no-audio --loop-file=inf --hwdec=auto --vd-lavc-threads=2 --cache=no --demuxer-max-bytes=10M --demuxer-max-back-bytes=1M\" \"*\" \"$1\" & PID=\$!; sleep 600 & wait \$!; kill \$PID 2>/dev/null; sleep 1.5; done"' -- "$MP4_WALL" &
               else
                   echo "Static wallpaper detected: $NEW_WALL"
                   pkill -f "mpvpaper-loop" || true
                   pkill mpvpaper || true
               fi


              # Update Zathura colors from Matugen
              if [ -f ~/.config/hypr/dms/colors.conf ]; then
                  echo "Updating Zathura colors..."
                  # Extract colors from hyprland dms colors.conf
                  PRIMARY=$(grep "\$primary =" ~/.config/hypr/dms/colors.conf | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
                  BG=$(grep "\$surface =" ~/.config/hypr/dms/colors.conf | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
                  FG=$(grep "\$onSurface =" ~/.config/hypr/dms/colors.conf | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
                  
                  mkdir -p ~/.config/zathura
                  cat <<EOF > ~/.config/zathura/zathurarc
set recolor "true"
set completion-bg "#$BG"
set completion-fg "#$FG"
set completion-highlight-bg "#$PRIMARY"
set completion-highlight-fg "#$BG"
set recolor-lightcolor "#$BG"
set recolor-darkcolor "#$FG"
set default-bg "#$BG"
set default-fg "#$FG"
set statusbar-bg "#$BG"
set statusbar-fg "#$FG"
set inputbar-bg "#$BG"
set inputbar-fg "#$FG"
set notification-error-bg "#ff5555"
set notification-error-fg "#$FG"
set notification-warning-bg "#ffb86c"
set notification-warning-fg "#$FG"
set highlight-color "#$PRIMARY"
set highlight-active-color "#$PRIMARY"
EOF
              fi
          fi
          sleep 2
      done
    '')

    (pkgs.writeShellScriptBin "generate-thumbnails" ''
      WALLPAPER_DIR="$HOME/wallpapers"
      THUMBNAIL_DIR="$WALLPAPER_DIR/.thumbnails"

      mkdir -p "$THUMBNAIL_DIR"
      cd "$WALLPAPER_DIR" || exit 1

      for video in *.mp4; do
          [ -f "$video" ] || continue
          base_name="''${video%.*}"
          thumbnail="$THUMBNAIL_DIR/''${base_name}.png"
          
          if [ ! -f "$thumbnail" ]; then
              echo "Generating thumbnail for $video..."
              ${pkgs.ffmpeg}/bin/ffmpeg -y -i "$video" -ss 00:00:01 -update 1 -vframes 1 "$thumbnail"
          else
              echo "Thumbnail exists for $video"
          fi
      done
      echo "Thumbnail generation complete."
    '')

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
