{ctx}: let
  inherit
    (ctx)
    desktopDmsSettingsFile
    desktopHome
    desktopSkwdDmsSyncHook
    desktopTmpfilesRulesFile
    pkgs
    ;
in {
  wallpaper-runtime =
    pkgs.runCommand "wallpaper-runtime-checks" {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      assert_executable() {
        local path="$1"
        local label="$2"

        if [ ! -x "$path" ]; then
          echo "Expected executable $label at $path" >&2
          exit 1
        fi
      }

      assert_contains() {
        local needle="$1"
        local file="$2"
        local label="$3"

        if ! grep -Fq "$needle" "$file"; then
          echo "Expected $label to contain: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_before() {
        local first="$1"
        local second="$2"
        local file="$3"
        local label="$4"
        local first_line
        local second_line

        first_line="$(grep -nF "$first" "$file" | head -n1 | cut -d: -f1 || true)"
        second_line="$(grep -nF "$second" "$file" | head -n1 | cut -d: -f1 || true)"
        if [ -z "$first_line" ] || [ -z "$second_line" ] || [ "$first_line" -ge "$second_line" ]; then
          echo "Expected $label to contain '$first' before '$second'" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_executable "${desktopHome}/bin/skwd" "skwd"
      assert_executable "${desktopHome}/bin/skwd-daemon" "skwd-daemon"
      assert_executable "${desktopHome}/bin/skwd-wall" "skwd-wall"
      assert_executable "${desktopHome}/bin/skwd-we-capture-still" "skwd-we-capture-still"
      assert_executable "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"

      skwd_bin="$(readlink -f "${desktopHome}/bin/skwd")"
      skwd_pkg="$(dirname "$(dirname "$skwd_bin")")"
      skwd_keybinds_qml="$skwd_pkg/share/skwd-wall/qml/wallpaper/settings/KeybindsSettings.qml"
      skwd_selector_qml="$skwd_pkg/share/skwd-wall/qml/wallpaper/WallpaperSelector.qml"
      assert_executable "$skwd_pkg/libexec/skwd-wall/awww" "skwd-wall awww helper"
      assert_executable "$skwd_pkg/libexec/skwd-wall/linux-wallpaperengine" "skwd-wall Wallpaper Engine helper"
      skwd_apply_static="$(sed -n 's/^apply_static="\([^"]*\)"$/\1/p' "$skwd_pkg/libexec/skwd-wall/awww")"
      assert_executable "$skwd_apply_static" "skwd-wall static apply helper"
      assert_contains "awww query" "$skwd_apply_static" "skwd-wall static apply helper"

      if grep -Fq "pgrep -x awww-daemon" "$skwd_apply_static"; then
        echo "skwd-wall static apply helper must probe the daemon socket, not the wrapped process name." >&2
        exit 1
      fi

      assert_contains "sync-dms-wallpaper: missing both" "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
      assert_contains '"$dms_bin" ipc wallpaper externalSet "$live_wallpaper" "$mode"' "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
      assert_contains "skwd-we-capture-still" "${desktopHome}/bin/skwd-we-capture-still" "Wallpaper Engine capture helper"
      assert_contains "# selector navigation" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# filter bar keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# tag cloud keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# settings keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# keybind help" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "KeybindsSettings.qml" ${../modules/home/wallpaper/patched-package.nix} "skwd-wall patched package"
      assert_contains "H / J / K / L" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "B then W / S" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "weRender = {" ${../modules/home/wallpaper/skwd-wall-state.nix} "skwd-wall declarative config"
      assert_contains "noAudioProcessing = true;" ${../modules/home/wallpaper/skwd-wall-state.nix} "skwd-wall declarative config"
      assert_contains "disableMouse = true;" ${../modules/home/wallpaper/skwd-wall-state.nix} "skwd-wall declarative config"
      assert_contains "disableParallax = true;" ${../modules/home/wallpaper/skwd-wall-state.nix} "skwd-wall declarative config"
      assert_contains '"muxType":"zellij"' ${desktopDmsSettingsFile} "desktop DMS settings"
      assert_contains "function _toggleEffects()" "$skwd_selector_qml" "patched skwd-wall selector"
      assert_contains "onEffectsToggled: wallpaperSelector._toggleEffects()" "$skwd_selector_qml" "patched skwd-wall selector"
      assert_contains "function _scheduleDmsWallpaperSync()" "$skwd_pkg/share/skwd-wall/qml/wallpaper/WallpaperSelectorService.qml" "patched skwd-wall selector service"
      assert_contains "service._scheduleDmsWallpaperSync()" "$skwd_pkg/share/skwd-wall/qml/wallpaper/WallpaperSelectorService.qml" "patched skwd-wall selector service"
      assert_contains 'Quickshell.execDetached([Config.scriptsDir + "/sync-dms-wallpaper.sh"])' "$skwd_pkg/share/skwd-wall/qml/wallpaper/WallpaperSelectorService.qml" "patched skwd-wall selector service"
      assert_contains "z /var/cache/dms-greeter 2775 root greeter - -" ${desktopTmpfilesRulesFile} "desktop tmpfiles rules"
      assert_contains "title: \"Settings controls\"" "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
      assert_contains "title: \"Tags & browsers\"" "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
      assert_contains '{ key: "Ctrl + S / H / W", action: "Switch Slices / Hex / Wall view" },' "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
      assert_contains '{ key: "B then W / S",  action: "Open Wallhaven / Steam browser" },' "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
      assert_before 'title: "Settings controls"' 'title: "Filters"' "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
      assert_contains "DaemonClient.applyVideo(path, outputs, neighbors, screens, audioMap, volumeMap)" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"

      dms_bin="$(readlink -f "${desktopHome}/bin/dms")"
      dms_pkg="$(dirname "$(dirname "$dms_bin")")"
      assert_contains 'function externalSet(path: string, mode: string): string' "$dms_pkg/share/quickshell/dms/Common/SessionData.qml" "patched DMS SessionData"
      assert_contains 'target: "wallpaper"' "$dms_pkg/share/quickshell/dms/Common/SessionData.qml" "patched DMS SessionData"

      if grep -Fq "'} else if (event.key === Qt.Key_Right) {'," ${../modules/home/wallpaper/qml-patches.nix}; then
        echo "skwd-wall QML patch module still contains the confirmed no-op Qt.Key_Right replacement." >&2
        exit 1
      fi

      if grep -Fq "# apply-service backends" ${../modules/home/wallpaper/qml-patches.nix}; then
        echo "skwd-wall QML patch module should rely on upstream daemon-backed apply methods instead of restoring the old apply-service backend patch." >&2
        exit 1
      fi

      if grep -Fq "WallpaperApplyService" ${../modules/home/wallpaper/qml-patches.nix}; then
        echo "skwd-wall QML patch module should not reference the removed upstream WallpaperApplyService file." >&2
        exit 1
      fi

      touch "$out"
    '';
}
