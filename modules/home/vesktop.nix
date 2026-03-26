{
  pkgs,
  config,
  lib,
  ...
}: let
  transluenceSourceThemeName = "Translucence.theme.css";
  transluenceThemeName = "transluence-matugen.theme.css";
  transluenceOverlayName = ".transluence-matugen.overlay.css";

  regenTransluenceTheme = pkgs.writeShellScriptBin "regen-vesktop-transluence-theme" ''
    set -euo pipefail

    THEME_DIR="$HOME/.config/vesktop/themes"
    SRC_THEME="$THEME_DIR/${transluenceSourceThemeName}"
    SRC_COLORS="$THEME_DIR/dank-discord.css"
    OVERLAY="$THEME_DIR/${transluenceOverlayName}"
    OUT="$THEME_DIR/${transluenceThemeName}"

    [ -f "$SRC_THEME" ] || exit 0
    [ -f "$SRC_COLORS" ] || exit 0
    [ -f "$OVERLAY" ] || exit 0

    tmp=$(mktemp)
    src_hash=$(${pkgs.coreutils}/bin/md5sum "$SRC_COLORS" | ${pkgs.coreutils}/bin/cut -d' ' -f1)

    cat > "$tmp" <<EOF
/**
 * @name Transluence Matugen
 * @description Transluence tuned for transparent Vesktop and Matugen palette sync
 * @author skamprogiannis
 * @version 1.0.0
 */

/* Source hash: $src_hash (dank-discord.css) */
EOF

    cat "$SRC_THEME" >> "$tmp"
    printf '\n/* ----- Matugen + Transparency overlay ----- */\n' >> "$tmp"
    cat "$SRC_COLORS" >> "$tmp"
    printf '\n/* ----- Transluence overlay ----- */\n' >> "$tmp"
    cat "$OVERLAY" >> "$tmp"

    mv "$tmp" "$OUT"
  '';

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
    enabledThemes = [transluenceThemeName];
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
          | .enabledThemes = ["${transluenceThemeName}"]
          | .useQuickCss = false
          | .transparent = true' \
          "$target" > "$tmp"
      else
        printf '%s\n' '{"plugins":{"ClientTheme":{"enabled":true}},"enabledThemes":["${transluenceThemeName}"],"useQuickCss":false,"transparent":true}' > "$tmp"
      fi

      mv "$tmp" "$target"
    }

    enforce_theme_settings "$CFG/settings.json"
    enforce_theme_settings "$SETTINGS_DIR/settings.json"
    ${regenTransluenceTheme}/bin/regen-vesktop-transluence-theme

    # Stability-first: transparent visuals flag has caused Electron traps here.
    exec ${pkgs.vesktop}/bin/vesktop "$@"
  '';
in {
  home.packages = [pkgs.vesktop regenTransluenceTheme];
  home.file.".config/vesktop/themes/${transluenceOverlayName}".source = ./vesktop/transluence-matugen.overlay.css;

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
