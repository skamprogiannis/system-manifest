{
  pkgs,
  inputs,
  lib,
  ...
}: let
  weCommon = import ./wallpaper-common.nix {inherit pkgs;};

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

      ${weCommon.constants}
      ${weCommon.normalizeDir}

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

          local target_dir
          target_dir="$(normalize_dir "$wallpaper_dir")"

          # Resolve thumbnail for DMS/matugen color generation
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

          # Set DMS thumbnail BEFORE restarting WE. DMS is behind WE's
          # layer surface so this is invisible while WE is running.
          # When WE restarts, the brief gap reveals the correct new
          # thumbnail instead of the stale old one.
          if [ -n "$thumb_path" ] && [ -f "$thumb_path" ]; then
              dms ipc wallpaper set "$thumb_path" || true
          fi

          # Now (re)start WE with the new wallpaper directory
          systemctl --user set-environment \
              WE_WALLPAPER_DIR="$target_dir" \
              WE_ASSETS_DIR="$we_assets"
          systemctl --user restart linux-wallpaperengine.service

          if [ -n "$thumb_path" ] && [ -f "$thumb_path" ]; then
              write_last_wallpaper "$thumb_path"
          else
              echo "Warning: Could not resolve thumbnail for matugen: $wallpaper_dir" >&2
              write_last_wallpaper "$target_dir"
          fi
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

  xdg.desktopEntries.wallpaper-selector = {
    name = "Wallpaper Selector";
    comment = "Open the Quickshell Wallpaper Selector";
    exec = "wallpaper-selector";
    icon = "preferences-desktop-wallpaper";
    terminal = false;
    categories = ["Utility" "Graphics"];
  };
}
