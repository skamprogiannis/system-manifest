{ctx}: let
  inherit
    (ctx)
    desktopHyprlandLuaFile
    desktopHyprlandPackage
    pkgs
    ;
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

      assert_contains() {
        local needle="$1"
        if ! grep -Fq "$needle" ${desktopHyprlandLuaFile}; then
          echo "Expected generated Hyprland Lua config to contain: $needle" >&2
          sed 's/^/  /' ${desktopHyprlandLuaFile} >&2
          exit 1
        fi
      }

      assert_not_contains() {
        local needle="$1"
        if grep -Fq "$needle" ${desktopHyprlandLuaFile}; then
          echo "Generated Hyprland Lua config still contains legacy text: $needle" >&2
          sed 's/^/  /' ${desktopHyprlandLuaFile} >&2
          exit 1
        fi
      }

      assert_contains 'local mod = "SUPER"'
      assert_contains 'mod .. " + grave"'
      assert_contains 'mod .. " + KP_Enter"'
      assert_contains 'hl.dsp.window.close()'
      assert_contains 'hl.bind((mod .. " + m"), (hl.dsp.exec_cmd("spotify")))'
      assert_contains 'hl.bind((mod .. " + f"), (hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })))'
      assert_contains 'hl.bind((mod .. " + SHIFT + f"), (hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })))'
      assert_contains 'hl.dsp.focus({ workspace = "1" })'
      assert_contains 'hl.dsp.window.move({ workspace = "1", follow = true })'
      assert_contains 'hl.dsp.window.move({ workspace = "1", follow = false })'
      assert_contains 'hl.get_monitor("l") == nil'
      assert_contains 'hl.get_monitor("r") == nil'
      assert_contains 'hl.dispatch(hl.dsp.window.move({ monitor = "l" }))'
      assert_contains 'hl.dispatch(hl.dsp.window.move({ monitor = "r" }))'
      assert_contains 'hl.dsp.workspace.toggle_special("music")'
      assert_contains 'hl.dsp.window.move({ workspace = "special:music", follow = true })'
      assert_contains 'hl.dsp.window.move({ workspace = "special:music", follow = false })'
      assert_contains 'hl.bind((mod .. " + r"), (hl.dsp.exec_cmd("gpu-screen-recorder-gtk")))'
      assert_contains 'hl.bind((mod .. " + SHIFT + r"), (hl.dsp.exec_cmd("gsr-record stop")))'
      assert_contains 'require_optional("dms.colors")'
      assert_contains 'require_optional("dms.outputs")'
      assert_contains 'require_optional("dms.binds-user")'
      assert_not_contains 'gsr-record region'
      assert_not_contains 'gsr-record fullscreen'
      assert_not_contains 'gsr-record window'
      assert_not_contains 'hl.dsp.exec_raw('
      assert_not_contains 'hypr-move-window-monitor'
      assert_not_contains 'hl.bind((mod .. " + SHIFT + Left"), (hl.dsp.window.move({ monitor = "l" })))'
      assert_not_contains 'hl.bind((mod .. " + SHIFT + Right"), (hl.dsp.window.move({ monitor = "r" })))'
      assert_not_contains 'source='
      assert_not_contains 'colors.conf'

      grep -Fq -- '--config' ${desktopHyprlandPackage}/bin/Hyprland
      grep -Fq -- 'hyprland.lua' ${desktopHyprlandPackage}/bin/Hyprland

      export HOME="$TMPDIR/home"
      export XDG_RUNTIME_DIR="$TMPDIR/runtime"
      mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
      ${desktopHyprlandPackage}/bin/Hyprland --config ${desktopHyprlandLuaFile} --verify-config

      touch "$out"
    '';
}
