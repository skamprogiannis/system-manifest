{ctx}: let
  inherit
    (ctx)
    desktopAccountsServiceAvatarScript
    desktopBraveExtensionsFile
    desktopDmsPackage
    desktopDmsLegacyProfileFile
    desktopDmsOutputsFile
    desktopGreeterPackage
    desktopGpuScreenRecorderGtkPackage
    desktopGpuScreenRecorderPackage
    desktopBravePackage
    desktopHyprlandPackage
    desktopMimeDefaultApplicationsFile
    desktopNvidiaDriverVersion
    laptopDmsOutputsFile
    pkgs
    usbDmsPackage
    usbDmsOutputsFile
    ;
  minimumCompatibleNvidiaDriver = "610";
in {
  desktop-runtime-config = assert pkgs.lib.assertMsg
  (pkgs.lib.versionOlder desktopNvidiaDriverVersion minimumCompatibleNvidiaDriver)
  ''
    GPU Screen Recorder compatibility pin review required: desktop NVIDIA
    driver ${desktopNvidiaDriverVersion} is ${minimumCompatibleNvidiaDriver}
    or newer. Retest the stock FFmpeg 9 backend with
    `gpu-screen-recorder --info`, then remove the FFmpeg 8 compatibility
    overrides and this guard. Keep the independent GTK tray icon path fix.
  '';
    pkgs.runCommand "desktop-runtime-config-checks" {
      nativeBuildInputs = [
        pkgs.binutils
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      assert_file_contains() {
        local file="$1"
        local needle="$2"
        if ! grep -Fq -- "$needle" "$file"; then
          echo "Expected $file to contain: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_file_not_contains() {
        local file="$1"
        local needle="$2"
        if grep -Fq -- "$needle" "$file"; then
          echo "$file still contains legacy text: $needle" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      assert_elf_needs() {
        local file="$1"
        local library="$2"
        if ! readelf -d "$file" | grep -Fq "Shared library: [$library]"; then
          echo "Expected $file to require: $library" >&2
          readelf -d "$file" | grep -F 'Shared library:' >&2
          exit 1
        fi
      }

      assert_file_contains ${desktopHyprlandPackage}/bin/Hyprland '--config'
      assert_file_contains ${desktopHyprlandPackage}/bin/Hyprland 'hyprland.lua'
      assert_file_contains ${desktopHyprlandPackage}/bin/start-hyprland '/bin/start-hyprland --path'
      assert_file_contains ${desktopHyprlandPackage}/bin/start-hyprland '/bin/Hyprland" "$@"'
      assert_file_not_contains ${desktopBravePackage}/bin/brave '--test-type'
      assert_file_contains ${desktopBravePackage}/bin/brave '--user-data-dir=/home/stefan/.config/BraveSoftware/Brave-Browser'
      assert_file_contains ${desktopBraveExtensionsFile} 'bkkmolkhemgaeaeggcmfbghljjjoofoh'
      assert_elf_needs ${desktopGpuScreenRecorderPackage}/bin/.wrapped/gpu-screen-recorder 'libavcodec.so.62'
      assert_file_contains ${desktopGpuScreenRecorderGtkPackage}/bin/gpu-screen-recorder-gtk '${desktopGpuScreenRecorderPackage}/bin'
      for state in idle recording paused; do
        recorder_icon="/share/icons/hicolor/32x32/status/com.dec05eba.gpu_screen_recorder.tray-$state.png"
        test -s "${desktopGpuScreenRecorderGtkPackage}$recorder_icon"
        assert_file_contains ${desktopGpuScreenRecorderGtkPackage}/bin/.gpu-screen-recorder-gtk-wrapped "${desktopGpuScreenRecorderGtkPackage}$recorder_icon"
        assert_file_not_contains ${desktopGpuScreenRecorderGtkPackage}/bin/.gpu-screen-recorder-gtk-wrapped "/usr$recorder_icon"
      done
      assert_file_contains ${desktopMimeDefaultApplicationsFile} '"x-scheme-handler/magnet":["torrent-add.desktop"]'
      assert_file_contains ${desktopMimeDefaultApplicationsFile} '"application/x-bittorrent":["torrent-add.desktop"]'
      test -x ${desktopGreeterPackage}/bin/dms-greeter
      assert_file_not_contains ${desktopDmsPackage}/share/quickshell/dms/Modals/DankLauncherV2/DankLauncherV2ModalHost.qml 'sourceRect.antialiasing'
      assert_file_not_contains ${desktopDmsPackage}/share/quickshell/dms/Modals/DankLauncherV2/DankLauncherV2ModalHost.qml 'sourceRect.smooth'
      assert_file_contains ${desktopDmsPackage}/share/quickshell/dms/Modules/DankBar/Widgets/Clock.qml 'showSeconds: root.widgetData?.showSeconds !== undefined ? root.widgetData.showSeconds : SettingsData.showSeconds'
      assert_file_contains ${desktopDmsPackage}/share/quickshell/dms/Widgets/ClockContent.qml 'SettingsData.getEffectiveTimeFormat(root.showSeconds)'
      assert_file_contains ${desktopDmsPackage}/share/quickshell/dms/Widgets/ClockContent.qml 'precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes'
      assert_file_contains ${desktopDmsPackage}/share/quickshell/dms/Modals/NotificationModal.qml 'NotificationService.clearHistory();'
      assert_file_contains ${usbDmsPackage}/share/quickshell/dms/Modules/DankBar/BarSurface.qml 'Shape.SoftwareRenderer : Shape.CurveRenderer'
      assert_file_contains ${usbDmsPackage}/share/quickshell/dms/DankCommon/Widgets/CachingImage.qml 'if (!root._cacheTarget || Quickshell.env("QT_QUICK_BACKEND") === "software")'
      assert_file_contains ${usbDmsPackage}/share/quickshell/dms/Modules/Settings/WallpaperColorsTab.qml 'Quickshell.execDetached(["skwd-wall-v2"]);'
      assert_file_not_contains ${usbDmsPackage}/share/quickshell/dms/Modules/Settings/WallpaperColorsTab.qml 'SessionData.setMaterialWallpaper'
      assert_file_not_contains ${usbDmsPackage}/share/quickshell/dms/Modules/Settings/WallpaperColorsTab.qml 'SessionData.setWallpaper('
      assert_file_not_contains ${usbDmsPackage}/share/quickshell/dms/Modules/Settings/WallpaperColorsTab.qml 'SessionData.setMonitorWallpaper('
      # Guard the packaged wake listener; real input/session-lock behavior
      # still requires a monitor-off-then-lock trial on hardware.
      lock_wake_monitor="$TMPDIR/lock-wake-monitor.qml"
      sed -n '/id: lockWakeMonitor/,/^    }/p' \
        ${desktopDmsPackage}/share/quickshell/dms/Services/IdleService.qml > "$lock_wake_monitor"
      if ! grep -Fxq '        enabled: root.enabled && root.isShellLocked && root.monitorsOff' "$lock_wake_monitor"; then
        echo "Expected locked monitor wake for every monitor-off path, including automatic idle." >&2
        cat "$lock_wake_monitor" >&2
        exit 1
      fi
      assert_file_contains "$lock_wake_monitor" 'timeout: 1'
      assert_file_contains "$lock_wake_monitor" 'respectInhibitors: false'
      assert_file_contains "$lock_wake_monitor" 'if (!isIdle && root.monitorsOff)'
      assert_file_contains "$lock_wake_monitor" 'root.requestMonitorOn();'
      for dms_package in ${desktopDmsPackage} ${usbDmsPackage}; do
        niri_service="$dms_package/share/quickshell/dms/Services/NiriService.qml"
        if ! grep -Fq 'readonly property string screenshotsDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.PicturesLocation)) + "/screenshots"' "$niri_service"; then
          echo "Expected lowercase screenshotsDir in $niri_service" >&2
          grep -n 'screenshotsDir:' "$niri_service" >&2 || true
          exit 1
        fi
        if grep -Fq '"/Screenshots"' "$niri_service"; then
          echo "Unexpected uppercase Screenshots path in $niri_service" >&2
          exit 1
        fi
      done
      assert_file_contains ${desktopAccountsServiceAvatarScript} '/var/lib/AccountsService/icons/stefan'
      assert_file_contains ${desktopAccountsServiceAvatarScript} '/var/lib/dms-greeter/users/stefan/profile.png'
      assert_file_contains ${desktopDmsOutputsFile} 'hl.monitor({ output = "desc:Samsung Electric Company S24E510C 0x3042524B", mode = "1920x1080@60.000", position = "0x0", scale = "1", vrr = 0 })'
      assert_file_contains ${desktopDmsOutputsFile} 'hl.monitor({ output = "desc:BNQ BenQ XL2411Z 54G01103SL0", mode = "1920x1080@60.000", position = "1920x0", scale = "1", vrr = 0 })'
      assert_file_contains ${desktopDmsLegacyProfileFile} 'monitor = desc:Samsung Electric Company S24E510C 0x3042524B, 1920x1080@60.000, 0x0, 1, vrr, 0'
      assert_file_contains ${desktopDmsLegacyProfileFile} 'monitor = desc:BNQ BenQ XL2411Z 54G01103SL0, 1920x1080@60.000, 1920x0, 1, vrr, 0'
      assert_file_contains ${laptopDmsOutputsFile} 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })'
      assert_file_contains ${usbDmsOutputsFile} 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })'

      touch "$out"
    '';
}
