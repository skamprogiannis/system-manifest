{ctx}: let
  inherit
    (ctx)
    desktopHome
    desktopSkwdDmsSyncHook
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

      assert_executable "${desktopHome}/bin/skwd" "skwd"
      assert_executable "${desktopHome}/bin/skwd-daemon" "skwd-daemon"
      assert_executable "${desktopHome}/bin/skwd-wall" "skwd-wall"
      assert_executable "${desktopHome}/bin/skwd-we-capture-still" "skwd-we-capture-still"
      assert_executable "${desktopSkwdDmsSyncHook}" "DMS wallpaper sync hook"

      skwd_bin="$(readlink -f "${desktopHome}/bin/skwd")"
      skwd_pkg="$(dirname "$(dirname "$skwd_bin")")"
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
      assert_contains "skwd-we-capture-still" "${desktopHome}/bin/skwd-we-capture-still" "Wallpaper Engine capture helper"
      assert_contains "# selector navigation" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# filter bar keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# tag cloud keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# settings keyboard" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"
      assert_contains "# apply-service backends" ${../modules/home/wallpaper/qml-patches.nix} "skwd-wall QML patch module"

      if grep -Fq "'} else if (event.key === Qt.Key_Right) {'," ${../modules/home/wallpaper/qml-patches.nix}; then
        echo "skwd-wall QML patch module still contains the confirmed no-op Qt.Key_Right replacement." >&2
        exit 1
      fi

      touch "$out"
    '';
}
