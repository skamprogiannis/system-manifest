{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.dms.homeModules.dank-material-shell
  ];

  xdg.configFile."DankMaterialShell/.firstlaunch".text = "";

  programs.dank-material-shell = {
    enable = true;
    systemd = {
      enable = true;
      target = "hyprland-session.target";
    };
    enableSystemMonitoring = true;
    enableDynamicTheming = true;
    enableClipboardPaste = true;
    enableCalendarEvents = false;
    enableVPN = true;
    enableAudioWavelength = true;
    settings = {
      # Keep settings declarative while removing setup prompts in DMS UI.
      barConfigs = [
        {
          id = "default";
          name = "Main Bar";
          enabled = true;
          position = 0;
          screenPreferences = ["BenQ XL2411Z"];
          showOnLastDisplay = true;
          leftWidgets = ["launcherButton" "workspaceSwitcher" "focusedWindow"];
          centerWidgets = ["music" "clock" "weather"];
          rightWidgets = ["systemTray" "clipboard" "cpuUsage" "memUsage" "notificationButton" "battery" "controlCenterButton"];
          spacing = 4;
          innerPadding = 4;
          bottomGap = 0;
          transparency = 1.0;
          widgetTransparency = 1.0;
          squareCorners = false;
          noBackground = false;
          maximizeWidgetIcons = false;
          maximizeWidgetText = false;
          removeWidgetPadding = false;
          widgetPadding = 8;
          gothCornersEnabled = false;
          gothCornerRadiusOverride = false;
          gothCornerRadiusValue = 12;
          borderEnabled = false;
          borderColor = "surfaceText";
          borderOpacity = 1.0;
          borderThickness = 1;
          widgetOutlineEnabled = false;
          widgetOutlineColor = "primary";
          widgetOutlineOpacity = 1.0;
          widgetOutlineThickness = 1;
          fontScale = 1.0;
          iconScale = 1.0;
          autoHide = false;
          autoHideDelay = 250;
          showOnWindowsOpen = false;
          openOnOverview = false;
          visible = true;
          popupGapsAuto = true;
          popupGapsManual = 4;
          maximizeDetection = true;
          scrollEnabled = true;
          scrollXBehavior = "column";
          scrollYBehavior = "workspace";
          shadowIntensity = 0;
          shadowOpacity = 60;
          shadowColorMode = "default";
          shadowCustomColor = "#000000";
          clickThrough = false;
        }
      ];

      # --- DISPLAYS & WIDGET SCREENS ---
      displayNameMode = "model";
      displaySnapToEdge = true;
      displayProfileAutoSelect = false;
      showDock = false;
      screenPreferences = {
        notifications = ["BenQ XL2411Z"];
        osd = ["BenQ XL2411Z"];
        toast = ["BenQ XL2411Z"];
        notepad = ["BenQ XL2411Z"];
      };
      showOnLastDisplay = {
        notifications = true;
        osd = true;
        toast = true;
        notepad = true;
      };

      # --- THEME & COLOR ---
      currentThemeName = "dynamic";
      currentThemeCategory = "dynamic";
      matugenScheme = "scheme-fidelity";
      matugenPaletteFidelity = 1;
      popupTransparency = 0.95;
      notepadTransparencyOverride = 0.95;
      systemMonitorTransparency = 0.95;

      # --- WORKSPACES ---
      showWorkspaceIndex = true;
      showWorkspaceName = false;
      showWorkspacePadding = false;
      showWorkspaceApps = false;
      workspaceFollowFocus = true;
      showOccupiedWorkspacesOnly = true;
      reverseScrolling = false;
      workspaceColorMode = "s";
      workspaceOccupiedColorMode = "none";
      workspaceUnfocusedColorMode = "s";
      workspaceUrgentColorMode = "primary";
      workspaceFocusedBorderEnabled = false;
      workspaceFocusedBorderColor = "primary";
      workspaceFocusedBorderThickness = 2;

      # --- LAUNCHER ---
      launcherLogoMode = "apps";
      launcherLogoSizeOffset = 5;
      sortAppsAlphabetically = false;
      appLauncherGridColumns = 4;
      dankLauncherV2Size = "compact";
      dankLauncherV2ShowFooter = true;
      dankLauncherV2BorderEnabled = true;
      dankLauncherV2BorderThickness = 2;
      dankLauncherV2BorderColor = "primary";
      launcherPluginVisibility = {
        dms_settings_search.allowWithoutTrigger = true;
      };
      builtInPluginSettings = {
        dms_settings.enabled = true;
        dms_notepad.enabled = true;
        dms_sysmon.enabled = true;
        dms_settings_search = {
          enabled = true;
          trigger = "?";
        };
      };
      appIdSubstitutions = [
        {
          pattern = "Spotify";
          replacement = "spotify";
          type = "exact";
        }
        {
          pattern = "beepertexts";
          replacement = "beeper";
          type = "exact";
        }
        {
          pattern = "home assistant desktop";
          replacement = "homeassistant-desktop";
          type = "exact";
        }
        {
          pattern = "com.transmissionbt.transmission";
          replacement = "transmission-gtk";
          type = "contains";
        }
        {
          pattern = "^steam_app_(\\d+)$";
          replacement = "steam_icon_$1";
          type = "regex";
        }
        {
          pattern = "spotify_player";
          replacement = "spotify";
          type = "exact";
        }
      ];

      # --- CURSOR ---
      cursorSettings = {
        theme = config.home.pointerCursor.name;
        size = config.home.pointerCursor.size;
        hyprland = {
          hideOnKeyPress = true;
          hideOnTouch = false;
          inactiveTimeout = 5;
        };
      };

      # --- GENERAL ---
      showSeconds = true;
      useAutoLocation = true;
      use24HourClock = true;
      cornerRadius = 12;
      enablePerModeWallpapers = false;
      nightModeEnabled = false;
      themeModeAutoEnabled = false;

      # --- POWER & SLEEP ---
      acMonitorTimeout = 600;
      acLockTimeout = 1800;
      acSuspendTimeout = 3600;
      lockBeforeSuspend = true;

      # --- LOCK SCREEN ---
      fadeToLockEnabled = true;
      fadeToDpmsEnabled = true;

      # --- NOTIFICATIONS ---
      notificationTimeoutNormal = 10000;
      notificationTimeoutLow = 5000;
      notificationHistorySaveLow = false;

      # --- MATUGEN TEMPLATES ---
      runDmsMatugenTemplates = true;
      runUserMatugenTemplates = true;
      matugenTemplateGtk = true;
      matugenTemplateHyprland = true;
      matugenTemplateFirefox = false;
      matugenTemplateVesktop = true;
      matugenTemplateGhostty = false;
      matugenTemplateNeovim = true;
      matugenTemplateZellij = true;
      matugenTemplateDgop = true;
      matugenTemplateKcolorscheme = true;
      matugenTemplateNiri = false;
      matugenTemplateMangowc = false;
      matugenTemplateQt5ct = false;
      matugenTemplateQt6ct = false;
      matugenTemplatePywalfox = false;
      matugenTemplateZenBrowser = false;
      matugenTemplateEquibop = false;
      matugenTemplateKitty = false;
      matugenTemplateFoot = false;
      matugenTemplateAlacritty = false;
      matugenTemplateWezterm = false;
      matugenTemplateVscode = false;
      matugenTemplateEmacs = false;
    };

    session = {
      nightModeEnabled = false;
      nightModeAutoEnabled = false;
      themeModeAutoEnabled = false;
      themeModeShareGammaSettings = false;
      nightModeUseIPLocation = false;
    };
  };
}
