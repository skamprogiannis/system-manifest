{
  pkgs,
  inputs,
  lib,
  hostType ? null,
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

  # DMS paths for matugen queue and screenshot — resolved at build time
  dmsPackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  dmsConstants = ''
    DMS_SHELL_DIR="${dmsPackage}/share/quickshell/dms"
    DMS_STATE_DIR="$HOME/.local/state/DankMaterialShell"
    DMS_CONFIG_DIR="$HOME/.config/DankMaterialShell"
  '';

  selectorRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.ffmpeg
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.pipewire
    pkgs.procps
    pkgs.wireplumber
    pkgs.wl-clipboard
    pkgs.xdg-utils
  ];

  wallpaperSelectorPkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "wallpaper-selector";
    version = "unstable";
    src = inputs."wallpaper-selector";
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/share/wallpaper-selector/qml"

      cp qml/Selector.qml "$out/share/wallpaper-selector/qml/Selector.qml"
      cat > "$out/share/wallpaper-selector/qml/Theme.qml" <<'EOF'
      pragma Singleton
      import QtQuick
      import Quickshell.Io
      import Qt.labs.platform

      QtObject {
          id: root
          property bool loaded: false

          property color background: "#B2111718"
          property color background90: "#E6111718"
          property color border: "#D99E60"
          property color accent: "#B27A8364"
          property color text: "#edd1bf"

          function normalizeHex6(value, fallback) {
              const pick = value && String(value).length > 0 ? String(value) : String(fallback);
              let hex = pick.replace(/^#/, "");
              if (hex.length === 8)
                  hex = hex.slice(2);
              if (/^[0-9a-fA-F]{6}$/.test(hex))
                  return "#" + hex.toLowerCase();
              return "#111718";
          }

          function parseColorVar(name, fallback) {
              let data = String(colorFile.text() || "");
              let regex = new RegExp("^\\s*\\$" + name + "\\s*=\\s*rgb\\(([0-9a-fA-F]{6,8})\\)\\s*$", "m");
              let match = data.match(regex);
              if (!match || match.length < 2)
                  return normalizeHex6(fallback, "#111718");
              return normalizeHex6("#" + match[1], fallback);
          }

          function updateFromDmsColors() {
              let surface = parseColorVar("surface", "#111718");
              let onSurface = parseColorVar("onSurface", "#edd1bf");
              let primary = parseColorVar("primary", border);
              let outline = parseColorVar("outline", primary);

              root.background = "#B2" + surface.slice(1);
              root.background90 = "#E6" + surface.slice(1);
              root.border = primary;
              root.accent = "#B2" + outline.slice(1);
              root.text = onSurface;
              root.loaded = true;
          }

          Behavior on background {
              ColorAnimation {
                  duration: root.loaded ? 800 : 0
                  easing.type: Easing.BezierSpline
                  easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
              }
          }
          Behavior on background90 {
              ColorAnimation {
                  duration: root.loaded ? 800 : 0
                  easing.type: Easing.BezierSpline
                  easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
              }
          }
          Behavior on border {
              ColorAnimation {
                  duration: root.loaded ? 800 : 0
                  easing.type: Easing.BezierSpline
                  easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
              }
          }
          Behavior on accent {
              ColorAnimation {
                  duration: root.loaded ? 800 : 0
                  easing.type: Easing.BezierSpline
                  easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
              }
          }
          Behavior on text {
              ColorAnimation {
                  duration: root.loaded ? 800 : 0
                  easing.type: Easing.BezierSpline
                  easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
              }
          }

          property string dmsColorsPath: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.config/hypr/dms/colors.conf"
          property string dmsColorsUrl: dmsColorsPath.startsWith("file://") ? dmsColorsPath : "file://" + dmsColorsPath

          property var _watcher: FileView {
              id: colorFile
              path: root.dmsColorsUrl
              blockLoading: true
              onLoaded: root.updateFromDmsColors()
              onLoadFailed: error => console.warn("Wallpaper selector theme: failed to load DMS colors:", error)
          }

          property var _timer: Timer {
              interval: 2000
              repeat: true
              running: true
              onTriggered: colorFile.reload()
              Component.onCompleted: colorFile.reload()
          }
      }
      EOF
      cp qml/shell.qml "$out/share/wallpaper-selector/qml/shell.qml"
      cp scripts/wallpaper-playlist.sh "$out/bin/wallpaper-playlist"

      cat > "$out/bin/wallpaper-apply" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      ${weConstants}
      ${weNormalizeDir}
      ${dmsConstants}

      usage() {
          cat >&2 <<'USAGE'
      Usage:
        wallpaper-apply static <wallpaper_image>
        wallpaper-apply dynamic [--hash HASH --thumb-folder PATH] <wallpaper_folder_path>
        wallpaper-apply audio mute|unmute
      USAGE
      }

      we_audio() {
          local action="''${1:-}"
          if [[ "$action" != "mute" && "$action" != "unmute" ]]; then
              echo "Usage: wallpaper-apply audio mute|unmute" >&2
              exit 1
          fi
          local WE_PID
          WE_PID=$(systemctl --user show -p MainPID --value linux-wallpaperengine.service 2>/dev/null)
          if [ -z "$WE_PID" ] || [ "$WE_PID" = "0" ]; then
              echo "Wallpaper Engine is not running"
              exit 1
          fi
          local NODE_ID
          NODE_ID=$(pw-dump 2>/dev/null | jq -r \
            --argjson pid "$WE_PID" \
            '([ .[] | select(.type == "PipeWire:Interface:Client" and .info.props."application.process.id" == $pid) | .id ]) as $cids |
             .[] | select(.type == "PipeWire:Interface:Node" and (.info.props."client.id" as $cid | $cids | contains([$cid])) and .info.props."media.class" == "Stream/Output/Audio") | .id' \
            | head -1)
          if [ -z "$NODE_ID" ]; then
              echo "No audio stream found for Wallpaper Engine (wallpaper may have no sound)"
              exit 0
          fi
          if [ "$action" = "mute" ]; then
              wpctl set-mute "$NODE_ID" 1
              echo "Wallpaper Engine audio muted (node $NODE_ID)"
          else
              wpctl set-mute "$NODE_ID" 0
              echo "Wallpaper Engine audio unmuted (node $NODE_ID)"
          fi
      }

      write_last_wallpaper() {
          local path="$1"
          printf '%s\n' "$path" > "$HOME/.cache/quickshell-last-wallpaper"
      }

      apply_static_wallpaper() {
          local wallpaper_image="''${1:-}"
          if [ -z "$wallpaper_image" ] || [ ! -f "$wallpaper_image" ]; then
              usage
              exit 1
          fi

          # Set DMS wallpaper BEFORE stopping WE so the new image is ready
          # underneath. When WE's layer surface disappears, DMS already shows
          # the correct wallpaper — no old-thumbnail flash.
          if ! dms ipc wallpaper set "$wallpaper_image"; then
              echo "Failed to apply static wallpaper via DMS: $wallpaper_image" >&2
              exit 1
          fi
          # Dismiss the Hyprland autoreload notification triggered by DMS matugen.
          (sleep 4 && hyprctl dismissnotify -1 >/dev/null 2>&1) &

          systemctl --user stop linux-wallpaperengine.service 2>/dev/null || true

          write_last_wallpaper "$wallpaper_image"
      }

      apply_dynamic_wallpaper() {
          local wallpaper_dir=""
          local map_file="$MAP_FILE"
          local thumb_dir="$WALL_DIR"
          local we_assets="$WE_ASSETS"

          while [ "$#" -gt 0 ]; do
              case "$1" in
                  --hash|--thumb-folder)
                      shift
                      [ "$#" -gt 0 ] && shift
                      ;;
                  *)
                      if [ -z "$wallpaper_dir" ]; then
                          wallpaper_dir="$1"
                      fi
                      shift
                      ;;
              esac
          done

          if [ -z "$wallpaper_dir" ] || [ ! -d "$wallpaper_dir" ]; then
              usage
              exit 1
          fi

          lookup_thumb_by_dir() {
              local dir="$1"
              [ -f "$map_file" ] || return 1
              ${pkgs.jq}/bin/jq -r --arg dir "$dir" '
                  to_entries[]
                  | select((.value | sub("/$"; "")) == $dir)
                  | .key
              ' "$map_file" | ${pkgs.coreutils}/bin/head -n 1
          }

          lookup_thumb_by_id() {
              local wid="$1"
              [ -f "$map_file" ] || return 1
              ${pkgs.jq}/bin/jq -r --arg wid "$wid" '
                  to_entries[]
                  | select((.value | sub("/$"; "") | split("/") | last) == $wid)
                  | .key
              ' "$map_file" | ${pkgs.coreutils}/bin/head -n 1
          }

          # Extract the dominant hex color from an image for matugen fallback
          extract_dominant_color() {
              local img="$1"
              ${pkgs.imagemagick}/bin/magick "$img" -resize 1x1! -format '#%[hex:u.p{0,0}]' info:- 2>/dev/null \
                | ${pkgs.gnused}/bin/sed 's/#\(......\).*/\1/' || echo ""
          }

          # Invoke matugen directly without changing the DMS wallpaper
          invoke_matugen_direct() {
              local kind="$1" value="$2"
              dms matugen queue \
                --kind "$kind" \
                --value "$value" \
                --mode dark \
                --matugen-type scheme-fidelity \
                --shell-dir "$DMS_SHELL_DIR" \
                --state-dir "$DMS_STATE_DIR" \
                --config-dir "$DMS_CONFIG_DIR" >/dev/null 2>&1 || true
              # Dismiss the Hyprland "reloaded the configuration" notification
              # that autoreload shows when matugen rewrites colors.conf.
              (sleep 2 && hyprctl dismissnotify -1 >/dev/null 2>&1) &
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
              local refresh_colors="''${2:-1}"
              [ -n "$image_path" ] || return 1
              [ -f "$image_path" ] || return 1

              dms ipc wallpaper set "$image_path" || return 1
              # DMS's own matugen triggers a Hyprland autoreload notification;
              # dismiss it after the internal generation settles.
              (sleep 4 && hyprctl dismissnotify -1 >/dev/null 2>&1) &

              if [ "$refresh_colors" = "1" ]; then
                  invoke_matugen_direct "image" "$image_path"
              fi

              return 0
          }

          local target_dir
          target_dir="$(normalize_dir "$wallpaper_dir")"

          # Resolve thumbnail for immediate matugen color generation
          local thumb_name
          thumb_name="$(lookup_thumb_by_dir "$target_dir" || true)"

          if [ -z "$thumb_name" ]; then
              wallpaper-engine-sync >/dev/null 2>&1 || true
              thumb_name="$(lookup_thumb_by_dir "$target_dir" || true)"
          fi

          if [ -z "$thumb_name" ]; then
              local workshop_id
              workshop_id="$(${pkgs.coreutils}/bin/basename "$target_dir")"
              thumb_name="$(lookup_thumb_by_id "$workshop_id" || true)"
          fi

          local thumb_path=""
          if [ -n "$thumb_name" ]; then
              thumb_path="$thumb_dir/$thumb_name"
              if [ ! -f "$thumb_path" ]; then
                  wallpaper-engine-sync --regen >/dev/null 2>&1 || true
              fi
          fi

          # Set the thumbnail as DMS wallpaper immediately — this advances
          # SessionData.wallpaperPath (Settings preview, lock screen) and
          # triggers full DMS theme generation. For video-type WE wallpapers
          # the thumbnail is a real 1080p frame and looks great.
          if [ -n "$thumb_path" ] && [ -f "$thumb_path" ]; then
              publish_dms_wallpaper "$thumb_path" "1"
          else
              # Try the author's preview.jpg as color source only
              local author_preview="$target_dir/preview.jpg"
              if [ -f "$author_preview" ]; then
                  local hex
                  hex=$(extract_dominant_color "$author_preview")
                  if [ -n "$hex" ]; then
                      invoke_matugen_direct "hex" "#$hex"
                  fi
              fi
          fi

          # Start/restart WE with the new wallpaper directory
          systemctl --user set-environment \
              WE_WALLPAPER_DIR="$target_dir" \
              WE_ASSETS_DIR="$we_assets"
          systemctl --user restart linux-wallpaperengine.service

          # Write persistence cache pointing to the WE directory so
          # wallpaper-hook can restore it on boot.
          write_last_wallpaper "$target_dir"
      }

      mode="dynamic"
      if [ "$#" -gt 0 ]; then
          case "$1" in
              static|dynamic|audio)
                  mode="$1"
                  shift
                  ;;
          esac
      fi

      case "$mode" in
          static)
              apply_static_wallpaper "''${1:-}"
              ;;
          dynamic)
              apply_dynamic_wallpaper "$@"
              ;;
          audio)
              we_audio "''${1:-}"
              ;;
          *)
              usage
              exit 1
              ;;
      esac
      EOF

      cat > "$out/bin/wallpaper-selector" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      export PATH="$HOME/.local/bin:${selectorRuntimePath}:$PATH"
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export QML_XHR_ALLOW_FILE_READ=1

      selector_path="$HOME/.config/quickshell/wallpaper"
      mode="toggle"
      if [ "$#" -gt 0 ]; then
          case "$1" in
              open|toggle)
                  mode="$1"
                  shift
                  ;;
          esac
      fi

      mapfile -t selector_pids < <(
        ${pkgs.procps}/bin/ps -u "$(id -u)" -o pid= -o args= \
          | ${pkgs.gawk}/bin/awk -v selector_path="$selector_path" '
              index($0, "quickshell") > 0 && index($0, " -p " selector_path) > 0 {
                print $1
              }
            '
      )

      if [ "$mode" = "toggle" ] && [ "''${#selector_pids[@]}" -gt 0 ]; then
          for pid in "''${selector_pids[@]}"; do
              kill "$pid" 2>/dev/null || true
          done
          exit 0
      fi

      exec ${pkgs.quickshell}/bin/quickshell -p "$selector_path"
      EOF

      chmod +x "$out/bin/"*

      runHook postInstall
    '';
  };
in {
  home.packages = [wallpaperSelectorPkg];

  # The selector stores settings relative to its QML location, so we install
  # real writable files (installer-style) instead of symlinks into /nix/store.
  home.activation.installWallpaperSelector = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/quickshell/wallpaper" "$HOME/.local/bin"

    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/share/wallpaper-selector/qml/Selector.qml" "$HOME/.config/quickshell/wallpaper/Selector.qml"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/share/wallpaper-selector/qml/Theme.qml" "$HOME/.config/quickshell/wallpaper/Theme.qml"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/share/wallpaper-selector/qml/shell.qml" "$HOME/.config/quickshell/wallpaper/shell.qml"

    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-apply" "$HOME/.local/bin/wallpaper-apply"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-playlist" "$HOME/.local/bin/wallpaper-playlist"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-selector" "$HOME/.local/bin/wallpaper-selector"

    # Cleanup stale wrappers from previous iterations.
    ${pkgs.coreutils}/bin/rm -f \
      "$HOME/.local/bin/wallpaper-selector.sh" \
      "$HOME/.local/bin/wallpaper-selector-toggle" \
      "$HOME/.local/bin/wallpaper-startup.sh" \
      "$HOME/.local/bin/wallpaper-apply.sh" \
      "$HOME/.local/bin/wallpaper-apply-static.sh" \
      "$HOME/.local/bin/wallpaper-playlist.sh"

    ${pkgs.coreutils}/bin/chmod 755 \
      "$HOME/.local/bin/wallpaper-apply" \
      "$HOME/.local/bin/wallpaper-playlist" \
      "$HOME/.local/bin/wallpaper-selector"
  '';

  xdg.desktopEntries = lib.mkIf (hostType != "usb") {
    wallpaper-selector = {
      name = "Wallpaper Selector";
      comment = "Open the Quickshell Wallpaper Selector";
      exec = "wallpaper-selector";
      icon = "preferences-desktop-wallpaper";
      terminal = false;
      categories = ["Utility" "Graphics"];
    };
  };
}
