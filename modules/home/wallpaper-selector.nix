{
  pkgs,
  inputs,
  lib,
  ...
}: let
  selectorRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.ffmpeg
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.procps
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
      cp qml/Theme.qml "$out/share/wallpaper-selector/qml/Theme.qml"
      cp qml/shell.qml "$out/share/wallpaper-selector/qml/shell.qml"
      cp scripts/wallpaper-playlist.sh "$out/bin/wallpaper-playlist.sh"

      cat > "$out/bin/wallpaper-apply" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      usage() {
          cat >&2 <<'USAGE'
      Usage:
        wallpaper-apply static <wallpaper_image>
        wallpaper-apply dynamic [--hash HASH --thumb-folder PATH] <wallpaper_folder_path>
      USAGE
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

          if ! dms ipc wallpaper set "$wallpaper_image"; then
              echo "Failed to apply static wallpaper via DMS: $wallpaper_image" >&2
              exit 1
          fi

          write_last_wallpaper "$wallpaper_image"
      }

      apply_dynamic_wallpaper() {
          local wallpaper_dir=""
          local map_file="$HOME/.cache/we-wallpaper-map.json"
          local thumb_dir="$HOME/wallpapers/.wallpaper-engine"

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

          normalize_dir() {
              ${pkgs.coreutils}/bin/realpath "$1" | ${pkgs.gnused}/bin/sed 's:/*$::'
          }

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

          local thumb_name
          thumb_name="$(lookup_thumb_by_dir "$target_dir" || true)"

          if [ -z "$thumb_name" ]; then
              if ! wallpaper-engine-sync >/dev/null 2>&1; then
                  echo "Warning: wallpaper-engine-sync refresh failed while resolving $target_dir" >&2
              fi
              thumb_name="$(lookup_thumb_by_dir "$target_dir" || true)"
          fi

          if [ -z "$thumb_name" ]; then
              local workshop_id
              workshop_id="$(${pkgs.coreutils}/bin/basename "$target_dir")"
              thumb_name="$(lookup_thumb_by_id "$workshop_id" || true)"
          fi

          if [ -z "$thumb_name" ]; then
              echo "Could not map wallpaper folder to synced thumbnail: $wallpaper_dir" >&2
              exit 1
          fi

          local thumb_path="$thumb_dir/$thumb_name"
          if [ ! -f "$thumb_path" ]; then
              if ! wallpaper-engine-sync --regen >/dev/null 2>&1; then
                  echo "Warning: wallpaper-engine-sync --regen failed for $wallpaper_dir" >&2
              fi
          fi

          if [ ! -f "$thumb_path" ]; then
              echo "Mapped thumbnail missing after sync: $thumb_path" >&2
              exit 1
          fi

          if ! dms ipc wallpaper set "$thumb_path"; then
              echo "Failed to apply wallpaper through DMS: $thumb_path" >&2
              exit 1
          fi

          write_last_wallpaper "$thumb_path"
      }

      mode="dynamic"
      if [ "$#" -gt 0 ]; then
          case "$1" in
              static|dynamic)
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
          *)
              usage
              exit 1
              ;;
      esac
      EOF

      cat > "$out/bin/wallpaper-apply-static.sh" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      exec "$HOME/.local/bin/wallpaper-apply" static "$@"
      EOF

      cat > "$out/bin/wallpaper-apply.sh" <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      exec "$HOME/.local/bin/wallpaper-apply" dynamic "$@"
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
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-apply.sh" "$HOME/.local/bin/wallpaper-apply.sh"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-apply-static.sh" "$HOME/.local/bin/wallpaper-apply-static.sh"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-playlist.sh" "$HOME/.local/bin/wallpaper-playlist.sh"
    ${pkgs.coreutils}/bin/cp -f "${wallpaperSelectorPkg}/bin/wallpaper-selector" "$HOME/.local/bin/wallpaper-selector"

    # Cleanup stale wrappers from previous iterations.
    ${pkgs.coreutils}/bin/rm -f \
      "$HOME/.local/bin/wallpaper-selector.sh" \
      "$HOME/.local/bin/wallpaper-selector-toggle" \
      "$HOME/.local/bin/wallpaper-startup.sh"

    ${pkgs.coreutils}/bin/chmod 755 \
      "$HOME/.local/bin/wallpaper-apply" \
      "$HOME/.local/bin/wallpaper-apply.sh" \
      "$HOME/.local/bin/wallpaper-apply-static.sh" \
      "$HOME/.local/bin/wallpaper-playlist.sh" \
      "$HOME/.local/bin/wallpaper-selector"
  '';

  xdg.desktopEntries.wallpaper-selector = {
    name = "Wallpaper Selector";
    comment = "Browse and apply wallpapers from your library";
    exec = "wallpaper-selector";
    icon = "preferences-desktop-wallpaper";
    terminal = false;
    categories = ["Utility" "Graphics"];
  };
}
