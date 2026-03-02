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
    };
  };

  home.packages = [
    (pkgs.writeShellScriptBin "wallpaper-hook" ''
      LOCKFILE="/tmp/wallpaper-hook.lock"
      exec 9>"$LOCKFILE"
      if ! flock -n 9; then
        exit 1
      fi

      cleanup() {
        systemctl --user stop mpvpaper.service
        rm -f "$LOCKFILE"
      }
      trap cleanup EXIT SIGTERM

      # Wait for environment
      until hyprctl monitors &>/dev/null; do sleep 1; done
      sleep 2
      until dms ipc wallpaper get &>/dev/null; do sleep 1; done

      CURRENT_WALL=""
      LAST_COLORS_HASH=""

      update_zathura() {
        local color_file="$HOME/.config/hypr/dms/colors.conf"
        [ ! -f "$color_file" ] && return
        
        local current_hash=$(${pkgs.coreutils}/bin/md5sum "$color_file" | cut -d' ' -f1)
        [ "$current_hash" = "$LAST_COLORS_HASH" ] && return
        LAST_COLORS_HASH="$current_hash"
        
        echo "Updating Zathura colors..."
        PRIMARY=$(grep "\$primary =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        BG=$(grep "\$surface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        FG=$(grep "\$onSurface =" "$color_file" | cut -d'(' -f2 | cut -d')' -f1 | sed 's/ff$//')
        
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

      while true; do
        NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)
        
        if [ -n "$NEW_WALL" ] && [ "$NEW_WALL" != "$CURRENT_WALL" ]; then
          CURRENT_WALL="$NEW_WALL"
          
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
          else
            echo "Static wallpaper: $NEW_WALL"
            systemctl --user stop mpvpaper.service
          fi
          
          update_zathura
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
