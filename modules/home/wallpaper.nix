{
  pkgs,
  config,
  lib,
  ...
}: {
  systemd.user.services.linux-wallpaperengine = {
    Unit = {
      Description = "Wallpaper Engine Live Wallpaper";
      After = ["hyprland-session.target"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash -c 'silent=\"\"; [ \"\$WE_SILENT\" = \"1\" ] && silent=\"--silent\"; exec ${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine --assets-dir \"\$WE_ASSETS_DIR\" \"\$WE_WALLPAPER_DIR\" --screen-root HDMI-A-1 --screen-root DP-1 \$silent'";
      Restart = "on-failure";
      RestartSec = "2.5";
      TimeoutStopSec = "2s";
    };
  };

  home.packages = [
    pkgs.swaybg
    (pkgs.writeShellScriptBin "we-sync" ''
      WE_WORKSHOP="$HOME/games/SteamLibrary/steamapps/workshop/content/431960"
      WALL_DIR="$HOME/wallpapers"
      MAP_FILE="$HOME/.cache/we-wallpaper-map.json"

      mkdir -p "$WALL_DIR"

      # Build new mapping and track expected thumbnails
      echo "{" > "$MAP_FILE.tmp"
      FIRST=true
      declare -A EXPECTED_THUMBS

      for dir in "$WE_WORKSHOP"/*/; do
        [ -d "$dir" ] || continue
        [ -f "$dir/project.json" ] || continue

        PREVIEW_SRC=""
        if [ -f "$dir/preview.jpg" ]; then
          PREVIEW_SRC="$dir/preview.jpg"
        elif [ -f "$dir/preview.gif" ]; then
          PREVIEW_SRC="$dir/preview.gif"
        else
          continue
        fi

        TITLE=$(${pkgs.jq}/bin/jq -r '.title // "unknown"' "$dir/project.json")
        SAFE_TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
        THUMB_NAME="''${SAFE_TITLE}.jpg"

        # Handle duplicate names by appending dir basename
        if [ -n "''${EXPECTED_THUMBS[$THUMB_NAME]+x}" ]; then
          THUMB_NAME="''${SAFE_TITLE}-$(basename "$dir").jpg"
        fi
        EXPECTED_THUMBS["$THUMB_NAME"]=1

        THUMB_PATH="$WALL_DIR/$THUMB_NAME"

        if [ "''${PREVIEW_SRC##*.}" = "gif" ]; then
          # Convert first gif frame to jpg
          if [ ! -f "$THUMB_PATH" ] || [ "$PREVIEW_SRC" -nt "$THUMB_PATH" ]; then
            ${pkgs.imagemagick}/bin/magick "''${PREVIEW_SRC}[0]" "$THUMB_PATH" 2>/dev/null
          fi
        else
          # Symlink jpg preview directly
          ln -sf "$PREVIEW_SRC" "$THUMB_PATH"
        fi

        if [ "$FIRST" = true ]; then
          FIRST=false
        else
          echo "," >> "$MAP_FILE.tmp"
        fi
        printf '  "%s": "%s"' "$THUMB_NAME" "$dir" >> "$MAP_FILE.tmp"
      done

      echo "" >> "$MAP_FILE.tmp"
      echo "}" >> "$MAP_FILE.tmp"
      mv "$MAP_FILE.tmp" "$MAP_FILE"

      # Clean stale thumbnails not in current mapping
      for thumb in "$WALL_DIR"/*.jpg; do
        [ -f "$thumb" ] || [ -L "$thumb" ] || continue
        BASENAME=$(basename "$thumb")
        # Skip static wallpapers subdirectory contents
        [[ "$thumb" == */static/* ]] && continue
        if [ -z "''${EXPECTED_THUMBS[$BASENAME]+x}" ]; then
          echo "Removing stale: $BASENAME"
          rm -f "$thumb"
        fi
      done

      echo "Synced $(echo "''${!EXPECTED_THUMBS[@]}" | wc -w) Wallpaper Engine wallpapers"
    '')

    (pkgs.writeShellScriptBin "we-mute" ''
      systemctl --user set-environment WE_SILENT=1
      systemctl --user restart linux-wallpaperengine.service
      echo "Wallpaper Engine audio muted"
    '')

    (pkgs.writeShellScriptBin "we-unmute" ''
      systemctl --user unset-environment WE_SILENT
      systemctl --user restart linux-wallpaperengine.service
      echo "Wallpaper Engine audio restored (auto-mutes when other audio plays)"
    '')

    (pkgs.writeShellScriptBin "wallpaper-hook" ''
      LOCKFILE="/tmp/wallpaper-hook.lock"
      exec 9>"$LOCKFILE"
      if ! flock -n 9; then
        exit 1
      fi

      CACHE_WALL="$HOME/.cache/current_wallpaper"
      MAP_FILE="$HOME/.cache/we-wallpaper-map.json"
      WE_ASSETS="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/assets"

      cleanup() {
        systemctl --user stop linux-wallpaperengine.service 2>/dev/null
        for pid in $(pgrep -x swaybg); do kill "$pid" 2>/dev/null; done
        rm -f "$LOCKFILE"
      }
      trap cleanup EXIT SIGTERM

      # Fast static startup
      if [ -f "$CACHE_WALL" ]; then
        LAST_WALL=$(cat "$CACHE_WALL")
        if [ -f "$LAST_WALL" ]; then
          ${pkgs.swaybg}/bin/swaybg -i "$LAST_WALL" -m fill &
          SWAYBG_PID=$!
        fi
      fi

      # Wait for environment
      until hyprctl monitors &>/dev/null; do sleep 1; done
      sleep 1
      until dms ipc wallpaper get &>/dev/null; do sleep 0.5; done

      CURRENT_WALL=""
      LAST_COLORS_HASH=""

      update_themes() {
        local color_file="$HOME/.config/hypr/dms/colors.conf"
        [ ! -f "$color_file" ] && return

        local current_hash=$(${pkgs.coreutils}/bin/md5sum "$color_file" | cut -d' ' -f1)
        [ "$current_hash" = "$LAST_COLORS_HASH" ] && return
        LAST_COLORS_HASH="$current_hash"

        PRIMARY=$(grep "\$primary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        BG=$(grep "\$surface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        FG=$(grep "\$onSurface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        ACCENT=$(grep "\$secondary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')

        # If primary is too dark, use accent instead
        if [ -n "$PRIMARY" ] && [ $((''${#PRIMARY})) -ge 6 ] 2>/dev/null; then
          PRIMARY_R=$((16#''${PRIMARY:0:2})) 2>/dev/null || PRIMARY_R=0
          PRIMARY_G=$((16#''${PRIMARY:2:2})) 2>/dev/null || PRIMARY_G=0
          PRIMARY_B=$((16#''${PRIMARY:4:2})) 2>/dev/null || PRIMARY_B=0
          BRIGHTNESS=$(( (PRIMARY_R * 299 + PRIMARY_G * 587 + PRIMARY_B * 114) / 1000 ))
          if [ "$BRIGHTNESS" -lt 80 ]; then
            PRIMARY="$ACCENT"
          fi
        fi

        echo "Updating Zathura colors..."
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
      }

      # Resolve wallpaper image to WE directory via mapping file
      resolve_we_dir() {
        local wall_path="$1"
        [ ! -f "$MAP_FILE" ] && return 1
        local bname
        bname=$(basename "$wall_path")
        local we_dir
        we_dir=$(${pkgs.jq}/bin/jq -r --arg k "$bname" '.[$k] // empty' "$MAP_FILE")
        [ -n "$we_dir" ] && echo "$we_dir" && return 0
        return 1
      }

      # Ensure WE wallpaper map is fresh before first poll
      we-sync &>/dev/null || true

      # Initial theme update on startup
      update_themes

      while true; do
        NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)

        if [ -n "$NEW_WALL" ] && [ "$NEW_WALL" != "$CURRENT_WALL" ]; then
          CURRENT_WALL="$NEW_WALL"
          echo "$CURRENT_WALL" > "$CACHE_WALL"

          WE_DIR=$(resolve_we_dir "$NEW_WALL")

          if [ -n "$WE_DIR" ]; then
            echo "Wallpaper Engine: $WE_DIR"
            systemctl --user set-environment WE_WALLPAPER_DIR="$WE_DIR" WE_ASSETS_DIR="$WE_ASSETS"
            systemctl --user restart linux-wallpaperengine.service
            [ -n "$SWAYBG_PID" ] && kill $SWAYBG_PID 2>/dev/null && SWAYBG_PID=""
          else
            echo "Static wallpaper: $NEW_WALL"
            systemctl --user stop linux-wallpaperengine.service 2>/dev/null
            [ -n "$SWAYBG_PID" ] && kill $SWAYBG_PID 2>/dev/null
            ${pkgs.swaybg}/bin/swaybg -i "$NEW_WALL" -m fill &
            SWAYBG_PID=$!
          fi

          update_themes
        fi
        sleep 2
      done
    '')
  ];
}
