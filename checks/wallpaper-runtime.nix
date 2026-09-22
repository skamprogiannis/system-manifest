{ctx}: let
  inherit
    (ctx)
    desktopSkwdWalldExec
    pkgs
    ;
in {
  wallpaper-runtime =
    pkgs.runCommand "wallpaper-runtime-checks" {
      nativeBuildInputs = [pkgs.coreutils pkgs.gnugrep];
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

      touch "$out"
    '';
}
