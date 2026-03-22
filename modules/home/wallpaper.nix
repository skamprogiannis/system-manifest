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
      # GPU may segfault repeatedly after suspend on Nvidia; keep retrying
      StartLimitBurst = 20;
      StartLimitIntervalSec = 120;
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
    (pkgs.writeShellScriptBin "we-sync" ''
      WE_WORKSHOP="$HOME/games/SteamLibrary/steamapps/workshop/content/431960"
      WE_DEFAULTS="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/projects/defaultprojects"
      WALL_DIR="$HOME/wallpapers"
      MAP_FILE="$HOME/.cache/we-wallpaper-map.json"
      WE_SUBS=$(ls -1t "$HOME/.local/share/Steam/userdata"/*/ugc/431960_subscriptions.vdf 2>/dev/null | head -n 1)

      mkdir -p "$WALL_DIR"

      echo "{" > "$MAP_FILE.tmp"
      FIRST=true
      declare -A EXPECTED_THUMBS
      declare -A SUBSCRIBED_IDS

      WE_ASSETS="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/assets"

      # Render a 1920x1080 screenshot via WE's offscreen GL window
      generate_screenshot() {
        local bg_dir="$1" dst="$2"
        rm -f "$dst"
        ${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine \
          --assets-dir "$WE_ASSETS" \
          --window 0x0x1920x1080 \
          --screenshot "$dst" \
          --screenshot-delay 3 --fps 1 \
          --silent --disable-mouse \
          "$bg_dir" &>/dev/null &
        local pid=$!
        # Poll until screenshot file appears (max 10s)
        local waited=0
        while [ ! -s "$dst" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 50 ]; do
          sleep 0.2
          waited=$((waited + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
          kill "$pid" 2>/dev/null || true
          local kill_wait=0
          while kill -0 "$pid" 2>/dev/null && [ "$kill_wait" -lt 10 ]; do
            sleep 0.2
            kill_wait=$((kill_wait + 1))
          done
          if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
          fi
        fi
        wait "$pid" 2>/dev/null || true
        [ -s "$dst" ]
      }

      # Fallback: scale-to-fill (cover crop) preview image to 16:9
      generate_thumb_fallback() {
        local src="$1" dst="$2"
        local frame="$src"
        if [[ "$src" == *.gif ]]; then
          # Pick the middle frame — avoids intro/blank frames and is more
          # representative. Gaussian filter during resize smooths out GIF
          # dithering artifacts (256-colour palette banding).
          local nframes
          nframes=$(${pkgs.imagemagick}/bin/magick identify "$src" 2>/dev/null | wc -l)
          local mid=$(( nframes / 2 ))
          frame="''${src}[''${mid}]"
        fi
        ${pkgs.imagemagick}/bin/magick "$frame" \
          -filter Gaussian \
          -resize 1920x1080^ -gravity center \
          -extent 1920x1080 \
          -quality 92 \
          "$dst" 2>/dev/null
      }

      # Process a single wallpaper directory
      process_dir() {
        local dir="$1"
        [ -d "$dir" ] || return
        local dir_id
        dir_id=$(basename "$dir")
        if [[ "$dir_id" =~ ^[0-9]+$ ]] && [ "''${#SUBSCRIBED_IDS[@]}" -gt 0 ] && [ -z "''${SUBSCRIBED_IDS[$dir_id]+x}" ]; then
          return
        fi
        [ -f "$dir/project.json" ] || return

        TITLE=$(${pkgs.jq}/bin/jq -r '.title // "unknown"' "$dir/project.json")
        SAFE_TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
        THUMB_NAME="''${SAFE_TITLE}.jpg"

        if [ -n "''${EXPECTED_THUMBS[$THUMB_NAME]+x}" ]; then
          THUMB_NAME="''${SAFE_TITLE}-$(basename "$dir").jpg"
        fi
        EXPECTED_THUMBS["$THUMB_NAME"]=1

        THUMB_PATH="$WALL_DIR/$THUMB_NAME"

        if [ ! -f "$THUMB_PATH" ]; then
          echo "  Rendering: $SAFE_TITLE..."
          if ! generate_screenshot "$dir" "$THUMB_PATH"; then
            echo "  Screenshot failed, using preview fallback"
            local preview=""
            [ -f "$dir/preview.jpg" ] && preview="$dir/preview.jpg"
            [ -z "$preview" ] && [ -f "$dir/preview.gif" ] && preview="$dir/preview.gif"
            [ -n "$preview" ] && generate_thumb_fallback "$preview" "$THUMB_PATH"
          fi
        fi

        if [ "$FIRST" = true ]; then
          FIRST=false
        else
          echo "," >> "$MAP_FILE.tmp"
        fi
        printf '  "%s": "%s"' "$THUMB_NAME" "$dir" >> "$MAP_FILE.tmp"
      }

      # Read currently subscribed Workshop IDs so stale leftover directories
      # from unsubscribed wallpapers are ignored.
      if [ -n "$WE_SUBS" ] && [ -f "$WE_SUBS" ]; then
        while IFS= read -r wid; do
          SUBSCRIBED_IDS["$wid"]=1
        done < <(sed -n 's/^[[:space:]]*"publishedfileid"[[:space:]]*"\([0-9]\+\)".*$/\1/p' "$WE_SUBS")
      fi

      # Scan workshop subscriptions
      for dir in "$WE_WORKSHOP"/*/; do
        process_dir "$dir"
      done

      # Include select bundled wallpapers
      process_dir "$WE_DEFAULTS/razer_vortex"

      echo "" >> "$MAP_FILE.tmp"
      echo "}" >> "$MAP_FILE.tmp"
      mv "$MAP_FILE.tmp" "$MAP_FILE"

      # Clean stale thumbnails not in current mapping
      for thumb in "$WALL_DIR"/*.jpg; do
        [ -f "$thumb" ] || [ -L "$thumb" ] || continue
        BASENAME=$(basename "$thumb")
        [[ "$thumb" == */static/* ]] && continue
        if [ -z "''${EXPECTED_THUMBS[$BASENAME]+x}" ]; then
          echo "Removing stale: $BASENAME"
          rm -f "$thumb"
        fi
      done

      echo "Synced $(echo "''${!EXPECTED_THUMBS[@]}" | wc -w) Wallpaper Engine wallpapers"
    '')

    (pkgs.writeShellScriptBin "we-mute" ''
      WE_PID=$(systemctl --user show -p MainPID --value linux-wallpaperengine.service 2>/dev/null)
      if [ -z "$WE_PID" ] || [ "$WE_PID" = "0" ]; then
        echo "Wallpaper Engine is not running"
        exit 1
      fi
      # WE has multiple Client objects per PID; find the Node whose client.id is any of them
      NODE_ID=$(${pkgs.pipewire}/bin/pw-dump 2>/dev/null | ${pkgs.jq}/bin/jq -r \
        --argjson pid "$WE_PID" \
        '([ .[] | select(.type == "PipeWire:Interface:Client" and .info.props."application.process.id" == $pid) | .id ]) as $cids |
         .[] | select(.type == "PipeWire:Interface:Node" and (.info.props."client.id" as $cid | $cids | contains([$cid])) and .info.props."media.class" == "Stream/Output/Audio") | .id' \
        | head -1)
      if [ -z "$NODE_ID" ]; then
        echo "No audio stream found for Wallpaper Engine (wallpaper may have no sound)"
        exit 0
      fi
      ${pkgs.wireplumber}/bin/wpctl set-mute "$NODE_ID" 1
      echo "Wallpaper Engine audio muted (node $NODE_ID)"
    '')

    (pkgs.writeShellScriptBin "we-unmute" ''
      WE_PID=$(systemctl --user show -p MainPID --value linux-wallpaperengine.service 2>/dev/null)
      if [ -z "$WE_PID" ] || [ "$WE_PID" = "0" ]; then
        echo "Wallpaper Engine is not running"
        exit 1
      fi
      # WE has multiple Client objects per PID; find the Node whose client.id is any of them
      NODE_ID=$(${pkgs.pipewire}/bin/pw-dump 2>/dev/null | ${pkgs.jq}/bin/jq -r \
        --argjson pid "$WE_PID" \
        '([ .[] | select(.type == "PipeWire:Interface:Client" and .info.props."application.process.id" == $pid) | .id ]) as $cids |
         .[] | select(.type == "PipeWire:Interface:Node" and (.info.props."client.id" as $cid | $cids | contains([$cid])) and .info.props."media.class" == "Stream/Output/Audio") | .id' \
        | head -1)
      if [ -z "$NODE_ID" ]; then
        echo "No audio stream found for Wallpaper Engine (wallpaper may have no sound)"
        exit 0
      fi
      ${pkgs.wireplumber}/bin/wpctl set-mute "$NODE_ID" 0
      echo "Wallpaper Engine audio unmuted (node $NODE_ID)"
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
        rm -f "$LOCKFILE"
      }
      trap cleanup EXIT SIGTERM

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
          else
            # Static wallpaper — DMS renders it natively, just stop WE
            echo "Static wallpaper: $NEW_WALL"
            systemctl --user stop linux-wallpaperengine.service 2>/dev/null
          fi

          update_themes
        fi
        sleep 2
      done
    '')
  ];
}
