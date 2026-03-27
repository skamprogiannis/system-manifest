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
          screenPreferences = [
            {
              name = "DP-1";
              model = "BenQ XL2411Z";
            }
          ];
          showOnLastDisplay = false;
          leftWidgets = [
            "workspaceSwitcher"
            {
              id = "runningApps";
              enabled = true;
              runningAppsCompactMode = true;
              runningAppsGroupByApp = false;
              runningAppsCurrentWorkspace = true;
              runningAppsCurrentMonitor = false;
            }
            {
              id = "systemTray";
              enabled = true;
            }
          ];
          centerWidgets = [
            {
              id = "clock";
              enabled = true;
              clockCompactMode = false;
            }
            {
              id = "music";
              enabled = true;
              mediaSize = 2;
            }
            {
              id = "weather";
              enabled = true;
            }
          ];
          rightWidgets = [
            {
              id = "cpuUsage";
              enabled = true;
            }
            {
              id = "memUsage";
              enabled = true;
              showSwap = true;
            }
            {
              id = "gpuTemp";
              enabled = true;
              selectedGpuIndex = 0;
              pciId = "10de:220a";
            }
            {
              id = "notificationButton";
              enabled = true;
            }
            {
              id = "battery";
              enabled = true;
            }
            {
              id = "controlCenterButton";
              enabled = true;
            }
          ];
          spacing = 4;
          innerPadding = 4;
          bottomGap = -2;
          transparency = 0.55;
          widgetTransparency = 0.6;
          squareCorners = false;
          noBackground = false;
          maximizeWidgetIcons = false;
          maximizeWidgetText = false;
          removeWidgetPadding = false;
          widgetPadding = 12;
          gothCornersEnabled = false;
          gothCornerRadiusOverride = false;
          gothCornerRadiusValue = 12;
          borderEnabled = true;
          borderColor = "primary";
          borderOpacity = 1.0;
          borderThickness = 2;
          widgetOutlineEnabled = false;
          widgetOutlineColor = "primary";
          widgetOutlineOpacity = 1.0;
          widgetOutlineThickness = 1;
          fontScale = 1.0;
          iconScale = 1.1;
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
        {
          id = "bar1774633251014";
          name = "Secondary Bar";
          enabled = true;
          position = 0;
          screenPreferences = [
            {
              name = "HDMI-A-1";
              model = "S24E510C";
            }
          ];
          showOnLastDisplay = false;
          leftWidgets = [
            {
              id = "launcherButton";
              enabled = true;
            }
            {
              id = "clipboard";
              enabled = true;
            }
            {
              id = "notepadButton";
              enabled = true;
            }
            {
              id = "colorPicker";
              enabled = true;
            }
            {
              id = "idleInhibitor";
              enabled = true;
            }
            {
              id = "powerMenuButton";
              enabled = true;
            }
          ];
          centerWidgets = [
            {
              id = "network_speed_monitor";
              enabled = true;
            }
            {
              id = "vpn";
              enabled = true;
            }
          ];
          rightWidgets = [
            {
              id = "keyboard_layout_name";
              enabled = true;
            }
            {
              id = "workspaceSwitcher";
              enabled = true;
            }
            {
              id = "focusedWindow";
              enabled = true;
            }
          ];
          spacing = 4;
          innerPadding = 4;
          bottomGap = -2;
          transparency = 0.55;
          widgetTransparency = 0.6;
          squareCorners = false;
          noBackground = false;
          maximizeWidgetIcons = false;
          maximizeWidgetText = false;
          removeWidgetPadding = false;
          widgetPadding = 12;
          gothCornersEnabled = false;
          gothCornerRadiusOverride = false;
          gothCornerRadiusValue = 12;
          borderEnabled = true;
          borderColor = "primary";
          borderOpacity = 1.0;
          borderThickness = 2;
          widgetOutlineEnabled = false;
          widgetOutlineColor = "primary";
          widgetOutlineOpacity = 1.0;
          widgetOutlineThickness = 1;
          fontScale = 1.0;
          iconScale = 1.1;
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
          shadowDirectionMode = "inherit";
          shadowDirection = "top";
          shadowColorMode = "default";
          shadowCustomColor = "#000000";
          clickThrough = false;
        }
        {
          id = "bar1774633251575";
          name = "Unified Bar";
          enabled = true;
          position = 0;
          screenPreferences = [];
          showOnLastDisplay = true;
          leftWidgets = ["launcherButton" "workspaceSwitcher" "focusedWindow"];
          centerWidgets = ["music" "clock" "weather"];
          rightWidgets = ["systemTray" "clipboard" "cpuUsage" "memUsage" "notificationButton" "battery" "controlCenterButton"];
          spacing = 4;
          innerPadding = 4;
          bottomGap = -2;
          transparency = 0.55;
          widgetTransparency = 0.6;
          squareCorners = false;
          noBackground = false;
          maximizeWidgetIcons = false;
          maximizeWidgetText = false;
          removeWidgetPadding = false;
          widgetPadding = 12;
          gothCornersEnabled = false;
          gothCornerRadiusOverride = false;
          gothCornerRadiusValue = 12;
          borderEnabled = true;
          borderColor = "primary";
          borderOpacity = 1.0;
          borderThickness = 2;
          widgetOutlineEnabled = false;
          widgetOutlineColor = "primary";
          widgetOutlineOpacity = 1.0;
          widgetOutlineThickness = 1;
          fontScale = 1.0;
          iconScale = 1.1;
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
          shadowDirectionMode = "inherit";
          shadowDirection = "top";
          shadowColorMode = "default";
          shadowCustomColor = "#000000";
          clickThrough = false;
        }
      ];

      # --- DISPLAYS & WIDGET SCREENS ---
      displayNameMode = "system";
      displaySnapToEdge = true;
      displayProfileAutoSelect = false;
      showDock = false;
      screenPreferences = {};
      showOnLastDisplay = {};

      # --- THEME & COLOR ---
      currentThemeName = "dynamic";
      currentThemeCategory = "dynamic";
      matugenScheme = "scheme-fidelity";
      matugenPaletteFidelity = 1;
      widgetColorMode = "default";
      popupTransparency = 1.0;
      notepadTransparencyOverride = -1;
      systemMonitorTransparency = 0.8;

      # --- WORKSPACES ---
      showWorkspaceIndex = false;
      showWorkspaceName = false;
      showWorkspacePadding = false;
      showWorkspaceApps = false;
      workspaceFollowFocus = false;
      showOccupiedWorkspacesOnly = false;
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
      launcherLogoSizeOffset = 0;
      sortAppsAlphabetically = false;
      appLauncherGridColumns = 4;
      dankLauncherV2Size = "compact";
      dankLauncherV2ShowFooter = true;
      dankLauncherV2BorderEnabled = false;
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

      # --- SYSTEM UPDATER ---
      updaterHideWidget = false;
      updaterUseCustomCommand = false;
      updaterCustomCommand = "";
      updaterTerminalAdditionalParams = "";

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
