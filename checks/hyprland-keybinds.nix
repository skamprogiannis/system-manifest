{ctx}: let
  inherit
    (ctx)
    desktopAccountsServiceAvatarScript
    desktopDmsLegacyProfileFile
    desktopDmsOutputsFile
    desktopGreeterPackage
    desktopHyprlandLuaFile
    desktopHyprlandPackage
    laptopDmsOutputsFile
    pkgs
    usbDmsOutputsFile
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
      assert_contains 'hl.dsp.window.close()'
      assert_contains 'hl.dsp.focus({ workspace = "1" })'
      assert_contains 'hl.dsp.window.move({ workspace = "1", follow = true })'
      assert_contains 'hl.dsp.window.move({ workspace = "1", follow = false })'
      assert_contains 'hl.dsp.workspace.toggle_special("music")'
      assert_contains 'hl.dsp.window.move({ workspace = "special:music", follow = true })'
      assert_contains 'hl.dsp.window.move({ workspace = "special:music", follow = false })'
      assert_contains 'require_optional("dms.colors")'
      assert_contains 'require_optional("dms.outputs")'
      assert_contains 'require_optional("dms.binds-user")'
      assert_contains 'hl.window_rule({'
      assert_contains '["name"] = "pearpass-no-blur"'
      assert_contains 'hl.layer_rule({'
      assert_not_contains 'hl.dsp.exec_raw('
      assert_not_contains 'source='
      assert_not_contains 'colors.conf'
      assert_not_contains 'plugin:hyprglass {'
      assert_not_contains '["light:brightness"]'
      assert_not_contains 'plugin:hyprglass:light:'
      assert_not_contains '["hyprglass"] = {'
      assert_not_contains '["pseudotile"]'
      assert_not_contains '["tint_color"] = "0xffffff08"'
      assert_contains 'hyprctl plugin load'
      assert_contains 'hyprctl keyword plugin:hyprglass:tint_color 0xffffff08'
      assert_contains 'hyprctl keyword plugin:hyprglass:brightness 1.02'
      assert_contains 'hyprctl keyword plugin:hyprglass:contrast 0.95'
      assert_contains 'hyprctl keyword plugin:hyprglass:saturation 1.0'
      assert_contains 'hyprctl keyword plugin:hyprglass:vibrancy 0.05'

      assert_file_contains ${desktopHyprlandPackage}/bin/Hyprland '--config'
      assert_file_contains ${desktopHyprlandPackage}/bin/Hyprland 'hyprland.lua'
      assert_file_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter '$CACHE_DIR/hyprland.log'
      assert_file_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter 'exec_compositor "hyprland" Hyprland -c "$COMPOSITOR_CONFIG"'
      assert_file_not_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter 'start-hyprland -- --config'
      assert_file_contains ${desktopAccountsServiceAvatarScript} '/var/lib/AccountsService/icons/stefan'
      assert_file_contains ${desktopAccountsServiceAvatarScript} '/var/lib/dms-greeter/users/stefan/profile.png'
      assert_file_contains ${desktopDmsOutputsFile} 'hl.monitor({ output = "desc:Samsung Electric Company S24E510C 0x3042524B", mode = "1920x1080@60.000", position = "0x0", scale = "1", vrr = 0 })'
      assert_file_contains ${desktopDmsOutputsFile} 'hl.monitor({ output = "desc:BNQ BenQ XL2411Z 54G01103SL0", mode = "1920x1080@60.000", position = "1920x0", scale = "1", vrr = 0 })'
      assert_file_contains ${desktopDmsLegacyProfileFile} 'monitor = desc:Samsung Electric Company S24E510C 0x3042524B, 1920x1080@60.000, 0x0, 1, vrr, 0'
      assert_file_contains ${desktopDmsLegacyProfileFile} 'monitor = desc:BNQ BenQ XL2411Z 54G01103SL0, 1920x1080@60.000, 1920x0, 1, vrr, 0'
      assert_file_contains ${laptopDmsOutputsFile} 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })'
      assert_file_contains ${usbDmsOutputsFile} 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })'

      export HOME="$TMPDIR/home"
      export XDG_RUNTIME_DIR="$TMPDIR/runtime"
      mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
      ${desktopHyprlandPackage}/bin/Hyprland --config ${desktopHyprlandLuaFile} --verify-config

      touch "$out"
    '';
}
