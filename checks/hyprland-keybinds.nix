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
      assert_contains 'hl.bind((mod .. " + g"), (hl.dsp.group.toggle()))'
      assert_contains 'hl.bind((mod .. " + Tab"), (hl.dsp.group.next()))'
      assert_contains 'hl.bind((mod .. " + SHIFT + Tab"), (hl.dsp.group.prev()))'
      assert_contains 'hl.bind((mod .. " + SHIFT + g"), (hl.dsp.window.move({ out_of_group = true })))'
      assert_contains 'hl.bind((mod .. " + CTRL + g"), (hl.dsp.group.lock_active({ action = "toggle" })))'
      assert_contains 'hl.bind((mod .. " + ALT + g"), (hl.dsp.group.lock({ action = "toggle" })))'
      assert_contains 'hl.bind((mod .. " + CTRL + Tab"), (hl.dsp.group.move_window({ forward = true })))'
      assert_contains 'hl.bind((mod .. " + CTRL + SHIFT + Tab"), (hl.dsp.group.move_window({ forward = false })))'
      assert_contains '["auto_group"] = true'
      assert_contains '["drag_into_group"] = 2'
      assert_contains '["focus_removed_window"] = true'
      assert_contains '["groupbar"] = {'
      assert_contains '["font_size"] = 10'
      assert_contains '["height"] = 18'
      assert_contains '["keep_upper_gap"] = true'
      assert_contains '["render_titles"] = true'
      assert_contains '["scrolling"] = true'
      assert_contains '["insert_after_current"] = true'
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
        assert_contains_in_file 'hl.bind((mod .. " + SHIFT + h"), (hl.dsp.window.move({ direction = "left", group_aware = true })))'
        assert_contains_in_file 'hl.bind((mod .. " + SHIFT + l"), (hl.dsp.window.move({ direction = "right", group_aware = true })))'
        assert_contains_in_file 'hl.bind((mod .. " + SHIFT + k"), (hl.dsp.window.move({ direction = "up", group_aware = true })))'
        assert_contains_in_file 'hl.bind((mod .. " + SHIFT + j"), (hl.dsp.window.move({ direction = "down", group_aware = true })))'
        assert_contains_in_file 'hl.bind((mod .. " + SHIFT + Tab"), (hl.dsp.group.prev()))'
        assert_contains_in_file 'hl.bind((mod .. " + SHIFT + g"), (hl.dsp.window.move({ out_of_group = true })))'
        assert_contains_in_file 'hl.bind((mod .. " + CTRL + g"), (hl.dsp.group.lock_active({ action = "toggle" })))'
        assert_contains_in_file 'hl.bind((mod .. " + ALT + g"), (hl.dsp.group.lock({ action = "toggle" })))'
        assert_contains_in_file 'hl.bind((mod .. " + CTRL + Tab"), (hl.dsp.group.move_window({ forward = true })))'
        assert_contains_in_file 'hl.bind((mod .. " + CTRL + SHIFT + Tab"), (hl.dsp.group.move_window({ forward = false })))'
        assert_contains_in_file '["drag_into_group"] = 2'
        assert_contains_in_file '["groupbar"] = {'
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + h"), (hl.dsp.focus({ direction = "left" })))' 1
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + l"), (hl.dsp.focus({ direction = "right" })))' 1
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + SHIFT + h"), (hl.dsp.window.move({ direction = "left", group_aware = true })))' 1
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + SHIFT + l"), (hl.dsp.window.move({ direction = "right", group_aware = true })))' 1
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + SHIFT + k"), (hl.dsp.window.move({ direction = "up", group_aware = true })))' 1
        assert_line_count_in_file "$hyprland_lua" 'hl.bind((mod .. " + SHIFT + j"), (hl.dsp.window.move({ direction = "down", group_aware = true })))' 1
        assert_not_contains_in_file 'hl.bind((mod .. " + SHIFT + h"), (hl.dsp.window.move({ direction = "left" })))'
        assert_not_contains_in_file 'hl.bind((mod .. " + SHIFT + l"), (hl.dsp.window.move({ direction = "right" })))'
        assert_not_contains_in_file 'hl.bind((mod .. " + SHIFT + k"), (hl.dsp.window.move({ direction = "up" })))'
        assert_not_contains_in_file 'hl.bind((mod .. " + SHIFT + j"), (hl.dsp.window.move({ direction = "down" })))'
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
