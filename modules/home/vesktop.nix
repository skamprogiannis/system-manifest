{
  pkgs,
  config,
  lib,
  ...
}: let
  liquidGlassThemeName = "liquid-glass.theme.css";

  vesktopSettingsPatch = builtins.toJSON {
    minimizeToTray = true;
    arRPC = false;
    splashColor = "rgb(15,17,22)";
    splashBackground = "transparent";
    staticTitle = true;
    disableMinSize = false;
    hardwareAcceleration = true;
    discordBranch = "stable";
    tray = true;
    clickTrayToShowHide = false;
    customTitleBar = false;
    disableAutostart = false;
    transparent = true;
    useQuickCss = false;
    enabledThemes = [liquidGlassThemeName];
  };

  vesktopLaunchWrapper = pkgs.writeShellScript "vesktop-launch" ''
    set -euo pipefail
    CFG="$HOME/.config/vesktop"
    SETTINGS_DIR="$CFG/settings"
    mkdir -p "$SETTINGS_DIR"

    # Ensure "Open Theme Folder" and other file:// opens resolve to Yazi.
    XDG_OPEN_WRAPPER=$(mktemp -d)
    trap 'rm -rf "$XDG_OPEN_WRAPPER"' EXIT
    cat > "$XDG_OPEN_WRAPPER/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

target="''${1:-$HOME}"
if [ "''${target#file://}" != "$target" ]; then
  target=$(${pkgs.python3}/bin/python3 - "$target" <<'PY'
import sys
from urllib.parse import unquote, urlparse
uri = sys.argv[1]
parsed = urlparse(uri)
path = parsed.path or ""
print(unquote(path))
PY
  )
fi

if [ -d "$target" ]; then
  exec ${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi "$target"
fi

exec ${pkgs.xdg-utils}/bin/xdg-open "$@"
EOF
    chmod +x "$XDG_OPEN_WRAPPER/xdg-open"
    export PATH="$XDG_OPEN_WRAPPER:$PATH"

    apply_settings_patch() {
      local target="$1"
      local tmp
      tmp=$(mktemp)
      if [ -s "$target" ] && ${pkgs.jq}/bin/jq empty "$target" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq --argjson patch '${vesktopSettingsPatch}' '. + $patch' "$target" > "$tmp"
      else
        printf '%s\n' '${vesktopSettingsPatch}' > "$tmp"
      fi
      mv "$tmp" "$target"
    }

    # Preserve user settings, but enforce transparency-critical keys.
    apply_settings_patch "$CFG/settings.json"
    apply_settings_patch "$SETTINGS_DIR/settings.json"

    # Keep client themes enabled and pinned to declarative theme set.
    enforce_theme_settings() {
      local target="$1"
      local tmp
      tmp=$(mktemp)

      if [ -s "$target" ] && ${pkgs.jq}/bin/jq empty "$target" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq \
          '.plugins = ((.plugins // {}) + {"ClientTheme": ((.plugins.ClientTheme // {}) + {"enabled": true})})
          | .enabledThemes = ["${liquidGlassThemeName}"]
          | .useQuickCss = false
          | .transparent = true' \
          "$target" > "$tmp"
      else
        printf '%s\n' '{"plugins":{"ClientTheme":{"enabled":true}},"enabledThemes":["${liquidGlassThemeName}"],"useQuickCss":false,"transparent":true}' > "$tmp"
      fi

      mv "$tmp" "$target"
    }

    enforce_theme_settings "$CFG/settings.json"
    enforce_theme_settings "$SETTINGS_DIR/settings.json"

    # Stability-first: transparent visuals flag has caused Electron traps here.
    exec ${pkgs.vesktop}/bin/vesktop "$@"
  '';
in {
  home.packages = [pkgs.vesktop];

  home.file.".config/vesktop/themes/${liquidGlassThemeName}".source = ./vesktop/liquid-glass.theme.css;

  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    genericName = "Internet Messenger";
    comment = "Vesktop with transparent background wrapper";
    icon = "vesktop";
    terminal = false;
    categories = ["Network" "InstantMessaging"];
    startupNotify = true;
    exec = "${vesktopLaunchWrapper} %U";
    mimeType = ["x-scheme-handler/discord"];
  };
}
