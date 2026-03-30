{
  pkgs,
  config,
  lib,
  ...
}: let
  translucenceThemeName = "Translucence.theme.css";
  legacyGeneratedThemeName = "transluence-matugen.theme.css";

  regenTransluenceTheme = pkgs.writeShellScriptBin "regen-vesktop-transluence-theme" ''
    set -euo pipefail

    THEME_DIR="$HOME/.config/vesktop/themes"
    SETTINGS_DIR="$HOME/.config/vesktop/settings"
    OUT="$THEME_DIR/${translucenceThemeName}"
    QUICKCSS_OUT="$SETTINGS_DIR/quickCss.css"
    SRC_JSON="$HOME/.cache/DankMaterialShell/dms-colors.json"
    OVERLAY_STORE="${./vesktop/transluence-matugen.overlay.css}"

    mkdir -p "$THEME_DIR" "$SETTINGS_DIR"
    [ -f "$SRC_JSON" ] || exit 0
    [ -f "$OVERLAY_STORE" ] || exit 0

    # DMS can rewrite palette state in bursts. Wait for a stable snapshot.
    stable_hash=""
    for _ in $(${pkgs.coreutils}/bin/seq 1 40); do
      hash_a=$(${pkgs.coreutils}/bin/md5sum "$SRC_JSON" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      ${pkgs.coreutils}/bin/sleep 0.05
      hash_b=$(${pkgs.coreutils}/bin/md5sum "$SRC_JSON" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      if [ "$hash_a" = "$hash_b" ] && ${pkgs.python3}/bin/python3 - "$SRC_JSON" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
dark = data["colors"]["dark"]
required = (
    "error",
    "inverse_primary",
    "on_primary",
    "on_surface",
    "on_surface_variant",
    "outline",
    "primary",
    "primary_fixed_dim",
    "surface",
    "surface_bright",
    "surface_container_high",
    "surface_container_low",
    "surface_variant",
    "tertiary",
    "tertiary_container",
)
missing = [key for key in required if key not in dark]
raise SystemExit(0 if not missing else 1)
PY
      then
        stable_hash="$hash_a"
        break
      fi
    done

    [ -n "$stable_hash" ] || exit 0

    accent_hue="220"
    accent_saturation="82%"
    accent_lightness="76%"

    accent_hex=$(${pkgs.python3}/bin/python3 - "$SRC_JSON" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
dark = data["colors"]["dark"]
print((dark.get("primary") or dark.get("primary_fixed_dim") or "").lstrip("#"))
PY
    )

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

    render_quickcss_source_root() {
      ${pkgs.python3}/bin/python3 - "$SRC_JSON" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
dark = data["colors"]["dark"]

mapping = [
    ("--online-indicator", dark["inverse_primary"]),
    ("--dnd-indicator", dark["error"]),
    ("--idle-indicator", dark["tertiary_container"]),
    ("--streaming-indicator", dark["on_primary"]),
    ("--accent-1", dark["tertiary"]),
    ("--accent-2", dark["primary"]),
    ("--accent-3", dark["primary"]),
    ("--accent-4", dark["surface_bright"]),
    ("--accent-5", dark["primary_fixed_dim"]),
    ("--mention", dark["surface"]),
    ("--mention-hover", dark["surface_bright"]),
    ("--text-0", dark["surface"]),
    ("--text-1", dark["on_surface"]),
    ("--text-2", dark["on_surface"]),
    ("--text-3", dark["on_surface_variant"]),
    ("--text-4", dark["on_surface_variant"]),
    ("--text-5", dark["outline"]),
    ("--bg-1", dark["surface_variant"]),
    ("--bg-2", dark["surface_container_high"]),
    ("--bg-3", dark["surface_container_low"]),
    ("--bg-4", dark["surface"]),
    ("--hover", dark["surface_bright"]),
    ("--active", dark["surface_bright"]),
    ("--message-hover", dark["surface_bright"]),
]

for name, value in mapping:
    print(f"  --dms-{name[2:]}: {value};")
PY
    }

    render_theme_bridge_root() {
      cat <<'EOF'
:root {
  --online-indicator: var(--dms-online-indicator, #43a25a);
  --dnd-indicator: var(--dms-dnd-indicator, #f23f43);
  --idle-indicator: var(--dms-idle-indicator, #f0b232);
  --streaming-indicator: var(--dms-streaming-indicator, #593695);

  --accent-1: var(--dms-accent-1, #c9d0ff);
  --accent-2: var(--dms-accent-2, #b0c6ff);
  --accent-3: var(--dms-accent-3, #b0c6ff);
  --accent-4: var(--dms-accent-4, #38393e);
  --accent-5: var(--dms-accent-5, #4e5058);

  --mention: var(--dms-mention, #17191f);
  --mention-hover: var(--dms-mention-hover, #1e2128);

  --text-0: var(--dms-text-0, #121317);
  --text-1: var(--dms-text-1, #f2f3f5);
  --text-2: var(--dms-text-2, #dbdee1);
  --text-3: var(--dms-text-3, #b5bac1);
  --text-4: var(--dms-text-4, #949ba4);
  --text-5: var(--dms-text-5, #6d727a);

  --bg-1: var(--dms-bg-1, #202225);
  --bg-2: var(--dms-bg-2, #2b2d31);
  --bg-3: var(--dms-bg-3, #1e1f22);
  --bg-4: var(--dms-bg-4, #111214);

  --hover: var(--dms-hover, #35373c);
  --active: var(--dms-active, #3f4248);
  --message-hover: var(--dms-message-hover, #2a2d31);

  --accent-hue: var(--dms-accent-hue, 220);
  --accent-saturation: var(--dms-accent-saturation, 82%);
  --accent-lightness: var(--dms-accent-lightness, 76%);

  --green-to-accent-3-filter: var(--dms-green-to-accent-3-filter, hue-rotate(56deg) saturate(1.43));
  --blurple-to-accent-3-filter: var(--dms-blurple-to-accent-3-filter, hue-rotate(304deg) saturate(0.84) brightness(1.2));
}
EOF
    }

    # Keep temp files outside the watched Vesktop paths:
    # - the themes directory is watched as a directory, so temp files there trigger reload flicker
    # - quickCss.css is watched as a file, so replacing it breaks/inconsistently reattaches the watcher
    theme_tmp=$(mktemp)
    quickcss_tmp=$(mktemp)
    src_hash="$stable_hash"
    trap 'rm -f "$theme_tmp" "$quickcss_tmp"' EXIT

    cat > "$theme_tmp" <<EOF
/**
 * @name Translucence Matugen
 * @description Custom Translucence base with dynamic Matugen source vars bridged from QuickCSS
 * @author skamprogiannis
 * @version 1.7.1
 */

@import url(https://capnkitten.github.io/BetterDiscord/Themes/Translucence/css/source.css);
EOF
    printf '\n/* ----- QuickCSS source bridge ----- */\n' >> "$theme_tmp"
    render_theme_bridge_root >> "$theme_tmp"
    printf '\n/* ----- Transluence overlay ----- */\n' >> "$theme_tmp"
    cat "$OVERLAY_STORE" >> "$theme_tmp"

    cat > "$quickcss_tmp" <<EOF
/* Source hash: $src_hash (dms-colors.json, DMS Vesktop token mapping) */

/* ----- QuickCSS source vars for the static Translucence bridge ----- */
:root {
EOF
    render_quickcss_source_root >> "$quickcss_tmp"
    printf '}\n' >> "$quickcss_tmp"

    cat >> "$quickcss_tmp" <<EOF

/* ----- Derived accent HSL from Matugen accent ----- */
:root {
  --dms-accent-hue: $accent_hue;
  --dms-accent-saturation: $accent_saturation;
  --dms-accent-lightness: $accent_lightness;

  /* Keep the non-structural icon filter variables from the old DMS template. */
  --dms-green-to-accent-3-filter: hue-rotate(56deg) saturate(1.43);
  --dms-blurple-to-accent-3-filter: hue-rotate(304deg) saturate(0.84) brightness(1.2);
}
EOF

    cleanup_legacy_files() {
      ${pkgs.coreutils}/bin/rm -f \
        "$THEME_DIR/.transluence-matugen.palette.css" \
        "$THEME_DIR/.transluence-matugen.overlay.css" \
        "$THEME_DIR/dank-discord.css" \
        "$THEME_DIR/${legacyGeneratedThemeName}" \
        "$THEME_DIR/${legacyGeneratedThemeName}.backup"
    }

    write_if_changed() {
      local src="$1"
      local dst="$2"
      if [ -f "$dst" ] && ${pkgs.diffutils}/bin/cmp -s "$src" "$dst"; then
        rm -f "$src"
        return 1
      fi
      mv "$src" "$dst"
      return 0
    }

    write_in_place_if_changed() {
      local src="$1"
      local dst="$2"
      if [ -f "$dst" ] && ${pkgs.diffutils}/bin/cmp -s "$src" "$dst"; then
        rm -f "$src"
        return 1
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dst")"
      ${pkgs.coreutils}/bin/cat "$src" > "$dst"
      rm -f "$src"
      return 0
    }

    write_if_changed "$theme_tmp" "$OUT" || true
    write_in_place_if_changed "$quickcss_tmp" "$QUICKCSS_OUT" || true
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
    useQuickCss = true;
    enabledThemes = [translucenceThemeName];
  };

  vesktopStateSync = pkgs.writeShellScript "vesktop-state-sync" ''
    set -euo pipefail

    CFG="$HOME/.config/vesktop"
    SETTINGS_DIR="$CFG/settings"
    USER_ASSETS="$CFG/userAssets"
    mkdir -p "$SETTINGS_DIR"

    cleanup_legacy_icon_overrides() {
      rm -f "$USER_ASSETS/tray" "$USER_ASSETS/trayUnread"
      rmdir "$USER_ASSETS" 2>/dev/null || true
    }

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

    enforce_theme_settings() {
      local target="$1"
      local tmp
      tmp=$(mktemp)

      if [ -s "$target" ] && ${pkgs.jq}/bin/jq empty "$target" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq \
          '.plugins = ((.plugins // {}) + {"ClientTheme": ((.plugins.ClientTheme // {}) + {"enabled": true})})
          | del(.plugins.ClientTheme.color)
          | .enabledThemes = ["${translucenceThemeName}"]
          | .useQuickCss = true
          | .transparent = true' \
          "$target" > "$tmp"
      else
        printf '%s\n' '{"plugins":{"ClientTheme":{"enabled":true}},"enabledThemes":["${translucenceThemeName}"],"useQuickCss":true,"transparent":true}' > "$tmp"
      fi

      mv "$tmp" "$target"
    }

    cleanup_legacy_icon_overrides
    apply_settings_patch "$CFG/settings.json"
    apply_settings_patch "$SETTINGS_DIR/settings.json"
    enforce_theme_settings "$CFG/settings.json"
    enforce_theme_settings "$SETTINGS_DIR/settings.json"
    ${regenTransluenceTheme}/bin/regen-vesktop-transluence-theme
  '';

  vesktopLaunchWrapper = pkgs.writeShellScript "vesktop-launch" ''
    set -euo pipefail
    ${vesktopStateSync}
    exec ${pkgs.vesktop}/bin/vesktop "$@"
  '';
in {
  home.packages = [pkgs.vesktop regenTransluenceTheme];

  home.activation.syncVesktopThemeState = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${vesktopStateSync}
  '';

  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    genericName = "Internet Messenger";
    comment = "Vesktop with transparent background wrapper";
    icon = "vesktop";
    terminal = false;
    categories = ["Network" "InstantMessaging"];
    startupNotify = true;
    settings = {
      StartupWMClass = "Vesktop";
    };
    exec = "${vesktopLaunchWrapper} %U";
    mimeType = ["x-scheme-handler/discord"];
  };
}
