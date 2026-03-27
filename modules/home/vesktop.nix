{
  pkgs,
  config,
  lib,
  ...
}: let
  transluenceThemeName = "transluence-matugen.theme.css";

  regenTransluenceTheme = pkgs.writeShellScriptBin "regen-vesktop-transluence-theme" ''
    set -euo pipefail

    THEME_DIR="$HOME/.config/vesktop/themes"
    SRC_COLORS="$THEME_DIR/dank-discord.css"
    OUT="$THEME_DIR/${transluenceThemeName}"
    OVERLAY_STORE="${./vesktop/transluence-matugen.overlay.css}"

    [ -f "$SRC_COLORS" ] || exit 0
    [ -f "$OVERLAY_STORE" ] || exit 0

    # DMS can rewrite palette files in bursts. Wait for a stable snapshot.
    stable_hash=""
    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      hash_a=$(${pkgs.coreutils}/bin/md5sum "$SRC_COLORS" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      ${pkgs.coreutils}/bin/sleep 0.05
      hash_b=$(${pkgs.coreutils}/bin/md5sum "$SRC_COLORS" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      if [ "$hash_a" = "$hash_b" ] && ${pkgs.gnugrep}/bin/grep -q -- '--accent-3:' "$SRC_COLORS"; then
        stable_hash="$hash_a"
        break
      fi
    done

    [ -n "$stable_hash" ] || exit 0

    accent_hue="220"
    accent_saturation="82%"
    accent_lightness="76%"

    accent_hex=$(
      ${pkgs.gnugrep}/bin/grep -m1 -oE -- '--accent-3:[[:space:]]*#[0-9a-fA-F]{6}' "$SRC_COLORS" \
        | ${pkgs.gnused}/bin/sed -E 's/.*#([0-9a-fA-F]{6}).*/\1/' \
        || true
    )
    if [ -z "$accent_hex" ]; then
      accent_hex=$(
        ${pkgs.gnugrep}/bin/grep -m1 -oE -- '--accent-2:[[:space:]]*#[0-9a-fA-F]{6}' "$SRC_COLORS" \
          | ${pkgs.gnused}/bin/sed -E 's/.*#([0-9a-fA-F]{6}).*/\1/' \
          || true
      )
    fi

    if [ -n "$accent_hex" ]; then
      accent_triplet=$(${pkgs.python3}/bin/python3 - "$accent_hex" <<'PY'
import colorsys
import sys

hexv = sys.argv[1].strip()
r = int(hexv[0:2], 16) / 255.0
g = int(hexv[2:4], 16) / 255.0
b = int(hexv[4:6], 16) / 255.0
h, l, s = colorsys.rgb_to_hls(r, g, b)
print(f"{round(h * 360)} {s * 100:.1f}% {l * 100:.1f}%")
PY
)
      accent_hue=$(printf '%s' "$accent_triplet" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      accent_saturation=$(printf '%s' "$accent_triplet" | ${pkgs.coreutils}/bin/cut -d' ' -f2)
      accent_lightness=$(printf '%s' "$accent_triplet" | ${pkgs.coreutils}/bin/cut -d' ' -f3)
    fi

    render_palette_root() {
      ${pkgs.gawk}/bin/awk '
        match($0, /--[a-zA-Z0-9-]+:[^;]+;/) {
          decl = substr($0, RSTART, RLENGTH)
          name = decl
          sub(/:.*/, "", name)

          keep =
            (name ~ /^--accent-[1-5]$/) ||
            (name ~ /^--text-[0-5]$/) ||
            (name ~ /^--bg-[1-4]$/) ||
            (name == "--hover") ||
            (name == "--active") ||
            (name == "--message-hover") ||
            (name == "--mention") ||
            (name == "--mention-hover") ||
            (name == "--online-indicator") ||
            (name == "--dnd-indicator") ||
            (name == "--idle-indicator") ||
            (name == "--streaming-indicator")

          if (keep && !seen[name]++) {
            print "  " decl
          }
        }
      ' "$SRC_COLORS"
    }

    tmp=$(mktemp)
    src_hash="$stable_hash"

    cat > "$tmp" <<EOF
/**
 * @name Transluence Matugen
 * @description Transluence tuned for transparent Vesktop and Matugen palette sync
 * @author skamprogiannis
 * @version 1.3.0
 */

@import url(https://capnkitten.github.io/BetterDiscord/Themes/Translucence/css/source.css);

/* Source hash: $src_hash (dank-discord.css) */
EOF

    printf '\n/* ----- Matugen palette tokens (sanitized from DMS output) ----- */\n:root {\n' >> "$tmp"
    render_palette_root >> "$tmp"
    printf '}\n' >> "$tmp"

    cat >> "$tmp" <<EOF

/* ----- Derived accent HSL from Matugen accent ----- */
:root {
  --dms-accent-hue: $accent_hue;
  --dms-accent-saturation: $accent_saturation;
  --dms-accent-lightness: $accent_lightness;
}
EOF
    printf '\n/* ----- Transluence overlay ----- */\n' >> "$tmp"
    cat "$OVERLAY_STORE" >> "$tmp"

    cleanup_legacy_files() {
      ${pkgs.coreutils}/bin/rm -f \
        "$THEME_DIR/.transluence-matugen.palette.css" \
        "$THEME_DIR/.transluence-matugen.overlay.css" \
        "$THEME_DIR/${transluenceThemeName}.backup"
    }

    # Avoid needless rewrites/reloads when content is unchanged.
    if [ -f "$OUT" ] && ${pkgs.diffutils}/bin/cmp -s "$tmp" "$OUT"; then
      rm -f "$tmp"
      cleanup_legacy_files
      exit 0
    fi

    mv "$tmp" "$OUT"
    cleanup_legacy_files
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
