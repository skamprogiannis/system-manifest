{
  pkgs,
  skwdColorContract,
  skwdWallPkg,
  skwdDefaultMonitor,
  skwdScriptDir,
  steamLibraryDir,
  steamWorkshopDir,
  steamWeAssetsDir,
  skwdSecretsFile,
}: let
  vesktopColorContractFile = pkgs.writeText "vesktop-color-contract.json" (builtins.toJSON skwdColorContract);

  # Hyprland/DMS colors.conf — Material Design 3 tokens in DMS format
  hyprlandDmsTemplate = pkgs.writeText "hyprland-dms-colors.conf" ''
    $primary = rgba({{colors.primary.default.hex_stripped}}ff)
    $onPrimary = rgba({{colors.on_primary.default.hex_stripped}}ff)
    $primaryContainer = rgba({{colors.primary_container.default.hex_stripped}}ff)
    $onPrimaryContainer = rgba({{colors.on_primary_container.default.hex_stripped}}ff)
    $secondary = rgba({{colors.secondary.default.hex_stripped}}ff)
    $onSecondary = rgba({{colors.on_secondary.default.hex_stripped}}ff)
    $secondaryContainer = rgba({{colors.secondary_container.default.hex_stripped}}ff)
    $onSecondaryContainer = rgba({{colors.on_secondary_container.default.hex_stripped}}ff)
    $tertiary = rgba({{colors.tertiary.default.hex_stripped}}ff)
    $onTertiary = rgba({{colors.on_tertiary.default.hex_stripped}}ff)
    $tertiaryContainer = rgba({{colors.tertiary_container.default.hex_stripped}}ff)
    $onTertiaryContainer = rgba({{colors.on_tertiary_container.default.hex_stripped}}ff)
    $error = rgba({{colors.error.default.hex_stripped}}ff)
    $onError = rgba({{colors.on_error.default.hex_stripped}}ff)
    $errorContainer = rgba({{colors.error_container.default.hex_stripped}}ff)
    $onErrorContainer = rgba({{colors.on_error_container.default.hex_stripped}}ff)
    $surface = rgba({{colors.surface.default.hex_stripped}}ff)
    $onSurface = rgba({{colors.on_surface.default.hex_stripped}}ff)
    $surfaceVariant = rgba({{colors.surface_variant.default.hex_stripped}}ff)
    $onSurfaceVariant = rgba({{colors.on_surface_variant.default.hex_stripped}}ff)
    $surfaceDim = rgba({{colors.surface_dim.default.hex_stripped}}ff)
    $surfaceBright = rgba({{colors.surface_bright.default.hex_stripped}}ff)
    $surfaceContainerLowest = rgba({{colors.surface_container_lowest.default.hex_stripped}}ff)
    $surfaceContainerLow = rgba({{colors.surface_container_low.default.hex_stripped}}ff)
    $surfaceContainer = rgba({{colors.surface_container.default.hex_stripped}}ff)
    $surfaceContainerHigh = rgba({{colors.surface_container_high.default.hex_stripped}}ff)
    $surfaceContainerHighest = rgba({{colors.surface_container_highest.default.hex_stripped}}ff)
    $outline = rgba({{colors.outline.default.hex_stripped}}ff)
    $outlineVariant = rgba({{colors.outline_variant.default.hex_stripped}}ff)
    $inverseSurface = rgba({{colors.inverse_surface.default.hex_stripped}}ff)
    $inverseOnSurface = rgba({{colors.inverse_on_surface.default.hex_stripped}}ff)
    $inversePrimary = rgba({{colors.inverse_primary.default.hex_stripped}}ff)
    $scrim = rgba({{colors.scrim.default.hex_stripped}}ff)
    $shadow = rgba({{colors.shadow.default.hex_stripped}}ff)

    general {
      col.active_border   = $primary
      col.inactive_border = $outline
    }

    group {
      col.border_active   = $primary
      col.border_inactive = $outline
      col.border_locked_active   = $error
      col.border_locked_inactive = $outline

      groupbar {
        col.active         = $primary
        col.inactive       = $outline
        col.locked_active   = $error
        col.locked_inactive = $outline
      }
    }
  '';

  dmsDynamicColorsTemplate = pkgs.writeText "dms-colors.json" ''
    {
      "dank16": {},
      "colors": {
        "dark": {
          "background": "{{colors.background.dark.hex}}",
          "error": "{{colors.error.dark.hex}}",
          "error_container": "{{colors.error_container.dark.hex}}",
          "inverse_on_surface": "{{colors.inverse_on_surface.dark.hex}}",
          "inverse_primary": "{{colors.inverse_primary.dark.hex}}",
          "inverse_surface": "{{colors.inverse_surface.dark.hex}}",
          "on_background": "{{colors.on_background.dark.hex}}",
          "on_error": "{{colors.on_error.dark.hex}}",
          "on_error_container": "{{colors.on_error_container.dark.hex}}",
          "on_primary": "{{colors.on_primary.dark.hex}}",
          "on_primary_container": "{{colors.on_primary_container.dark.hex}}",
          "on_primary_fixed": "{{colors.on_primary_fixed.dark.hex}}",
          "on_primary_fixed_variant": "{{colors.on_primary_fixed_variant.dark.hex}}",
          "on_secondary": "{{colors.on_secondary.dark.hex}}",
          "on_secondary_container": "{{colors.on_secondary_container.dark.hex}}",
          "on_secondary_fixed": "{{colors.on_secondary_fixed.dark.hex}}",
          "on_secondary_fixed_variant": "{{colors.on_secondary_fixed_variant.dark.hex}}",
          "on_surface": "{{colors.on_surface.dark.hex}}",
          "on_surface_variant": "{{colors.on_surface_variant.dark.hex}}",
          "on_tertiary": "{{colors.on_tertiary.dark.hex}}",
          "on_tertiary_container": "{{colors.on_tertiary_container.dark.hex}}",
          "on_tertiary_fixed": "{{colors.on_tertiary_fixed.dark.hex}}",
          "on_tertiary_fixed_variant": "{{colors.on_tertiary_fixed_variant.dark.hex}}",
          "outline": "{{colors.outline.dark.hex}}",
          "outline_variant": "{{colors.outline_variant.dark.hex}}",
          "primary": "{{colors.primary.dark.hex}}",
          "primary_container": "{{colors.primary_container.dark.hex}}",
          "primary_fixed": "{{colors.primary_fixed.dark.hex}}",
          "primary_fixed_dim": "{{colors.primary_fixed_dim.dark.hex}}",
          "scrim": "{{colors.scrim.dark.hex}}",
          "secondary": "{{colors.secondary.dark.hex}}",
          "secondary_container": "{{colors.secondary_container.dark.hex}}",
          "secondary_fixed": "{{colors.secondary_fixed.dark.hex}}",
          "secondary_fixed_dim": "{{colors.secondary_fixed_dim.dark.hex}}",
          "shadow": "{{colors.shadow.dark.hex}}",
          "source_color": "{{colors.source_color.dark.hex}}",
          "surface": "{{colors.surface.dark.hex}}",
          "surface_bright": "{{colors.surface_bright.dark.hex}}",
          "surface_container": "{{colors.surface_container.dark.hex}}",
          "surface_container_high": "{{colors.surface_container_high.dark.hex}}",
          "surface_container_highest": "{{colors.surface_container_highest.dark.hex}}",
          "surface_container_low": "{{colors.surface_container_low.dark.hex}}",
          "surface_container_lowest": "{{colors.surface_container_lowest.dark.hex}}",
          "surface_dim": "{{colors.surface_dim.dark.hex}}",
          "surface_tint": "{{colors.surface_tint.dark.hex}}",
          "surface_variant": "{{colors.surface_variant.dark.hex}}",
          "tertiary": "{{colors.tertiary.dark.hex}}",
          "tertiary_container": "{{colors.tertiary_container.dark.hex}}",
          "tertiary_fixed": "{{colors.tertiary_fixed.dark.hex}}",
          "tertiary_fixed_dim": "{{colors.tertiary_fixed_dim.dark.hex}}"
        },
        "light": {
          "background": "{{colors.background.light.hex}}",
          "error": "{{colors.error.light.hex}}",
          "error_container": "{{colors.error_container.light.hex}}",
          "inverse_on_surface": "{{colors.inverse_on_surface.light.hex}}",
          "inverse_primary": "{{colors.inverse_primary.light.hex}}",
          "inverse_surface": "{{colors.inverse_surface.light.hex}}",
          "on_background": "{{colors.on_background.light.hex}}",
          "on_error": "{{colors.on_error.light.hex}}",
          "on_error_container": "{{colors.on_error_container.light.hex}}",
          "on_primary": "{{colors.on_primary.light.hex}}",
          "on_primary_container": "{{colors.on_primary_container.light.hex}}",
          "on_primary_fixed": "{{colors.on_primary_fixed.light.hex}}",
          "on_primary_fixed_variant": "{{colors.on_primary_fixed_variant.light.hex}}",
          "on_secondary": "{{colors.on_secondary.light.hex}}",
          "on_secondary_container": "{{colors.on_secondary_container.light.hex}}",
          "on_secondary_fixed": "{{colors.on_secondary_fixed.light.hex}}",
          "on_secondary_fixed_variant": "{{colors.on_secondary_fixed_variant.light.hex}}",
          "on_surface": "{{colors.on_surface.light.hex}}",
          "on_surface_variant": "{{colors.on_surface_variant.light.hex}}",
          "on_tertiary": "{{colors.on_tertiary.light.hex}}",
          "on_tertiary_container": "{{colors.on_tertiary_container.light.hex}}",
          "on_tertiary_fixed": "{{colors.on_tertiary_fixed.light.hex}}",
          "on_tertiary_fixed_variant": "{{colors.on_tertiary_fixed_variant.light.hex}}",
          "outline": "{{colors.outline.light.hex}}",
          "outline_variant": "{{colors.outline_variant.light.hex}}",
          "primary": "{{colors.primary.light.hex}}",
          "primary_container": "{{colors.primary_container.light.hex}}",
          "primary_fixed": "{{colors.primary_fixed.light.hex}}",
          "primary_fixed_dim": "{{colors.primary_fixed_dim.light.hex}}",
          "scrim": "{{colors.scrim.light.hex}}",
          "secondary": "{{colors.secondary.light.hex}}",
          "secondary_container": "{{colors.secondary_container.light.hex}}",
          "secondary_fixed": "{{colors.secondary_fixed.light.hex}}",
          "secondary_fixed_dim": "{{colors.secondary_fixed_dim.light.hex}}",
          "shadow": "{{colors.shadow.light.hex}}",
          "source_color": "{{colors.source_color.light.hex}}",
          "surface": "{{colors.surface.light.hex}}",
          "surface_bright": "{{colors.surface_bright.light.hex}}",
          "surface_container": "{{colors.surface_container.light.hex}}",
          "surface_container_high": "{{colors.surface_container_high.light.hex}}",
          "surface_container_highest": "{{colors.surface_container_highest.light.hex}}",
          "surface_container_low": "{{colors.surface_container_low.light.hex}}",
          "surface_container_lowest": "{{colors.surface_container_lowest.light.hex}}",
          "surface_dim": "{{colors.surface_dim.light.hex}}",
          "surface_tint": "{{colors.surface_tint.light.hex}}",
          "surface_variant": "{{colors.surface_variant.light.hex}}",
          "tertiary": "{{colors.tertiary.light.hex}}",
          "tertiary_container": "{{colors.tertiary_container.light.hex}}",
          "tertiary_fixed": "{{colors.tertiary_fixed.light.hex}}",
          "tertiary_fixed_dim": "{{colors.tertiary_fixed_dim.light.hex}}"
        }
      }
    }
  '';

  zathuraTemplate = pkgs.writeText "zathura-colors" ''
    set recolor "true"
    set completion-bg "{{colors.surface.default.hex}}"
    set completion-fg "{{colors.on_surface.default.hex}}"
    set completion-highlight-bg "{{colors.primary.default.hex}}"
    set completion-highlight-fg "{{colors.surface.default.hex}}"
    set recolor-lightcolor "{{colors.surface.default.hex}}"
    set recolor-darkcolor "{{colors.on_surface.default.hex}}"
    set default-bg "{{colors.surface.default.hex}}"
    set default-fg "{{colors.on_surface.default.hex}}"
    set statusbar-bg "{{colors.surface.default.hex}}"
    set statusbar-fg "{{colors.on_surface.default.hex}}"
    set inputbar-bg "{{colors.surface.default.hex}}"
    set inputbar-fg "{{colors.on_surface.default.hex}}"
    set notification-error-bg "#ff5555"
    set notification-error-fg "{{colors.on_surface.default.hex}}"
    set notification-warning-bg "#ffb86c"
    set notification-warning-fg "{{colors.on_surface.default.hex}}"
    set highlight-color "{{colors.primary.default.hex}}"
    set highlight-active-color "{{colors.primary.default.hex}}"
  '';

  skwdTemplatesDir = pkgs.runCommand "skwd-wall-templates" {} ''
    mkdir -p $out
    cp ${skwdWallPkg}/share/skwd-wall/data/matugen/templates/* $out/
    cp ${dmsDynamicColorsTemplate} $out/dms-colors.json
    cp ${hyprlandDmsTemplate} $out/hyprland-dms-colors.conf
    cp ${zathuraTemplate} $out/zathura-colors
    cp ${vesktopColorContractFile} $out/vesktop-color-contract.json
  '';

  configJson = builtins.toJSON {
    compositor = "hyprland";
    monitor = skwdDefaultMonitor;
    general = {
      locale = "";
      closeOnSelection = false;
      reopenAtLastSelection = true;
    };
    paths = {
      wallpaper = "~/wallpapers";
      videoWallpaper = "~/videowalls";
      cache = "";
      templates = "${skwdTemplatesDir}";
      scripts = skwdScriptDir;
      steam = steamLibraryDir;
      steamWorkshop = steamWorkshopDir;
      steamWeAssets = steamWeAssetsDir;
    };
    features = {
      matugen = true;
      ollama = true;
      steam = true;
      wallhaven = true;
    };
    colorSource = "magick";
    ollama = {
      url = "http://localhost:11434";
      model = "gemma3:4b";
      consolidateEnabled = true;
    };
    steam = {
      apiKey = "";
      username = "";
    };
    wallhaven = {
      apiKey = "";
    };
    matugen = {
      schemeType = "scheme-fidelity";
      mode = "dark";
    };
    integrations = [
      {
        name = "skwd-wall";
        template = "quickshell-colors.json";
        output = "colors.json";
      }
      {
        name = "dms-shell";
        template = "dms-colors.json";
        output = "~/.cache/DankMaterialShell/dms-colors.json";
      }
      {
        name = "hyprland-dms";
        template = "hyprland-dms-colors.conf";
        output = "~/.config/hypr/dms/colors.conf";
        reload = "${skwdScriptDir}/sync-dms-wallpaper.sh";
      }
      {
        name = "zathura";
        template = "zathura-colors";
        output = "~/.config/zathura/skwd-colors";
      }
      {
        name = "vesktop";
        template = "vesktop.css";
        output = "vesktop.css";
        reload = "${skwdScriptDir}/reload-vesktop.sh";
      }
    ];
    components = {
      wallpaperSelector = {
        displayMode = "slices";
        sliceSpacing = -30;
        hexScrollStep = 1;
        customPresets = {};
      };
    };
    wallpaperMute = true;
    performance = {
      imageOptimizePreset = "balanced";
      imageOptimizeResolution = "2k";
      videoConvertPreset = "balanced";
      videoConvertResolution = "2k";
      autoOptimizeImages = false;
      autoConvertVideos = false;
      imageTrashDays = 7;
      videoTrashDays = 7;
      autoDeleteImageTrash = false;
      autoDeleteVideoTrash = false;
    };
  };

  skwdConfigDefaults = pkgs.writeText "skwd-wall-config-defaults.json" configJson;
  skwdSecretsTemplate = pkgs.writeText "skwd-wall-secrets.env.template" ''
    # Optional local secrets for skwd-wall.
    # STEAM_API_KEY=your_steam_web_api_key
    # WALLHAVEN_API_KEY=your_wallhaven_api_key
  '';

  # Home Manager owns ~/.config/skwd-wall/config.json and rewrites it back to
  # the declarative defaults on activation. Keep this shared contract narrow:
  # preserve only small user-facing state here (currently locale) and move
  # host-specific runtime behavior to dedicated host modules.
  skwdPrepareState = pkgs.writeShellScript "skwd-wall-prepare-state" ''
    set -euo pipefail

    config_dir="$HOME/.config/skwd-wall"
    config_file="$config_dir/config.json"
    defaults_file="${skwdConfigDefaults}"
    secrets_file="${skwdSecretsFile}"
    secrets_template="${skwdSecretsTemplate}"

    mkdir -p "$config_dir"

    saved_locale=""
    if [ -f "$config_file" ]; then
      saved_locale="$(${pkgs.jq}/bin/jq -r '.general.locale // ""' "$config_file" 2>/dev/null || echo "")"
    fi

    tmp_file=$(mktemp)
    cp "$defaults_file" "$tmp_file"

    if [ -L "$config_file" ] || { [ -e "$config_file" ] && [ ! -w "$config_file" ]; }; then
      rm -f "$config_file"
    fi
    mv "$tmp_file" "$config_file"
    chmod 600 "$config_file"

    if [ -n "$saved_locale" ]; then
      tmp_patch=$(mktemp)
      ${pkgs.jq}/bin/jq --arg loc "$saved_locale" '.general.locale = $loc' "$config_file" > "$tmp_patch"
      mv "$tmp_patch" "$config_file"
      chmod 600 "$config_file"
    fi

    if [ ! -e "$secrets_file" ]; then
      cp "$secrets_template" "$secrets_file"
      chmod 600 "$secrets_file"
    fi
  '';
in {
  inherit skwdPrepareState;
}
