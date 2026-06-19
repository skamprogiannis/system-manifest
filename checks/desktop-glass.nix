{ctx}: let
  inherit
    (ctx)
    desktopDmsSettingsFile
    desktopGhosttySettingsFile
    desktopGtk4ExtraCssFile
    desktopHyprlandLuaFile
    desktopSpicetifyAdditionalCssFile
    desktopSpicetifyExtraCommandsFile
    desktopSpicetifyInjectThemeJsFile
    pkgs
    ;
in {
  desktop-glass =
    pkgs.runCommand "desktop-glass-checks" {
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

      legacy_glass="hypr""glass"

      assert_file_contains ${desktopHyprlandLuaFile} 'hl.window_rule({'
      assert_file_contains ${desktopHyprlandLuaFile} '["name"] = "pearpass-no-blur"'
      assert_file_contains ${desktopHyprlandLuaFile} '["name"] = "ghostty-native-glass"'
      assert_file_contains ${desktopHyprlandLuaFile} '["class"] = "^(com\\.mitchellh\\.ghostty)$"'
      assert_file_contains ${desktopHyprlandLuaFile} '["opacity"] = "1.0 override"'
      assert_file_contains ${desktopHyprlandLuaFile} '["name"] = "vesktop-opaque"'
      assert_file_contains ${desktopHyprlandLuaFile} '["class"] = "^(vesktop)$"'
      assert_file_contains ${desktopHyprlandLuaFile} 'hl.layer_rule({'
      assert_file_not_contains ${desktopHyprlandLuaFile} "plugin:$legacy_glass {"
      assert_file_not_contains ${desktopHyprlandLuaFile} "$legacy_glass"
      assert_file_not_contains ${desktopHyprlandLuaFile} "$legacy_glass.so"
      assert_file_not_contains ${desktopHyprlandLuaFile} "apply-$legacy_glass-settings"
      assert_file_not_contains ${desktopHyprlandLuaFile} "hl.plugin.$legacy_glass"
      assert_file_not_contains ${desktopHyprlandLuaFile} '["light:brightness"]'
      assert_file_not_contains ${desktopHyprlandLuaFile} "plugin:$legacy_glass:light:"
      assert_file_not_contains ${desktopHyprlandLuaFile} "[\"$legacy_glass\"] = {"
      assert_file_not_contains ${desktopHyprlandLuaFile} "+''${legacy_glass}_preset"
      assert_file_not_contains ${desktopHyprlandLuaFile} "+''${legacy_glass}_disabled"
      assert_file_not_contains ${desktopHyprlandLuaFile} '["pseudotile"]'
      assert_file_not_contains ${desktopHyprlandLuaFile} '["tint_color"] = "0xffffff0c"'
      assert_file_not_contains ${desktopHyprlandLuaFile} 'ghostty -e spotify_player'
      assert_file_not_contains ${desktopHyprlandLuaFile} 'hyprctl plugin load'
      assert_file_contains ${desktopHyprlandLuaFile} '["size"] = 3'
      assert_file_contains ${desktopHyprlandLuaFile} '["passes"] = 2'
      assert_file_contains ${desktopHyprlandLuaFile} '["noise"] = 0.02'
      assert_file_contains ${desktopHyprlandLuaFile} '["contrast"] = 0.9'
      assert_file_contains ${desktopHyprlandLuaFile} '["ignore_opacity"] = true'
      assert_file_contains ${desktopHyprlandLuaFile} '["xray"] = false'
      assert_file_contains ${desktopHyprlandLuaFile} '["popups"] = true'
      assert_file_contains ${desktopHyprlandLuaFile} '["popups_ignorealpha"] = 0.2'
      assert_file_contains ${desktopHyprlandLuaFile} '"^dms:(bar|'
      assert_file_contains ${desktopGhosttySettingsFile} '"background-opacity":[0.4]'
      assert_file_contains ${desktopGhosttySettingsFile} '"background-opacity-cells":[true]'
      assert_file_contains ${desktopGhosttySettingsFile} '"background-blur":[true]'
      assert_file_contains ${desktopGhosttySettingsFile} '"minimum-contrast":[1.15]'
      assert_file_contains ${desktopDmsSettingsFile} '"popupTransparency":0.55'
      assert_file_contains ${desktopDmsSettingsFile} '"notepadTransparencyOverride":0.6'
      assert_file_contains ${desktopDmsSettingsFile} '"systemMonitorTransparency":0.6'
      assert_file_contains ${desktopDmsSettingsFile} '"transparency":0.35'
      assert_file_contains ${desktopDmsSettingsFile} '"widgetTransparency":0.55'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '--backdrop: rgba(0, 0, 0, 0.35) !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '--spice-card: rgba(var(--spice-rgb-card), 0.43) !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '--blur: 8px !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} 'backdrop-filter: blur(8px) !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '.main-contextMenu-menu::before'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} 'content: none !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} 'pointer-events: none !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '#search-dropdown > div'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '[role="dialog"]:has(input[placeholder="What do you want to play?"])'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '[role="dialog"]:has(.search-modal-listbox)'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '[data-tippy-root] [role="menu"]'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} 'overflow: visible !important;'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} '.encore-announcement-set'
      assert_file_contains ${desktopSpicetifyAdditionalCssFile} 'opacity: 0.45 !important;'
      assert_file_not_contains ${desktopSpicetifyAdditionalCssFile} 'overflow: hidden'
      assert_file_not_contains ${desktopSpicetifyAdditionalCssFile} '.CqXpLitKxRFvrULhC2kW.CJCWzxw0S_yJx0wDlvPQ.BGJFigbt4tZ2RFINF8Xu'
      assert_file_not_contains ${desktopSpicetifyAdditionalCssFile} '.VZpSxFV1mVKehHTF1r9W'
      assert_file_not_contains ${desktopSpicetifyAdditionalCssFile} 'div.ZuOMABESRg0Bpv8S9642'
      assert_file_contains ${desktopSpicetifyExtraCommandsFile} 'for hazyThemeScript in theme.js Extensions/theme.js; do'
      assert_file_contains ${desktopSpicetifyExtraCommandsFile} 'window.__systemManifestHazyThemeJsPatched = true;'
      assert_file_contains ${desktopSpicetifyExtraCommandsFile} 'systemManifestHazySettingsVersion = "glass-8px-v1";'
      assert_file_contains ${desktopSpicetifyExtraCommandsFile} 'localStorage.setItem("blurAmount", "8");'
      assert_file_contains ${desktopSpicetifyExtraCommandsFile} 'document.querySelectorAll("[aria-label=\"Hazy Settings\"]").forEach((button) => button.remove());'
      assert_file_contains ${desktopSpicetifyInjectThemeJsFile} 'false'
      assert_file_contains ${desktopGtk4ExtraCssFile} 'background-color: alpha(#11111b, 0.80);'
      assert_file_contains ${desktopGtk4ExtraCssFile} 'box-shadow: 0 10px 28px alpha(#000000, 0.32);'
      assert_file_contains ${../modules/home/vesktop.nix} 'glass.vesktop.settingsBlurPx'
      assert_file_contains ${../modules/home/vesktop.nix} 'glass.vesktop.popoutBlurPx'
      assert_file_not_contains ${../modules/home/vesktop/transluence-matugen.overlay.css} '--sidebar-color: color-mix'
      assert_file_not_contains ${../modules/home/vesktop/transluence-matugen.overlay.css} 'standardSidebarView_'
      assert_file_not_contains ${../modules/home/vesktop/transluence-matugen.overlay.css} 'blur(20px)'

      touch "$out"
    '';
}
