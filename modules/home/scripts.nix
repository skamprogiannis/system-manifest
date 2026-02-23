{ pkgs, ... }: {
  home.packages = [
    (pkgs.writeShellScriptBin "wallpaper-hook" ''
      # Monitor DMS for wallpaper changes and launch mpvpaper if a video exists
      CURRENT_WALL=""
      
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
                  pkill mpvpaper
                  mpvpaper -o "no-audio --loop" "*" "$MP4_WALL" &
              else
                  echo "Static wallpaper detected: $NEW_WALL"
                  pkill mpvpaper
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
  ];
}
