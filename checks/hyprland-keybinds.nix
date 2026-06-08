{ctx}: let
  inherit (ctx) desktopHyprlandBindsFile pkgs;
in {
  hyprland-keybinds =
    pkgs.runCommand "hyprland-keybind-checks" {
      nativeBuildInputs = [
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
      ];
    } ''
      set -euo pipefail

      assert_bind() {
        local bind="$1"
        if ! grep -Fxq "$bind" ${desktopHyprlandBindsFile}; then
          echo "Expected desktop Hyprland bind: $bind" >&2
          sed 's/^/  /' ${desktopHyprlandBindsFile} >&2
          exit 1
        fi
      }

      assert_bind '$mod, grave, togglespecialworkspace, music'
      assert_bind '$mod SHIFT, grave, movetoworkspace, special:music'
      assert_bind '$mod CTRL, grave, movetoworkspacesilent, special:music'

      touch "$out"
    '';
}
