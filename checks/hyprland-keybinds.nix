{ctx}: let
  inherit
    (ctx)
    desktopHyprlandLuaFile
    desktopHyprlandPackage
    laptopHyprlandLuaFile
    pkgs
    usbHyprlandLuaFile
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

      assert_line_count_in_file() {
        local file="$1"
        local needle="$2"
        local expected_count="$3"

        local actual_count
        actual_count="$(grep -Fxc "$needle" "$file" || true)"
        if [ "$actual_count" -ne "$expected_count" ]; then
          echo "Expected $expected_count exact occurrences of '$needle' in $file, got $actual_count" >&2
          sed 's/^/  /' "$file" >&2
          exit 1
        fi
      }

      extract_navigation_binds() {
        local file="$1"
        grep -F \
          -e 'hl.bind((mod .. " + h"), (hl.dsp.focus({ direction = "left" })))' \
          -e 'hl.bind((mod .. " + l"), (hl.dsp.focus({ direction = "right" })))' \
          "$file"
      }

      desktop_navigation_binds="$TMPDIR/desktop-navigation-binds"
      extract_navigation_binds ${desktopHyprlandLuaFile} > "$desktop_navigation_binds"

      for hyprland_lua in ${desktopHyprlandLuaFile} ${laptopHyprlandLuaFile} ${usbHyprlandLuaFile}; do
        assert_contains_in_file() {
          local needle="$1"
          if ! grep -Fq "$needle" "$hyprland_lua"; then
            echo "Expected generated Hyprland Lua config to contain: $needle" >&2
            sed 's/^/  /' "$hyprland_lua" >&2
            exit 1
          fi
        }

        assert_not_contains_in_file() {
          local needle="$1"
          if grep -Fq "$needle" "$hyprland_lua"; then
            echo "Generated Hyprland Lua config still contains legacy text: $needle" >&2
            sed 's/^/  /' "$hyprland_lua" >&2
            exit 1
          fi
        }

        assert_contains_in_file 'hl.bind((mod .. " + h"), (hl.dsp.focus({ direction = "left" })))'
        assert_contains_in_file 'hl.bind((mod .. " + l"), (hl.dsp.focus({ direction = "right" })))'
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + h"), (hl.dsp.focus({ direction = "left" })))' 1
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + l"), (hl.dsp.focus({ direction = "right" })))' 1
        assert_not_contains_in_file 'hypr-nav'
        assert_not_contains_in_file 'no_focus_fallback'
        assert_not_contains_in_file 'window_direction_monitor_fallback'

        host_navigation_binds="$TMPDIR/$(basename "$hyprland_lua").navigation-binds"
        extract_navigation_binds "$hyprland_lua" > "$host_navigation_binds"
        if ! cmp -s "$desktop_navigation_binds" "$host_navigation_binds"; then
          echo "Expected host Super+h/l navigation binds to match desktop exactly: $hyprland_lua" >&2
          echo "Desktop:" >&2
          sed 's/^/  /' "$desktop_navigation_binds" >&2
          echo "Host:" >&2
          sed 's/^/  /' "$host_navigation_binds" >&2
          exit 1
        fi
      done

      grep -Fq -- '--config' ${desktopHyprlandPackage}/bin/Hyprland
      grep -Fq -- 'hyprland.lua' ${desktopHyprlandPackage}/bin/Hyprland

      export HOME="$TMPDIR/home"
      export XDG_RUNTIME_DIR="$TMPDIR/runtime"
      mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
      ${desktopHyprlandPackage}/bin/Hyprland --config ${desktopHyprlandLuaFile} --verify-config

      touch "$out"
    '';
}
