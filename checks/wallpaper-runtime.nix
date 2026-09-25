{ctx}: let
  inherit
    (ctx)
    desktopDmsPackage
    desktopSkwdWalldExec
    pkgs
    self
    usbDmsPackage
    ;
  externalThemeEnabled = host:
    builtins.elem "DMS_DISABLE_MATUGEN=1"
    self.nixosConfigurations.${host}.config.home-manager.users.stefan.systemd.user.services.dms.Service.Environment;
in {
  wallpaper-runtime = assert pkgs.lib.assertMsg
  (builtins.all externalThemeEnabled ["desktop" "laptop" "usb"])
  "DMS must consume the externally generated wallpaper palette on every host.";
    pkgs.runCommand "wallpaper-runtime-checks" {
      nativeBuildInputs = [pkgs.coreutils pkgs.gnugrep pkgs.python3];
    } ''
      set -euo pipefail

      if [ ! -x "${desktopSkwdWalldExec}" ]; then
        echo "Expected skwd-wall v2 daemon executable: ${desktopSkwdWalldExec}" >&2
        exit 1
      fi

      if ! grep -Fq 'skwd-wall-v2' ${../modules/home/hyprland.nix}; then
        echo "Expected Hyprland wallpaper keybind to launch skwd-wall-v2." >&2
        exit 1
      fi

      if grep -Fq 'skwd wall toggle' ${../modules/home/hyprland.nix}; then
        echo "Legacy skwd-wall v1 keybind is still active." >&2
        exit 1
      fi

      if ! grep -Fq 'engine = "matugen";' ${../modules/home/wallpaper/skwd-wall-v2.nix}; then
        echo "Expected skwd-wall v2 to remain the Matugen colour authority." >&2
        exit 1
      fi

      if ! grep -Fq 'targets = ["dms"];' ${../modules/home/wallpaper/skwd-wall-v2.nix}; then
        echo "Expected skwd-wall v2 to publish its palette to DMS." >&2
        exit 1
      fi

      export WALLPAPER_SYNC_SOURCE=${../modules/home/wallpaper/wallpaper-sync.py}
      python3 ${./wallpaper-sync-test.py}
      export WALLPAPER_GREETER_SYNC_SOURCE=${../modules/system/wallpaper-greeter-sync.py}
      python3 ${./wallpaper-greeter-sync-test.py}

      python3 - ${desktopDmsPackage} ${usbDmsPackage} <<'PY'
      from pathlib import Path
      import sys
      for package in sys.argv[1:]:
          qml = (Path(package) / "share/quickshell/dms/Services/WallpaperCyclingService.qml").read_text()
          external_set = qml.split("function externalSet(", 1)[1].split("function clear()", 1)[0]
          assert "SessionData.saveSettings()" in external_set
          assert "generateSystemThemes" not in external_set, "externalSet must not overwrite skwd's palette"
      PY

      touch "$out"
    '';
}
