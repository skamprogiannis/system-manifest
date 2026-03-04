{
  pkgs,
  config,
  lib,
  ...
}: {
  systemd.user.services.mpvpaper = {
    Unit = {
      Description = "Mpvpaper Video Wallpaper Service";
      After = ["hyprland-session.target"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${pkgs.mpvpaper}/bin/mpvpaper -o \"no-audio --loop-file=inf --hwdec=auto --vd-lavc-threads=2 --cache=no --demuxer-max-bytes=10M --demuxer-max-back-bytes=1M\" \"*\" \"$MPV_WALLPAPER_PATH\"'";
      Restart = "always";
      RestartSec = "2.5";
      RuntimeMaxSec = "600s";
      TimeoutStopSec = "2s";
    };
  };

  systemd.user.services.wallpaper-thumbnail-watcher = {
    Unit = {
      Description = "Watch wallpapers directory for new MP4 files and generate thumbnails";
      After = ["hyprland-session.target"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${pkgs.inotify-tools}/bin/inotifywait -m -e create -e moved_to -e close_write --format \"%w%f\" \"$HOME/wallpapers\" | while read -r file; do case \"$file\" in *.mp4) \"$HOME/.local/bin/generate-thumbnails\" ;; esac; done'";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  home.packages = [
    pkgs.swaybg
    (pkgs.writeShellScriptBin "wallpaper-hook" ''
      LOCKFILE="/tmp/wallpaper-hook.lock"
      exec 9>"$LOCKFILE"
      if ! flock -n 9; then
        exit 1
      fi

      CACHE_WALL="$HOME/.cache/current_wallpaper"

      cleanup() {
        systemctl --user stop mpvpaper.service
        pkill swaybg || true
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
        
        # Extract colors
        PRIMARY=$(grep "\$primary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        BG=$(grep "\$surface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        FG=$(grep "\$onSurface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        ACCENT=$(grep "\$secondary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')

        # If primary is too dark (low perceived brightness), use accent instead
        # Calculate perceived brightness: (R * 299 + G * 587 + B * 114) / 1000
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

        echo "Updating GTK colors for Brave..."
        for version in 3.0 4.0; do
          mkdir -p "$HOME/.config/gtk-$version"
          cat <<EOF > "$HOME/.config/gtk-$version/gtk.css"
@define-color accent_color #$PRIMARY;
@define-color accent_bg_color #$PRIMARY;
@define-color accent_fg_color #$BG;
@define-color window_bg_color #$BG;
@define-color window_fg_color #$FG;
@define-color view_bg_color #$BG;
@define-color view_fg_color #$FG;
@define-color headerbar_bg_color #$BG;
@define-color headerbar_fg_color #$FG;
@define-color headerbar_border_color #$BG;
@define-color headerbar_backdrop_color @headerbar_bg_color;
@define-color card_bg_color #$BG;
@define-color card_fg_color #$FG;
@define-color dialog_bg_color #$BG;
@define-color dialog_fg_color #$FG;
@define-color popover_bg_color #$BG;
@define-color popover_fg_color #$FG;
@define-color sidebar_bg_color #$BG;
@define-color sidebar_fg_color #$FG;
@define-color scrollbar_outline_color #$BG;
EOF
        done

        echo "Updating Hyprland borders..."
        hyprctl keyword general:col.active_border "rgba(''${PRIMARY}99)"
      }

      # Initial theme update on startup
      update_themes

      while true; do
        NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)
        
        if [ -n "$NEW_WALL" ] && [ "$NEW_WALL" != "$CURRENT_WALL" ]; then
          CURRENT_WALL="$NEW_WALL"
          echo "$CURRENT_WALL" > "$CACHE_WALL"
          
          if echo "$NEW_WALL" | grep -q ".thumbnails/"; then
            BASE_NAME=$(basename "''${NEW_WALL%.*}")
            PARENT_DIR=$(dirname "$(dirname "$NEW_WALL")")
            MP4_WALL="''${PARENT_DIR}/''${BASE_NAME}.mp4"
          else
            MP4_WALL="''${NEW_WALL%.*}.mp4"
          fi
          
          if [ -f "$MP4_WALL" ]; then
            echo "Video wallpaper: $MP4_WALL"
            systemctl --user set-environment MPV_WALLPAPER_PATH="$MP4_WALL"
            systemctl --user restart mpvpaper.service
            # Kill swaybg if it was running for startup
            [ -n "$SWAYBG_PID" ] && kill $SWAYBG_PID && SWAYBG_PID=""
          else
            echo "Static wallpaper: $NEW_WALL"
            systemctl --user stop mpvpaper.service
            ${pkgs.swaybg}/bin/swaybg -i "$NEW_WALL" -m fill &
            SWAYBG_PID=$!
          fi
          
          update_themes
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
        fi
      done
    '')
  ];
}
