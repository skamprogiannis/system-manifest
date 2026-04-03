{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  # Shared wallpaper-engine path constants (inlined from former wallpaper-common.nix)
  weConstants = ''
    MAP_FILE="$HOME/.cache/we-wallpaper-map.json"
    WE_ASSETS="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/assets"
    WE_WORKSHOP="$HOME/games/SteamLibrary/steamapps/workshop/content/431960"
    WE_DEFAULTS_ROOT="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/projects/defaultprojects"
    WALL_DIR="$HOME/wallpapers/.wallpaper-engine"
  '';
  weNormalizeDir = ''
    normalize_dir() {
      ${pkgs.coreutils}/bin/realpath "$1" | ${pkgs.gnused}/bin/sed 's:/*$::'
    }
  '';

  # DMS paths for matugen queue and deferred capture
  dmsPackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  dmsConstants = ''
    DMS_SHELL_DIR="${dmsPackage}/share/quickshell/dms"
    DMS_STATE_DIR="$HOME/.local/state/DankMaterialShell"
    DMS_CONFIG_DIR="$HOME/.config/DankMaterialShell"
  '';

  # Shared service definition for both WE slots (a/b)
  weServiceConfig = {
    Unit = {
      Description = "Wallpaper Engine Live Wallpaper";
      After = ["hyprland-session.target"];
      PartOf = ["hyprland-session.target"];
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
in {
  programs.bash.initExtra = ''
    _wallpaper_engine_sync_complete() {
      local cur
      cur="''${COMP_WORDS[COMP_CWORD]}"
      COMPREPLY=($(compgen -W "--regen --list-subs --capture --capture-bad --help -h" -- "$cur"))
    }
    complete -F _wallpaper_engine_sync_complete wallpaper-engine-sync
  '';

  # Two identical WE services that alternate for seamless transitions.
  # When switching wallpapers, the idle slot starts first (its layer
  # surface renders on top), then the old slot is stopped — zero gap.
  systemd.user.services.linux-wallpaperengine-a = weServiceConfig;
  systemd.user.services.linux-wallpaperengine-b = weServiceConfig;

  systemd.user.services.dms.Service.ExecStartPost = "${config.home.profileDirectory}/bin/dms-restore-wallpaper";

  systemd.user.services.wallpaper-hook = {
    Unit = {
      Description = "DMS wallpaper sync hook";
      After = ["hyprland-session.target" "dms.service"];
      PartOf = ["hyprland-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/.wallpaper-hook";
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
  };

  home.packages = [
    (pkgs.writeShellScriptBin "wallpaper-engine-sync" ''
      set -euo pipefail
      shopt -s nullglob

      ${weConstants}
      CACHE_DIR="$HOME/.cache"
      LOCK_FILE="$CACHE_DIR/wallpaper-engine-sync.lock"
      WE_MANIFEST="$(dirname "$(dirname "$WE_WORKSHOP")")/appworkshop_431960.acf"
      WE_UI_LOG="$HOME/games/SteamLibrary/steamapps/common/wallpaper_engine/bin/uilog.txt"
      SUBS_VDF_GLOBS=(
        "$HOME/.local/share/Steam/userdata"/*/ugc/431960_subscriptions.vdf
        "$HOME/.steam/steam/userdata"/*/ugc/431960_subscriptions.vdf
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata"/*/ugc/431960_subscriptions.vdf
      )
      FORCE_REGEN=0
      LIST_SUBSCRIPTIONS=0
      CAPTURE_MODE=0
      CAPTURE_FILTER=""
      CAPTURE_BAD_ONLY=0

      usage() {
        cat <<'EOF'
Usage: wallpaper-engine-sync [OPTIONS] [NAME]

Options:
  --regen        Regenerate all dynamic thumbnails.
  --list-subs    Print discovered subscribed Wallpaper Engine IDs and exit.
  --capture      Interactive live-capture mode: cycles each WE wallpaper on
                 your desktop, waits for Enter, then screenshots it.
  --capture-bad  Like --capture, but only wallpapers with corrupt or missing
                 thumbnails.
  -h, --help     Show this help.

Arguments:
  NAME           Only process wallpapers matching this name (substring match).
EOF
      }

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --regen)
            FORCE_REGEN=1
            ;;
          --list-subs)
            LIST_SUBSCRIPTIONS=1
            ;;
          --capture)
            CAPTURE_MODE=1
            ;;
          --capture-bad)
            CAPTURE_MODE=1
            CAPTURE_BAD_ONLY=1
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
          *)
            CAPTURE_FILTER="$1"
            ;;
        esac
        shift
      done

      thumb_is_near_black() {
        local thumb="$1"
        [ -f "$thumb" ] || return 1
        local brightness=""
        brightness=$(${pkgs.imagemagick}/bin/magick "$thumb[0]" \
          -colorspace Gray -resize 1x1\! -depth 8 gray:- 2>/dev/null \
          | ${pkgs.coreutils}/bin/od -An -tu1 \
          | ${pkgs.gawk}/bin/awk 'NF { print $1; exit }')
        [ -n "$brightness" ] || return 1
        [ "$brightness" -le 3 ]
      }

      thumb_is_invalid() {
        local thumb="$1"
        [ ! -s "$thumb" ] && return 0
        local magic=""
        magic=$(${pkgs.coreutils}/bin/head -c2 "$thumb" \
          | ${pkgs.coreutils}/bin/od -A n -t x1 \
          | ${pkgs.coreutils}/bin/tr -d ' ')
        [ "$magic" != "ffd8" ] && return 0
        thumb_is_near_black "$thumb" && return 0
        return 1
      }

      thumb_is_low_quality() {
        local thumb="$1"
        thumb_is_invalid "$thumb" && return 0
        local size=0
        size=$(${pkgs.coreutils}/bin/stat -c%s "$thumb" 2>/dev/null || echo 0)
        [ "$size" -lt 51200 ]
      }

      SELECTOR_THUMB_DIR="$CACHE_DIR/quickshell-wallpaper-thumbs"

      selector_thumb_key() {
        local dir="$1"
        [ -f "$dir/project.json" ] || return 1
        local rel=""
        rel=$(${pkgs.jq}/bin/jq -r '
          (.preview // "") as $preview
          | (.file // "") as $file
          | (.type // "" | ascii_downcase) as $type
          | if $preview != "" then $preview
            elif $type == "video" and $file != "" then $file
            else ""
            end
        ' "$dir/project.json" 2>/dev/null || true)
        if [ -n "$rel" ]; then
          printf '%s\n' "$dir/$rel"
        else
          printf '%s\n' "$dir"
        fi
      }

      selector_thumb_path_for_dir() {
        local dir="$1"
        local key=""
        key=$(selector_thumb_key "$dir" || true)
        [ -n "$key" ] || return 1
        local hash=""
        hash=$(printf '%s' "$key" | ${pkgs.coreutils}/bin/md5sum | ${pkgs.coreutils}/bin/cut -d' ' -f1)
        printf '%s/%s.jpg\n' "$SELECTOR_THUMB_DIR" "$hash"
      }

      sync_selector_thumb_cache() {
        local dir="$1" src="$2"
        [ -f "$src" ] || return 0
        local selector_thumb=""
        selector_thumb=$(selector_thumb_path_for_dir "$dir" || true)
        [ -n "$selector_thumb" ] || return 0
        ${pkgs.coreutils}/bin/mkdir -p "$SELECTOR_THUMB_DIR"
        ${pkgs.coreutils}/bin/cp -f "$src" "$selector_thumb"
      }

      mkdir -p "$WALL_DIR" "$CACHE_DIR" "$SELECTOR_THUMB_DIR"
      exec 8>"$LOCK_FILE"
      if ! ${pkgs.util-linux}/bin/flock -n 8; then
        if [ "$CAPTURE_MODE" = "1" ]; then
          echo "Another wallpaper-engine-sync is running; waiting for it to finish..."
          ${pkgs.util-linux}/bin/flock 8
        else
          echo "wallpaper-engine-sync already running, skipping"
          exit 0
        fi
      fi

      # Interactive live-capture mode: apply each WE wallpaper, wait for
      # Enter, then screenshot the desktop at native resolution.
      if [ "$CAPTURE_MODE" = "1" ]; then

        echo "=== Interactive WE Thumbnail Capture ==="
        if [ -n "$CAPTURE_FILTER" ]; then
          echo "Filter: '$CAPTURE_FILTER'"
        elif [ "$CAPTURE_BAD_ONLY" = "1" ]; then
          echo "Mode: bad/missing thumbnails only"
        fi
        echo "Each wallpaper will be applied live. Press Enter when it looks"
        echo "good, or type 's' to skip. The screenshot replaces the thumbnail."
        echo "After you press Enter, you get 2 seconds to switch to a clean"
        echo "workspace or hide the terminal before the screenshot is taken."
        echo ""

        focused_monitor() {
          hyprctl monitors -j 2>/dev/null \
            | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true) | .name' \
            | ${pkgs.coreutils}/bin/head -n 1
        }

        capture_count=0
        captured=0
        skipped=0
        total=0
        for dir in "$WE_WORKSHOP"/*/; do
          [ -f "$dir/project.json" ] && total=$((total + 1))
        done

        for dir in "$WE_WORKSHOP"/*/; do
          [ -f "$dir/project.json" ] || continue
          capture_count=$((capture_count + 1))
          title=$(${pkgs.jq}/bin/jq -r '.title // "unknown"' "$dir/project.json")
          safe_title=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
          thumb_name="''${safe_title}.jpg"
          thumb_path="$WALL_DIR/$thumb_name"

          # Apply name filter (case-insensitive substring match)
          if [ -n "$CAPTURE_FILTER" ]; then
            title_lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')
            filter_lower=$(echo "$CAPTURE_FILTER" | tr '[:upper:]' '[:lower:]')
            if [[ "$title_lower" != *"$filter_lower"* ]] && [[ "$safe_title" != *"$filter_lower"* ]]; then
              continue
            fi
          fi

          # Apply bad-only filter
          if [ "$CAPTURE_BAD_ONLY" = "1" ] && ! thumb_is_low_quality "$thumb_path"; then
            continue
          fi

          echo "[$capture_count/$total] $title"
          if [ -s "$thumb_path" ]; then
            echo "    Current: $thumb_path"
            if thumb_is_low_quality "$thumb_path"; then
              echo "    ⚠ Bad thumbnail (corrupt or low-quality)"
            fi
          else
            echo "    No thumbnail yet"
          fi

          echo "    Applying wallpaper (waiting for WE to render)..."
          if ! wallpaper-apply dynamic "$dir" 2>&1 | sed 's/^/    /'; then
            echo "    Failed to apply wallpaper; aborting capture mode." >&2
            exit 1
          fi

          # Give WE a brief moment to render before prompting.
          sleep 1

          printf '    [Enter] capture  [s] skip  [q] quit: '
          read -r response </dev/tty
          case "$response" in
            s|S)
              echo "    Skipped."
              echo ""
              continue
              ;;
            q|Q)
              echo "    Quitting."
              break
              ;;
          esac

          echo "    Capturing in 2 seconds; switch to a clean workspace now."
          sleep 2

          tmp_capture=$(mktemp /tmp/we-capture-XXXXXX.png)
          monitor_name=$(focused_monitor || true)
          if [ -n "$monitor_name" ]; then
            ${pkgs.grim}/bin/grim -o "$monitor_name" "$tmp_capture" 2>/dev/null
          else
            ${pkgs.grim}/bin/grim "$tmp_capture" 2>/dev/null
          fi
          if [ -s "$tmp_capture" ]; then
            ${pkgs.imagemagick}/bin/magick "$tmp_capture" \
              -strip -colorspace sRGB -filter Lanczos \
              -resize 1920x1080^ -gravity center -extent 1920x1080 \
              -quality 95 "jpg:$thumb_path"
            sync_selector_thumb_cache "$dir" "$thumb_path"
            rm -f "$tmp_capture"
            echo "    ✓ Saved: $thumb_path"
            captured=$((captured + 1))
          else
            echo "    ✗ Screenshot failed"
            rm -f "$tmp_capture"
          fi
          echo ""
        done
        echo "Done! Captured $captured thumbnails."
        exit 0
      fi

      MAP_TMP=$(mktemp "$CACHE_DIR/we-wallpaper-map.json.tmp.XXXXXX")
      trap 'rm -f "$MAP_TMP"' EXIT

      echo "{" > "$MAP_TMP"
      FIRST=true
      declare -A EXPECTED_THUMBS=()
      declare -A SUBSCRIBED_IDS=()
      declare -A UNSUBSCRIBED_IDS=()
      declare -a SUBS_FILES=()

      # Render a 1920x1080 screenshot via WE's offscreen GL window
      generate_screenshot() {
        local bg_dir="$1" dst="$2"
        local attempt delay
        # Retry with increasing screenshot delay for complex scenes.
        for attempt in 1 2; do
          delay=$(( attempt == 1 ? 5 : 8 ))
          rm -f "$dst"
          ${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine \
            --assets-dir "$WE_ASSETS" \
            --window 0x0x1920x1080 \
            --screenshot "$dst" \
            --screenshot-delay "$delay" --fps 1 \
            --silent --disable-mouse \
            "$bg_dir" &>/dev/null &
          local pid=$!
          local waited=0
          local max_wait=$(( (delay + 7) * 5 ))
          while [ ! -s "$dst" ] && kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$max_wait" ]; do
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
          for _ in $(seq 1 25); do
            if ! kill -0 "$pid" 2>/dev/null; then
              break
            fi
            sleep 0.2
          done
          if kill -0 "$pid" 2>/dev/null; then
            continue
          fi
          wait "$pid" 2>/dev/null || true
          if [ -s "$dst" ]; then
            if thumb_is_near_black "$dst"; then
              rm -f "$dst"
              [ "$attempt" -eq 1 ] && echo "    Screenshot attempt $attempt produced a near-black frame, retrying..."
              continue
            fi
            return 0
          fi
          [ "$attempt" -eq 1 ] && echo "    Screenshot attempt $attempt failed, retrying with longer delay..."
        done
        return 1
      }

      normalize_thumb() {
        local src="$1" dst="$2"
        local geom w h
        geom=$(${pkgs.imagemagick}/bin/magick identify -format '%wx%h' "$src[0]" 2>/dev/null) || {
          ${pkgs.imagemagick}/bin/magick "$src" \
            -strip -colorspace sRGB -filter Lanczos \
            -resize 1920x1080^ -gravity center -extent 1920x1080 \
            -quality 92 "jpg:$dst" 2>/dev/null || true
          [ -s "$dst" ]
          return
        }
        w="''${geom%%x*}"
        h="''${geom##*x}"

        # Sources smaller than 400px (e.g., 192-250px workshop GIFs) look
        # terrible when upscaled to 1920x1080. Just convert to a clean JPEG
        # at native size — DMS scales small images smoothly via QML, and
        # matugen only needs colors.
        if [ "$w" -lt 400 ] && [ "$h" -lt 400 ]; then
          ${pkgs.imagemagick}/bin/magick "$src" \
            -strip -colorspace sRGB \
            -quality 92 "jpg:$dst" 2>/dev/null || true
          [ -s "$dst" ]
          return
        fi

        local src_ratio
        src_ratio=$(( w * 100 / (h > 0 ? h : 1) ))
        if [ "$w" -lt 640 ] || [ "$src_ratio" -lt 120 ] || [ "$src_ratio" -gt 230 ]; then
          ${pkgs.imagemagick}/bin/magick "$src" \
            -strip -colorspace sRGB \
            \( +clone -filter Gaussian -resize 1920x1080! -blur 0x20 \) \
            +swap -gravity center -filter Lanczos \
            -resize 1920x1080 -composite \
            -quality 92 "jpg:$dst" 2>/dev/null || true
        else
          ${pkgs.imagemagick}/bin/magick "$src" \
            -strip -colorspace sRGB -filter Lanczos \
            -resize 1920x1080^ -gravity center -extent 1920x1080 \
            -quality 92 "jpg:$dst" 2>/dev/null || true
        fi
        [ -s "$dst" ]
      }

      # For video projects, extract the true middle frame from the actual
      # project media file referenced in project.json.
      generate_thumb_from_project_video() {
        local dir="$1" dst="$2"
        local rel_video
        rel_video=$(${pkgs.jq}/bin/jq -r '.file // empty' "$dir/project.json")
        [ -z "$rel_video" ] && return 1

        local video_path="$dir/$rel_video"
        [ -f "$video_path" ] || return 1

        ${pkgs.ffmpegthumbnailer}/bin/ffmpegthumbnailer \
          -i "$video_path" \
          -o "$dst" \
          -s 1920 \
          -t 50 \
          -q 10 >/dev/null 2>&1 || true

        [ -s "$dst" ] || return 1
        normalize_thumb "$dst" "$dst"
      }

      resolve_preview_source() {
        local dir="$1"
        local declared=""
        declared=$(${pkgs.jq}/bin/jq -r '.preview // empty' "$dir/project.json" 2>/dev/null || true)
        if [ -n "$declared" ] && [ -f "$dir/$declared" ]; then
          printf '%s\n' "$dir/$declared"
          return 0
        fi

        local candidate=""
        for candidate in \
          "$dir/preview.jpg" \
          "$dir/preview.png" \
          "$dir/preview.webp" \
          "$dir/preview.bmp" \
          "$dir/preview.gif" \
          "$dir/thumbnail.jpg" \
          "$dir/thumbnail.png" \
          "$dir/thumbnail.webp"; do
          if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done

        return 1
      }

      preview_source_geometry() {
        local src="$1"
        ${pkgs.imagemagick}/bin/magick identify -format '%wx%h' "$src[0]" 2>/dev/null
      }

      preview_source_is_low_confidence() {
        local dir="$1"
        local src=""
        src=$(resolve_preview_source "$dir" || true)
        [ -n "$src" ] || return 1

        local geom=""
        geom=$(preview_source_geometry "$src" || true)
        [ -n "$geom" ] || return 1

        local w="''${geom%%x*}"
        local h="''${geom##*x}"
        local src_ratio=$(( w * 100 / (h > 0 ? h : 1) ))

        [ "$w" -lt 640 ] || [ "$h" -lt 360 ] || [ "$src_ratio" -lt 120 ] || [ "$src_ratio" -gt 230 ]
      }

      # Extract a usable still from a GIF: flatten onto black to eliminate
      # transparency artifacts, then pick the middle frame.
      flatten_gif_frame() {
        local src="$1" dst="$2"

        local nframes
        nframes=$(${pkgs.imagemagick}/bin/magick identify "$src" 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)
        [ -n "$nframes" ] && [ "$nframes" -gt 0 ] || return 1

        local mid_idx=$(( nframes / 2 ))
        ${pkgs.imagemagick}/bin/magick "$src[$mid_idx]" \
          -background black -flatten \
          -strip -colorspace sRGB \
          -quality 95 "$dst" 2>/dev/null || return 1
        [ -s "$dst" ]
      }

      # Use Wallpaper Engine authored preview assets when they look trustworthy.
      # Tiny/square previews (like some workshop GIFs) are treated as low
      # confidence so we can try a proper WE render first and fall back cleanly.
      generate_thumb_from_preview() {
        local dir="$1" dst="$2"
        local src=""
        src=$(resolve_preview_source "$dir" || true)

        if [ -n "$src" ]; then
          if [[ "$src" == *.gif ]]; then
            local flat_tmp=""
            flat_tmp=$(${pkgs.coreutils}/bin/mktemp /tmp/we-flat-XXXXXX.jpg)
            if flatten_gif_frame "$src" "$flat_tmp"; then
              normalize_thumb "$flat_tmp" "$dst"
              local rc=$?
              rm -f "$flat_tmp"
              [ "$rc" -eq 0 ] && return 0
            fi
            rm -f "$flat_tmp"
          else
            normalize_thumb "$src" "$dst" && return 0
          fi
        fi

        local movie=""
        [ -f "$dir/preview_movie.mp4" ] && movie="$dir/preview_movie.mp4"
        [ -z "$movie" ] && [ -f "$dir/preview_movie.webm" ] && movie="$dir/preview_movie.webm"
        if [ -n "$movie" ]; then
          ${pkgs.ffmpegthumbnailer}/bin/ffmpegthumbnailer \
            -i "$movie" \
            -o "$dst" \
            -s 1920 \
            -t 50 \
            -q 10 >/dev/null 2>&1 || true

          [ -s "$dst" ] && normalize_thumb "$dst" "$dst" && return 0
        fi

        return 1
      }

      load_subscribed_ids_from_file() {
        local subs_file="$1"
        while IFS= read -r wid; do
          [ -n "$wid" ] || continue
          SUBSCRIBED_IDS["$wid"]=1
        done < <(${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*"publishedfileid"[[:space:]]*"\([0-9]\+\)".*$/\1/p' "$subs_file")
      }

      # Wallpaper Engine's own log is usually the freshest unsubscribe signal
      # when Steam metadata lags behind.
      load_unsubscribed_ids_from_uilog() {
        local log_file="$1"
        local line wid
        [ -f "$log_file" ] || return 0

        while IFS= read -r line; do
          if [[ "$line" =~ Unsubscribed[[:space:]]+from[[:space:]]+file[[:space:]]+([0-9]+) ]]; then
            wid="''${BASH_REMATCH[1]}"
            UNSUBSCRIBED_IDS["$wid"]=1
            continue
          fi
          if [[ "$line" =~ Subscribed[[:space:]]+to[[:space:]]+file[[:space:]]+([0-9]+) ]]; then
            wid="''${BASH_REMATCH[1]}"
            unset "UNSUBSCRIBED_IDS[$wid]"
          fi
        done < "$log_file"
      }

      # Fallback: Workshop manifest from the active Steam library.
      load_subscribed_ids_from_manifest() {
        local manifest="$1"
        [ -f "$manifest" ] || return 0

        local in_items=0
        local depth=0
        local line trimmed wid

        while IFS= read -r line; do
          trimmed=$(echo "$line" | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

          if [ "$in_items" -eq 0 ]; then
            if [ "$trimmed" = '"WorkshopItemsInstalled"' ]; then
              in_items=1
              depth=0
            fi
            continue
          fi

          if [ "$trimmed" = "{" ]; then
            depth=$((depth + 1))
            continue
          fi

          if [ "$trimmed" = "}" ]; then
            depth=$((depth - 1))
            if [ "$depth" -le 0 ]; then
              break
            fi
            continue
          fi

          if [ "$depth" -eq 1 ]; then
            wid=$(echo "$trimmed" | ${pkgs.gnused}/bin/sed -n 's/^"\([0-9]\{6,\}\)"$/\1/p')
            if [ -n "$wid" ]; then
              SUBSCRIBED_IDS["$wid"]=1
            fi
          fi
        done < "$manifest"
      }

      collect_subscription_sources() {
        local pattern
        local file
        SUBS_FILES=()
        for pattern in "''${SUBS_VDF_GLOBS[@]}"; do
          for file in $pattern; do
            [ -f "$file" ] || continue
            SUBS_FILES+=("$file")
          done
        done

        if [ "''${#SUBS_FILES[@]}" -gt 0 ]; then
          mapfile -t SUBS_FILES < <(printf '%s\n' "''${SUBS_FILES[@]}" | ${pkgs.coreutils}/bin/sort -u)
        fi
      }

      # Process a single wallpaper directory
      process_dir() {
        local dir="$1"
        [ -d "$dir" ] || return
        local dir_id
        dir_id=$(basename "$dir")
        if [[ "$dir_id" =~ ^[0-9]+$ ]]; then
          # Strict filtering: only subscribed Workshop IDs should ever appear.
          if [ "''${#SUBSCRIBED_IDS[@]}" -eq 0 ] || [ -z "''${SUBSCRIBED_IDS[$dir_id]+x}" ]; then
            return
          fi
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
        PROJECT_TYPE=$(${pkgs.jq}/bin/jq -r '.type // ""' "$dir/project.json" | tr '[:upper:]' '[:lower:]')

        if thumb_is_invalid "$THUMB_PATH" || [ "$FORCE_REGEN" = "1" ]; then
          local render_target=""
          local render_source=""
          local preview_low_confidence=0
          render_target=$(${pkgs.coreutils}/bin/mktemp "$CACHE_DIR/we-thumb.XXXXXX.jpg")
          rm -f "$render_target"
          echo "  Rendering: $SAFE_TITLE..."
          if preview_source_is_low_confidence "$dir"; then
            preview_low_confidence=1
          fi
          if [ "$PROJECT_TYPE" = "video" ]; then
            if generate_thumb_from_project_video "$dir" "$render_target"; then
              render_source="project video middle frame"
            else
              echo "    -> project video extraction failed, trying preview assets"
              if generate_thumb_from_preview "$dir" "$render_target"; then
                render_source="preview asset"
              else
                echo "    -> preview assets unavailable, trying offscreen WE render"
                if generate_screenshot "$dir" "$render_target"; then
                  render_source="offscreen WE render"
                fi
              fi
            fi
          else
            if [ "$preview_low_confidence" -eq 1 ]; then
              echo "    -> preview asset is low confidence, trying offscreen WE render first"
              if generate_screenshot "$dir" "$render_target"; then
                render_source="offscreen WE render"
              elif generate_thumb_from_preview "$dir" "$render_target"; then
                render_source="preview asset"
              fi
            else
              if generate_thumb_from_preview "$dir" "$render_target"; then
                render_source="preview asset"
              else
                echo "    -> preview assets unavailable, trying offscreen WE render"
                if generate_screenshot "$dir" "$render_target"; then
                  render_source="offscreen WE render"
                fi
              fi
            fi
          fi

          if [ -n "$render_source" ] && [ -s "$render_target" ]; then
            mv -f "$render_target" "$THUMB_PATH"
            echo "    -> $render_source"
          else
            rm -f "$render_target"
            if [ -s "$THUMB_PATH" ] && ! thumb_is_invalid "$THUMB_PATH"; then
              echo "    -> keeping existing thumbnail (refresh failed)"
            else
              rm -f "$THUMB_PATH"
              echo "    -> failed to generate thumbnail" >&2
              return
            fi
          fi
        fi

        if [ -s "$THUMB_PATH" ]; then
          sync_selector_thumb_cache "$dir" "$THUMB_PATH"
        fi

        if [ "$FIRST" = true ]; then
          FIRST=false
        else
          echo "," >> "$MAP_TMP"
        fi
        printf '  "%s": "%s"' "$THUMB_NAME" "$dir" >> "$MAP_TMP"
      }

      # Read currently subscribed Workshop IDs so stale leftover directories
      # from unsubscribed wallpapers are ignored.
      collect_subscription_sources
      if [ "''${#SUBS_FILES[@]}" -gt 0 ]; then
        for subs_file in "''${SUBS_FILES[@]}"; do
          load_subscribed_ids_from_file "$subs_file"
        done
      fi

      if [ "''${#SUBSCRIBED_IDS[@]}" -eq 0 ]; then
        load_subscribed_ids_from_manifest "$WE_MANIFEST"
      fi

      load_unsubscribed_ids_from_uilog "$WE_UI_LOG"
      if [ "''${#UNSUBSCRIBED_IDS[@]}" -gt 0 ]; then
        for wid in "''${!UNSUBSCRIBED_IDS[@]}"; do
          unset "SUBSCRIBED_IDS[$wid]"
        done
      fi

      if [ "$LIST_SUBSCRIPTIONS" = "1" ]; then
        if [ "''${#SUBS_FILES[@]}" -gt 0 ]; then
          echo "Subscription sources:"
          printf '  %s\n' "''${SUBS_FILES[@]}"
        else
          echo "Subscription sources: none (using manifest fallback if available)"
        fi

        if [ "''${#UNSUBSCRIBED_IDS[@]}" -gt 0 ]; then
          echo "Excluded IDs from Wallpaper Engine unsubscribe log (''${#UNSUBSCRIBED_IDS[@]}):"
          printf '%s\n' "''${!UNSUBSCRIBED_IDS[@]}" | ${pkgs.coreutils}/bin/sort -n
        fi

        if [ "''${#SUBSCRIBED_IDS[@]}" -eq 0 ]; then
          echo "No subscribed Wallpaper Engine IDs discovered."
        else
          echo "Subscribed Wallpaper Engine IDs (''${#SUBSCRIBED_IDS[@]}):"
          printf '%s\n' "''${!SUBSCRIBED_IDS[@]}" | ${pkgs.coreutils}/bin/sort -n
        fi
        exit 0
      fi

      if [ "''${#SUBSCRIBED_IDS[@]}" -eq 0 ]; then
        echo "Warning: no subscription IDs discovered; skipping dynamic workshop wallpapers." >&2
      fi

      # Scan workshop subscriptions
      for dir in "$WE_WORKSHOP"/*/; do
        process_dir "$dir"
      done

      echo "" >> "$MAP_TMP"
      echo "}" >> "$MAP_TMP"

      if ! ${pkgs.jq}/bin/jq empty "$MAP_TMP" >/dev/null 2>&1; then
        echo "Failed to build valid wallpaper map"
        exit 1
      fi

      mv "$MAP_TMP" "$MAP_FILE"
      trap - EXIT

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

    (pkgs.writeShellScriptBin ".wallpaper-hook" ''
      LOCKFILE="''${XDG_RUNTIME_DIR:-/tmp}/wallpaper-hook.lock"
      exec 9>"$LOCKFILE"
      if ! ${pkgs.util-linux}/bin/flock -n 9; then
        exit 1
      fi

      ${weConstants}
      ${weNormalizeDir}
      ${dmsConstants}
      CACHE_WALL="$HOME/.cache/current_wallpaper"
      FALLBACK_CACHE="$HOME/.cache/quickshell-last-wallpaper"
      WE_WORKSHOP_ROOT="$WE_WORKSHOP"
      USB_LIGHT_MODE_FLAG="$HOME/.config/system-manifest/usb-light-mode-enabled"
      NORMAL_POLL_INTERVAL=2
      LIGHT_MODE_POLL_INTERVAL=8

      cleanup() {
        stop_all_we
        rm -f "$LOCKFILE"
      }
      trap cleanup EXIT SIGTERM

      # Wait for environment
      until hyprctl monitors &>/dev/null; do sleep 1; done
      sleep 1
      until dms ipc wallpaper get &>/dev/null; do sleep 0.5; done

      CURRENT_WALL=""
      LAST_COLORS_HASH=""
      LAST_VESKTOP_PALETTE_HASH=""
      LAST_POWER_PROFILE=""

      update_themes() {
        local color_file="$HOME/.config/hypr/dms/colors.conf"
        local palette_json="$HOME/.cache/DankMaterialShell/dms-colors.json"

        if [ -f "$color_file" ]; then
          local current_hash=$(${pkgs.coreutils}/bin/md5sum "$color_file" | cut -d' ' -f1)
          if [ "$current_hash" != "$LAST_COLORS_HASH" ]; then
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
          fi
        fi

        # Keep Transluence-derived Vesktop theme synchronized with the same
        # palette artifact it actually consumes, not just colors.conf.
        if command -v regen-vesktop-transluence-theme >/dev/null 2>&1 && [ -f "$palette_json" ]; then
          local current_palette_hash=$(${pkgs.coreutils}/bin/md5sum "$palette_json" | cut -d' ' -f1)
          if [ "$current_palette_hash" != "$LAST_VESKTOP_PALETTE_HASH" ]; then
            if regen-vesktop-transluence-theme; then
              LAST_VESKTOP_PALETTE_HASH=$(${pkgs.coreutils}/bin/md5sum "$palette_json" | cut -d' ' -f1)
            fi
          fi
        fi
      }

      resolve_direct_we_dir() {
        local candidate="$1"
        [ -d "$candidate" ] || return 1
        [ -f "$candidate/project.json" ] || return 1
        local normalized
        normalized=$(normalize_dir "$candidate" 2>/dev/null || true)
        [ -n "$normalized" ] || return 1
        case "$normalized" in
          "$WE_WORKSHOP_ROOT"/*|"$WE_DEFAULTS_ROOT"/*)
            echo "$normalized"
            return 0
            ;;
        esac
        return 1
      }

      resolve_we_dir() {
        local wall_path="$1"

        local direct_dir=""
        direct_dir=$(resolve_direct_we_dir "$wall_path" || true)
        if [ -n "$direct_dir" ]; then
          echo "$direct_dir"
          return 0
        fi

        [ ! -f "$MAP_FILE" ] && return 1
        local bname
        bname=$(basename "$wall_path")
        local we_dir
        we_dir=$(${pkgs.jq}/bin/jq -r --arg k "$bname" '.[$k] // empty' "$MAP_FILE")
        if [ -n "$we_dir" ]; then
          local normalized
          normalized=$(normalize_dir "$we_dir" 2>/dev/null || true)
          if [ -n "$normalized" ]; then
            echo "$normalized"
            return 0
          fi
          echo "$we_dir"
          return 0
        fi
        return 1
      }

      resolve_we_dir_with_refresh() {
        local wall_path="$1"
        local resolved=""

        resolved=$(resolve_we_dir "$wall_path" || true)
        if [ -n "$resolved" ]; then
          echo "$resolved"
          return 0
        fi

        # Mapping can get stale/corrupted after interrupted sessions.
        # If current wallpaper comes from the synced folder, refresh once.
        if [ -f "$wall_path" ] && [ "''${wall_path#$HOME/wallpapers/.wallpaper-engine/}" != "$wall_path" ]; then
          wallpaper-engine-sync &>/dev/null || true
          resolved=$(resolve_we_dir "$wall_path" || true)
          if [ -n "$resolved" ]; then
            echo "$resolved"
            return 0
          fi
        fi

        return 1
      }

      current_we_dir() {
        local current_target=""
        current_target=$(systemctl --user show-environment 2>/dev/null \
          | grep '^WE_WALLPAPER_DIR=' | cut -d= -f2- || true)
        if [ -n "$current_target" ]; then
          current_target=$(normalize_dir "$current_target" 2>/dev/null || printf '%s\n' "$current_target")
        fi
        printf '%s\n' "$current_target"
      }

      publish_dms_wallpaper() {
        local image_path="$1"
        [ -n "$image_path" ] || return 1
        [ -f "$image_path" ] || return 1
        dms ipc wallpaper set "$image_path"
      }

      lookup_thumb_by_dir() {
        local dir="$1"
        [ -f "$MAP_FILE" ] || return 1
        ${pkgs.jq}/bin/jq -r --arg dir "$dir" '
            to_entries[]
            | select((.value | sub("/$"; "")) == $dir)
            | .key
        ' "$MAP_FILE" | ${pkgs.coreutils}/bin/head -n 1
      }

      lookup_thumb_by_id() {
        local wid="$1"
        [ -f "$MAP_FILE" ] || return 1
        ${pkgs.jq}/bin/jq -r --arg wid "$wid" '
            to_entries[]
            | select((.value | sub("/$"; "") | split("/") | last) == $wid)
            | .key
        ' "$MAP_FILE" | ${pkgs.coreutils}/bin/head -n 1
      }

      # Look up the generated thumbnail for a WE directory and publish it
      # as DMS wallpaper. This advances SessionData.wallpaperPath and
      # triggers full DMS theme generation.
      publish_we_thumbnail() {
        local we_dir="$1"
        local map_file="$MAP_FILE"
        local thumb_dir="$WALL_DIR"

        local thumb_name=""
        thumb_name=$(lookup_thumb_by_dir "$we_dir" || true)
        if [ -z "$thumb_name" ]; then
          local workshop_id=""
          workshop_id=$(basename "$we_dir")
          thumb_name=$(lookup_thumb_by_id "$workshop_id" || true)
        fi

        local thumb_path=""
        if [ -n "$thumb_name" ]; then
          thumb_path="$thumb_dir/$thumb_name"
        fi

        if [ -n "$thumb_path" ] && [ -f "$thumb_path" ]; then
          publish_dms_wallpaper "$thumb_path"
          return $?
        fi

        # No thumbnail — try the author's preview.jpg directly
        local preview="$we_dir/preview.jpg"
        if [ -f "$preview" ]; then
          publish_dms_wallpaper "$preview"
          return $?
        fi
        return 1
      }

      WE_SLOT_FILE="$HOME/.cache/we-active-slot"

      # Start WE on the idle slot; once it renders, stop the old slot.
      swap_we_service() {
        local new_dir="$1" assets_dir="$2"
        local current_slot
        current_slot=$(cat "$WE_SLOT_FILE" 2>/dev/null || echo "a")
        local next_slot="b"
        [ "$current_slot" = "b" ] && next_slot="a"

        systemctl --user set-environment \
          WE_WALLPAPER_DIR="$new_dir" \
          WE_ASSETS_DIR="$assets_dir"
        systemctl --user start "linux-wallpaperengine-''${next_slot}.service"
        sleep 2
        systemctl --user stop "linux-wallpaperengine-''${current_slot}.service" 2>/dev/null || true
        echo "$next_slot" > "$WE_SLOT_FILE"
      }

      stop_all_we() {
        systemctl --user stop linux-wallpaperengine-a.service 2>/dev/null || true
        systemctl --user stop linux-wallpaperengine-b.service 2>/dev/null || true
        rm -f "$WE_SLOT_FILE"
      }

      # Check if either WE slot is active
      we_is_active() {
        local a b
        a=$(systemctl --user is-active linux-wallpaperengine-a.service 2>/dev/null || true)
        b=$(systemctl --user is-active linux-wallpaperengine-b.service 2>/dev/null || true)
        [ "$a" = "active" ] || [ "$a" = "activating" ] || \
        [ "$b" = "active" ] || [ "$b" = "activating" ]
      }

      usb_light_mode_enabled() {
        [ -f "$USB_LIGHT_MODE_FLAG" ]
      }

      current_power_profile() {
        if ! usb_light_mode_enabled; then
          printf 'balanced\n'
          return 0
        fi

        local profile=""
        profile="$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || true)"
        case "$profile" in
          power-saver|balanced|performance)
            printf '%s\n' "$profile"
            ;;
          *)
            printf 'balanced\n'
            ;;
        esac
      }

      current_poll_interval() {
        if usb_light_mode_enabled && [ "$LAST_POWER_PROFILE" = "power-saver" ]; then
          printf '%s\n' "$LIGHT_MODE_POLL_INTERVAL"
        else
          printf '%s\n' "$NORMAL_POLL_INTERVAL"
        fi
      }

      apply_we_policy() {
        local requested_dir="$1"
        local normalized_dir=""
        local current_target=""

        [ -n "$requested_dir" ] || return 1
        normalized_dir=$(normalize_dir "$requested_dir" 2>/dev/null || printf '%s\n' "$requested_dir")
        publish_we_thumbnail "$normalized_dir" || true

        if usb_light_mode_enabled && [ "$LAST_POWER_PROFILE" = "power-saver" ]; then
          echo "USB light mode active: keeping static preview for $normalized_dir"
          stop_all_we
          return 0
        fi

        current_target=$(current_we_dir)
        if [ "$current_target" = "$normalized_dir" ] && we_is_active; then
          echo "Wallpaper Engine already running: $normalized_dir (skipped restart)"
          return 0
        fi

        echo "Wallpaper Engine: $normalized_dir"
        swap_we_service "$normalized_dir" "$WE_ASSETS"
      }

      handle_power_profile_change() {
        local profile="$1"
        local previous="$LAST_POWER_PROFILE"
        local target_wall=""
        local target_we_dir=""

        usb_light_mode_enabled || return 0
        [ "$profile" = "$LAST_POWER_PROFILE" ] && return 0
        LAST_POWER_PROFILE="$profile"

        echo "USB light mode profile: ${previous:-unset} -> $profile"

        target_wall="$CURRENT_WALL"
        if [ -z "$target_wall" ]; then
          target_wall=$(dms ipc wallpaper get 2>/dev/null || true)
        fi
        if [ -n "$target_wall" ]; then
          target_we_dir=$(resolve_we_dir_with_refresh "$target_wall" || true)
        fi

        if [ "$profile" = "power-saver" ]; then
          if [ -n "$target_we_dir" ]; then
            publish_we_thumbnail "$target_we_dir" || true
          fi
          stop_all_we
          return 0
        fi

        if [ -n "$target_we_dir" ]; then
          apply_we_policy "$target_we_dir"
        fi
      }

      # Ensure WE wallpaper map is fresh before first poll
      wallpaper-engine-sync &>/dev/null || true

      # Initial theme update on startup
      update_themes
      LAST_POWER_PROFILE=$(current_power_profile)

      # If DMS restored a static wallpaper, stop WE immediately so Hyprland
      # does not keep probing a crashed renderer and showing ANR popups.
      # If the cached wallpaper is a WE directory, start WE and capture live.
      initial_wall=$(dms ipc wallpaper get 2>/dev/null || true)
      boot_cache=""
      if [ -s "$CACHE_WALL" ]; then
        boot_cache=$(cat "$CACHE_WALL")
      fi
      fallback_wall=""
      if [ -s "$FALLBACK_CACHE" ]; then
        fallback_wall=$(cat "$FALLBACK_CACHE")
      fi

      # Check if boot cache points to a WE directory (new persistence format)
      boot_we_dir=""
      if [ -n "$fallback_wall" ]; then
        boot_we_dir=$(resolve_direct_we_dir "$fallback_wall" || true)
      fi
      if [ -z "$boot_we_dir" ] && [ -n "$boot_cache" ] && [ -d "$boot_cache" ] && [ -f "$boot_cache/project.json" ]; then
        boot_we_dir=$(normalize_dir "$boot_cache" 2>/dev/null || true)
      fi

      if [ -n "$boot_we_dir" ]; then
        # Boot restore: start WE on first slot and set thumbnail as DMS wallpaper
        echo "Boot restore: WE directory $boot_we_dir"
        apply_we_policy "$boot_we_dir"
      elif [ -n "$initial_wall" ]; then
        initial_we_dir=$(resolve_we_dir_with_refresh "$initial_wall" || true)
        if [ -n "$initial_we_dir" ]; then
          apply_we_policy "$initial_we_dir"
        else
          stop_all_we
        fi
      fi

      while true; do
        handle_power_profile_change "$(current_power_profile)"
        NEW_WALL=$(dms ipc wallpaper get 2>/dev/null)

        if [ -n "$NEW_WALL" ] && [ "$NEW_WALL" != "$CURRENT_WALL" ]; then
          CURRENT_WALL="$NEW_WALL"
          echo "$CURRENT_WALL" > "$CACHE_WALL"

          WE_DIR=$(resolve_we_dir_with_refresh "$NEW_WALL" || true)

          if [ -n "$WE_DIR" ]; then
            apply_we_policy "$WE_DIR"
          else
            # Static wallpaper — DMS renders it natively, just stop WE
            echo "Static wallpaper: $NEW_WALL"
            stop_all_we
          fi

        fi

        # Static wallpapers can lag behind the wallpaper-path change, so keep
        # polling Matugen output independently and let the color hash gate
        # skip no-op work once the new palette lands.
        update_themes
        sleep "$(current_poll_interval)"
      done
    '')

    (pkgs.writeShellScriptBin "dms-restore-wallpaper" ''
      set -eu

      CACHE_WALL="$HOME/.cache/current_wallpaper"
      FALLBACK_CACHE="$HOME/.cache/quickshell-last-wallpaper"

      for _ in $(seq 1 60); do
        if dms ipc wallpaper get >/dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      wall=""
      if [ -s "$CACHE_WALL" ]; then
        wall=$(cat "$CACHE_WALL")
      elif [ -s "$FALLBACK_CACHE" ]; then
        wall=$(cat "$FALLBACK_CACHE")
      fi

      # If the cached path is a WE directory, skip DMS restore — the
      # wallpaper-hook will handle WE startup and deferred capture.
      if [ -n "$wall" ] && [ -d "$wall" ]; then
        exit 0
      fi

      if [ -z "$wall" ] || [ ! -f "$wall" ]; then
        exit 0
      fi

      current=$(dms ipc wallpaper get 2>/dev/null || true)
      if [ "$current" = "$wall" ]; then
        exit 0
      fi

      for _ in $(seq 1 20); do
        dms ipc wallpaper set "$wall" >/dev/null 2>&1 || true
        sleep 0.5
        current=$(dms ipc wallpaper get 2>/dev/null || true)
        if [ "$current" = "$wall" ]; then
          exit 0
        fi
      done

      echo "dms-restore-wallpaper: failed to restore $wall" >&2
    '')

    (pkgs.writeShellScriptBin "wallpaper-library-sync" ''
      set -euo pipefail

      REPO_URL="''${WALLPAPER_REPO_URL:-}"
      REPO_BRANCH="''${WALLPAPER_REPO_BRANCH:-main}"
      REPO_DIR="''${WALLPAPER_REPO_DIR:-$HOME/wallpapers}"

      if [ -n "''${1:-}" ]; then
        REPO_URL="$1"
      fi

      if [ -n "$REPO_URL" ] && [ ! -d "$REPO_DIR/.git" ]; then
        mkdir -p "$(dirname "$REPO_DIR")"
        ${pkgs.git}/bin/git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
      fi

      if [ ! -d "$REPO_DIR/.git" ]; then
        echo "No git repo found at $REPO_DIR and no repo URL provided."
        echo "Usage (first run): wallpaper-library-sync git@github.com:you/wallpapers.git"
        exit 1
      fi

      if ${pkgs.git}/bin/git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
        ${pkgs.git}/bin/git -C "$REPO_DIR" fetch --depth 1 origin "$REPO_BRANCH"
        if ! ${pkgs.git}/bin/git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$REPO_BRANCH"; then
          ${pkgs.git}/bin/git -C "$REPO_DIR" checkout -b "$REPO_BRANCH" "origin/$REPO_BRANCH"
        else
          ${pkgs.git}/bin/git -C "$REPO_DIR" checkout -q "$REPO_BRANCH"
        fi
        ${pkgs.git}/bin/git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
      else
        echo "No origin remote configured at $REPO_DIR; skipping fetch/reset."
      fi

      mkdir -p "$REPO_DIR/.wallpaper-engine"
      touch "$REPO_DIR/.gitignore"
      if ! grep -qxF '.wallpaper-engine/' "$REPO_DIR/.gitignore"; then
        echo ".wallpaper-engine/" >> "$REPO_DIR/.gitignore"
        echo "Added .wallpaper-engine/ to $REPO_DIR/.gitignore"
      fi

      if ! grep -qxF '.DS_Store' "$REPO_DIR/.gitignore"; then
        echo ".DS_Store" >> "$REPO_DIR/.gitignore"
      fi
      if ! grep -qxF 'Thumbs.db' "$REPO_DIR/.gitignore"; then
        echo "Thumbs.db" >> "$REPO_DIR/.gitignore"
      fi

      echo "Synced static wallpapers repo at $REPO_DIR"
    '')
  ];
}
