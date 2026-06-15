{ctx}: let
  inherit
    (ctx)
    desktopAccountsServiceAvatarScript
    desktopDmsLegacyProfileFile
    desktopDmsOutputsFile
    desktopGreeterPackage
    desktopHyprlandPackage
    laptopDmsOutputsFile
    pkgs
    usbDmsOutputsFile
    ;
in {
  desktop-runtime-config =
    pkgs.runCommand "desktop-runtime-config-checks" {
      nativeBuildInputs = [
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

      assert_file_contains ${desktopHyprlandPackage}/bin/Hyprland '--config'
      assert_file_contains ${desktopHyprlandPackage}/bin/Hyprland 'hyprland.lua'
      assert_file_contains ${desktopHyprlandPackage}/bin/start-hyprland '/bin/start-hyprland --path'
      assert_file_contains ${desktopHyprlandPackage}/bin/start-hyprland '/bin/Hyprland" "$@"'
      assert_file_not_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter '$CACHE_DIR/hyprland.log'
      assert_file_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter "neither 'start-hyprland' nor 'Hyprland' was found in PATH"
      assert_file_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter 'exec_compositor "hyprland" start-hyprland -- --config "$COMPOSITOR_CONFIG"'
      assert_file_contains ${desktopGreeterPackage}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter 'exec_compositor "hyprland" Hyprland -c "$COMPOSITOR_CONFIG"'
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
