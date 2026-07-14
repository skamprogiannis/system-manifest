{ctx}: let
  inherit
    (ctx)
    desktopDmsSettingsFile
    desktopDmsPackage
    desktopSkwdDaemonExec
    desktopSkwdDmsScheduleHook
    desktopSkwdDmsSyncHook
    desktopSkwdPrepareStateActivationFile
    desktopTmpfilesRulesFile
    pkgs
    usbDmsPackage
    usbSkwdDaemonExec
    ;
in {
  wallpaper-runtime =
    pkgs.runCommand "wallpaper-runtime-checks" {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.imagemagick
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

            assert_not_contains() {
              local needle="$1"
              local file="$2"
              local label="$3"

              if grep -Fq "$needle" "$file"; then
                echo "Expected $label not to contain: $needle" >&2
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

            skwd_pkg="$(dirname "$(dirname "${desktopSkwdDaemonExec}")")"
            usb_skwd_pkg="$(dirname "$(dirname "${usbSkwdDaemonExec}")")"
            assert_executable "$skwd_pkg/bin/skwd" "skwd"
            assert_executable "$skwd_pkg/bin/skwd-daemon" "skwd-daemon"
            assert_executable "$skwd_pkg/bin/skwd-wall" "skwd-wall"
            assert_executable "$usb_skwd_pkg/bin/skwd" "USB skwd"
            assert_executable "$usb_skwd_pkg/bin/skwd-daemon" "USB skwd-daemon"
            assert_executable "$usb_skwd_pkg/bin/skwd-wall" "USB skwd-wall"

            for binary in skwd skwd-daemon skwd-wall; do
              assert_contains "QSG_RHI_BACKEND-'vulkan'" "$skwd_pkg/bin/$binary" "desktop $binary wrapper"
              assert_contains "QSG_RHI_BACKEND-'opengl'" "$usb_skwd_pkg/bin/$binary" "USB $binary wrapper"
              assert_not_contains "QSG_RHI_BACKEND-'vulkan'" "$usb_skwd_pkg/bin/$binary" "USB $binary wrapper"
            done

            usb_dms_session="${usbDmsPackage}/share/quickshell/dms/Common/SessionData.qml"
            usb_dms_skwd="$(sed -n 's|.*\["\(/nix/store/[^" ]*/bin/skwd\)".*|\1|p' "$usb_dms_session" | head -n1)"
            if [ -z "$usb_dms_skwd" ]; then
              echo "Expected USB DMS SessionData to reference an absolute skwd command." >&2
              exit 1
            fi
            assert_executable "$usb_dms_skwd" "USB DMS skwd command"
            assert_contains "QSG_RHI_BACKEND-'opengl'" "$usb_dms_skwd" "USB DMS skwd wrapper"
            assert_executable "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
            assert_executable "${desktopSkwdDmsScheduleHook}" "DMS wallpaper sync scheduler"
            ${pkgs.bash}/bin/bash -n "${desktopSkwdDmsSyncHook}"
            ${pkgs.bash}/bin/bash -n "${desktopSkwdDmsScheduleHook}"
            skwd_capture_still="$(sed -n 's/^[[:space:]]*export SKWD_CAPTURE_STILL_BIN="\([^"]*\)"$/\1/p' "${desktopSkwdDmsSyncHook}")"
            if [ -z "$skwd_capture_still" ]; then
              echo "Expected DMS wallpaper sync hook to export SKWD_CAPTURE_STILL_BIN." >&2
              sed 's/^/  /' "${desktopSkwdDmsSyncHook}" >&2
              exit 1
            fi
            assert_executable "$skwd_capture_still" "skwd-we-capture-still"

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

            skwd_prepare="$(sed -n 's/^run //p' ${desktopSkwdPrepareStateActivationFile})"
            skwd_defaults="$(sed -n 's/^[[:space:]]*defaults_file="\([^"]*\)"/\1/p' "$skwd_prepare")"
            if [ -z "$skwd_defaults" ]; then
              echo "Expected to find skwd-wall defaults file in prepare-state script." >&2
              sed 's/^/  /' "$skwd_prepare" >&2
              exit 1
            fi
            assert_contains "schedule-dms-wallpaper-sync.sh" "$skwd_defaults" "generated skwd-wall defaults"
            assert_not_contains '"/sync-dms-wallpaper.sh"' "$skwd_defaults" "generated skwd-wall defaults"
            assert_contains '"music":false' "$skwd_defaults" "generated skwd-wall defaults"

            assert_contains "sync-dms-wallpaper: missing both" "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
            assert_contains "should_call_dms=" "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
            assert_contains "def matches():" "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
            assert_contains '"$dms_bin" ipc wallpaper externalSet "$live_wallpaper" "$mode"' "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"
            assert_contains "dms-wallpaper-sync.request" "${desktopSkwdDmsScheduleHook}" "DMS wallpaper sync scheduler"
            assert_contains "flock -n 9" "${desktopSkwdDmsScheduleHook}" "DMS wallpaper sync scheduler"
            assert_contains "REQUEST_FILE=" "${desktopSkwdDmsScheduleHook}" "DMS wallpaper sync scheduler"
            assert_contains "skwd-we-capture-still" "$skwd_capture_still" "Wallpaper Engine capture helper"
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
            assert_contains 'Quickshell.execDetached([Config.scriptsDir + "/schedule-dms-wallpaper-sync.sh"])' "$skwd_pkg/share/skwd-wall/qml/wallpaper/WallpaperSelectorService.qml" "patched skwd-wall selector service"
            assert_contains "z /var/cache/dms-greeter 2775 root greeter - -" ${desktopTmpfilesRulesFile} "desktop tmpfiles rules"
            assert_contains "title: \"Settings controls\"" "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
            assert_contains "title: \"Tags & browsers\"" "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
            assert_contains '{ key: "Ctrl + S / H / W", action: "Switch Slices / Hex / Wall view" },' "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
            assert_contains '{ key: "B then W / S",  action: "Open Wallhaven / Steam browser" },' "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
            assert_before 'title: "Settings controls"' 'title: "Filters"' "$skwd_keybinds_qml" "patched skwd-wall keybind settings"
            assert_contains "DaemonClient.applyVideo(path, outputs, neighbors, screens, audioMap, volumeMap)" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
            assert_contains "music = false;" ${../modules/home/wallpaper/skwd-wall-state.nix} "skwd-wall declarative config"

            dms_pkg="${desktopDmsPackage}"
            assert_contains 'function externalSet(path: string, mode: string): string' "$dms_pkg/share/quickshell/dms/Common/SessionData.qml" "patched DMS SessionData"
            external_set_block="$(sed -n '/function externalSet(path: string, mode: string): string/,/function clear(): string/p' "$dms_pkg/share/quickshell/dms/Common/SessionData.qml")"
            if printf '%s\n' "$external_set_block" | grep -Fq 'root.setWallpaper(path)'; then
              echo "DMS externalSet must not call root.setWallpaper(path), because that re-enters skwd wall apply." >&2
              printf '%s\n' "$external_set_block" >&2
              exit 1
            fi
            if printf '%s\n' "$external_set_block" | grep -Fq '_skwdWallApplyProcess'; then
              echo "DMS externalSet must not launch the skwd wallpaper apply process." >&2
              printf '%s\n' "$external_set_block" >&2
              exit 1
            fi
            if ! printf '%s\n' "$external_set_block" | grep -Fq 'Theme.generateSystemThemesFromCurrentTheme();'; then
              echo "DMS externalSet must still trigger theme generation." >&2
              printf '%s\n' "$external_set_block" >&2
              exit 1
            fi
            assert_contains 'target: "wallpaper"' "$dms_pkg/share/quickshell/dms/Common/SessionData.qml" "patched DMS SessionData"

            fake_dms="$TMPDIR/fake-dms"
            cat > "$fake_dms" <<'SH'
      #!/bin/sh
      printf '%s\n' "$*" >> "$DMS_LOG"
      exit 0
      SH
            chmod +x "$fake_dms"

            sync_home="$TMPDIR/sync-home"
            sync_greeter="$TMPDIR/sync-greeter"
            sync_log="$TMPDIR/sync-dms.log"
            mkdir -p "$sync_home/.cache/skwd-wall/wallpaper" "$sync_home/.local/state/DankMaterialShell" "$sync_home/.config/skwd-wall" "$sync_greeter"
            magick -size 4x4 xc:red "$sync_home/wall.png"
            cp "$sync_home/wall.png" "$sync_home/.cache/skwd-wall/wallpaper/current.jpg"
            printf '{"path":"%s","type":"static"}\n' "$sync_home/wall.png" > "$sync_home/.cache/skwd-wall/last-wallpaper.json"
            printf '{"matugen":{"mode":"dark"}}\n' > "$sync_home/.config/skwd-wall/config.json"

            HOME="$sync_home" DMS_BIN="$fake_dms" DMS_LOG="$sync_log" DMS_GREETER_CACHE_DIR="$sync_greeter" "${desktopSkwdDmsSyncHook}"
            current_format="$(magick identify -format '%m' "$sync_home/.cache/skwd-wall/wallpaper/current.jpg")"
            if [ "$current_format" != "JPEG" ]; then
              echo "Expected sync hook to normalize current.jpg to JPEG, got $current_format" >&2
              exit 1
            fi
            assert_contains "ipc wallpaper externalSet $sync_home/wall.png dark" "$sync_log" "fake DMS IPC log"
            assert_contains "$sync_greeter/greeter_wallpaper_override.jpg" "$sync_greeter/settings.json" "fake greeter settings"

            ${pkgs.python3}/bin/python3 - "$sync_home/wall.png" "$sync_home/.local/state/DankMaterialShell/session.json" <<'PY'
      from pathlib import Path
      import json
      import sys

      wallpaper = sys.argv[1]
      session_file = Path(sys.argv[2])
      data = {
          "wallpaperPath": wallpaper,
          "wallpaperPathLight": wallpaper,
          "wallpaperPathDark": wallpaper,
          "wallpaperCyclingEnabled": False,
          "perMonitorWallpaper": False,
          "perModeWallpaper": False,
          "isLightMode": False,
          "monitorWallpapers": {},
          "monitorWallpapersLight": {},
          "monitorWallpapersDark": {},
          "monitorCyclingSettings": {},
      }
      session_file.write_text(json.dumps(data, separators=(",", ":")) + "\n")
      PY
            : > "$sync_log"
            rm -f "$sync_greeter/settings.json"
            HOME="$sync_home" DMS_BIN="$fake_dms" DMS_LOG="$sync_log" DMS_GREETER_CACHE_DIR="$sync_greeter" "${desktopSkwdDmsSyncHook}"
            if [ -s "$sync_log" ]; then
              echo "Expected sync hook to skip redundant DMS IPC when session contract already matches." >&2
              sed 's/^/  /' "$sync_log" >&2
              exit 1
            fi
            assert_contains "$sync_greeter/greeter_wallpaper_override.jpg" "$sync_greeter/settings.json" "fake greeter settings after skipped IPC"

            scheduler_home="$TMPDIR/scheduler-home"
            scheduler_greeter="$TMPDIR/scheduler-greeter"
            scheduler_runtime="$TMPDIR/scheduler-runtime"
            scheduler_log="$TMPDIR/scheduler-dms.log"
            mkdir -p "$scheduler_home/.cache/skwd-wall/wallpaper" "$scheduler_home/.local/state/DankMaterialShell" "$scheduler_home/.config/skwd-wall" "$scheduler_greeter" "$scheduler_runtime"
            magick -size 4x4 xc:blue "$scheduler_home/wall.png"
            cp "$scheduler_home/wall.png" "$scheduler_home/.cache/skwd-wall/wallpaper/current.jpg"
            printf '{"path":"%s","type":"static"}\n' "$scheduler_home/wall.png" > "$scheduler_home/.cache/skwd-wall/last-wallpaper.json"
            printf '{"matugen":{"mode":"dark"}}\n' > "$scheduler_home/.config/skwd-wall/config.json"
            HOME="$scheduler_home" XDG_RUNTIME_DIR="$scheduler_runtime" SKWD_DMS_SYNC_FOREGROUND=1 DMS_BIN="$fake_dms" DMS_LOG="$scheduler_log" DMS_GREETER_CACHE_DIR="$scheduler_greeter" "${desktopSkwdDmsScheduleHook}"
            assert_contains "ipc wallpaper externalSet $scheduler_home/wall.png dark" "$scheduler_log" "fake DMS IPC log from scheduler"

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
