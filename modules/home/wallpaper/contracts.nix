let
  wallpaperTransitions = let
    included = [
      "fade"
      "wipe"
      "disc"
      "stripes"
      "iris bloom"
      "pixelate"
      "portal"
    ];
  in {
    default = "disc";
    inherit included;
    allowed = included ++ [
      "none"
      "random"
    ];
  };
in {
  dmsMonitorIdentity = {
    displayNameMode = "model";
    primary = {
      connector = "DP-1";
      model = "BenQ XL2411Z";
      dmsDisplayName = "BenQ XL2411Z";
    };
    secondary = {
      connector = "HDMI-A-1";
      model = "S24E510C";
      dmsDisplayName = "S24E510C";
    };
  };

  inherit wallpaperTransitions;

  dmsSessionDefaults = {
    nightModeEnabled = false;
    nightModeAutoEnabled = false;
    themeModeAutoEnabled = false;
    themeModeShareGammaSettings = false;
    nightModeUseIPLocation = false;
    isLightMode = false;
    wallpaperTransition = wallpaperTransitions.default;
    includedTransitions = wallpaperTransitions.included;
  };

  dmsWallpaperSessionSync = {
    forcedFlags = {
      perModeWallpaper = false;
      perMonitorWallpaper = false;
      wallpaperCyclingEnabled = false;
      isLightMode = false;
    };
    wallpaperPathKeys = [
      "wallpaperPath"
      "wallpaperPathLight"
      "wallpaperPathDark"
    ];
    monitorWallpaperKeys = [
      "monitorWallpapers"
      "monitorWallpapersLight"
      "monitorWallpapersDark"
    ];
    monitorCyclingSettingsKey = "monitorCyclingSettings";
  };

  skwdColorContract = {
    requiredTokens = [
      "background"
      "error"
      "inversePrimary"
      "onPrimary"
      "outline"
      "primary"
      "primaryContainer"
      "surface"
      "surfaceContainer"
      "surfaceText"
      "surfaceVariant"
      "surfaceVariantText"
      "tertiary"
      "tertiaryContainer"
    ];
    accentFallbackTokens = [
      "primary"
      "primaryContainer"
    ];
    vesktopMappings = [
      {
        cssVar = "--online-indicator";
        token = "inversePrimary";
      }
      {
        cssVar = "--dnd-indicator";
        token = "error";
      }
      {
        cssVar = "--idle-indicator";
        token = "tertiaryContainer";
      }
      {
        cssVar = "--streaming-indicator";
        token = "onPrimary";
      }
      {
        cssVar = "--accent-1";
        token = "tertiary";
      }
      {
        cssVar = "--accent-2";
        token = "primary";
      }
      {
        cssVar = "--accent-3";
        token = "primary";
      }
      {
        cssVar = "--accent-4";
        token = "surfaceContainer";
      }
      {
        cssVar = "--accent-5";
        token = "primaryContainer";
      }
      {
        cssVar = "--mention";
        token = "surface";
      }
      {
        cssVar = "--mention-hover";
        token = "surfaceContainer";
      }
      {
        cssVar = "--text-0";
        token = "surface";
      }
      {
        cssVar = "--text-1";
        token = "surfaceText";
      }
      {
        cssVar = "--text-2";
        token = "surfaceText";
      }
      {
        cssVar = "--text-3";
        token = "surfaceVariantText";
      }
      {
        cssVar = "--text-4";
        token = "surfaceVariantText";
      }
      {
        cssVar = "--text-5";
        token = "outline";
      }
      {
        cssVar = "--bg-1";
        token = "surfaceVariant";
      }
      {
        cssVar = "--bg-2";
        token = "surfaceContainer";
      }
      {
        cssVar = "--bg-3";
        token = "surface";
      }
      {
        cssVar = "--bg-4";
        token = "background";
      }
      {
        cssVar = "--hover";
        token = "surfaceContainer";
      }
      {
        cssVar = "--active";
        token = "surfaceContainer";
      }
      {
        cssVar = "--message-hover";
        token = "surfaceContainer";
      }
    ];
  };
}
