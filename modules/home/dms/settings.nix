{config, ...}: let
  wallpaperContracts = import ../wallpaper/contracts.nix;
  monitorIdentity = wallpaperContracts.dmsMonitorIdentity;
  sessionDefaults = wallpaperContracts.dmsSessionDefaults;
  enabledWidget = id: {
    inherit id;
    enabled = true;
  };
  monitorPreference = monitor: {
    name = monitor.connector;
    model = monitor.model;
  };
  commonBarStyle = {
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
    maximizeDetection = false;
    scrollEnabled = true;
    scrollXBehavior = "column";
    scrollYBehavior = "workspace";
    shadowIntensity = 0;
    shadowOpacity = 60;
    shadowColorMode = "default";
    shadowCustomColor = "#000000";
    clickThrough = false;
  };
  topShadowStyle = {
    shadowDirectionMode = "inherit";
    shadowDirection = "top";
  };
  compactRunningAppsWidget = {
    id = "runningApps";
    enabled = true;
    runningAppsCompactMode = true;
    runningAppsGroupByApp = false;
    runningAppsCurrentWorkspace = true;
    runningAppsCurrentMonitor = false;
  };
  compactFocusedWindowWidget = {
    id = "focusedWindow";
    enabled = true;
    focusedWindowCompactMode = true;
  };
in {
  programs.dank-material-shell.settings = {
    # Keep settings declarative while removing setup prompts in DMS UI.
    barConfigs = [
      (commonBarStyle // {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0;
        screenPreferences = [
          (monitorPreference monitorIdentity.primary)
        ];
        showOnLastDisplay = false;
        leftWidgets = [
          "workspaceSwitcher"
          compactRunningAppsWidget
          compactFocusedWindowWidget
          (enabledWidget "systemTray")
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
            mediaSize = 1;
          }
          {
            id = "weather";
            enabled = true;
          }
        ];
        rightWidgets = [
          (enabledWidget "cpuUsage")
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
          (enabledWidget "notificationButton")
          (enabledWidget "battery")
          (enabledWidget "controlCenterButton")
        ];
      })
      (commonBarStyle // topShadowStyle // {
        id = "bar1774633251014";
        name = "Secondary Bar";
        enabled = true;
        position = 0;
        screenPreferences = [
          (monitorPreference monitorIdentity.secondary)
        ];
        showOnLastDisplay = false;
        leftWidgets = [
          (enabledWidget "launcherButton")
          (enabledWidget "clipboard")
          (enabledWidget "notepadButton")
          (enabledWidget "colorPicker")
          (enabledWidget "idleInhibitor")
          (enabledWidget "powerMenuButton")
        ];
        centerWidgets = [
          (enabledWidget "network_speed_monitor")
          (enabledWidget "vpn")
        ];
        rightWidgets = [
          {
            id = "keyboard_layout_name";
            enabled = true;
            keyboardLayoutNameCompactMode = false;
          }
          compactFocusedWindowWidget
          compactRunningAppsWidget
          (enabledWidget "workspaceSwitcher")
        ];
      })
      (commonBarStyle // topShadowStyle // {
        id = "bar1774633251575";
        name = "Unified Bar";
        enabled = true;
        position = 0;
        screenPreferences = [];
        showOnLastDisplay = true;
        leftWidgets = [
          (enabledWidget "launcherButton")
          (enabledWidget "workspaceSwitcher")
          (enabledWidget "systemTray")
          compactRunningAppsWidget
          (enabledWidget "focusedWindow")
        ];
        centerWidgets = [
          {
            id = "clock";
            enabled = true;
            clockCompactMode = true;
            showSeconds = false;
          }
          {
            id = "music";
            enabled = true;
            mediaSize = 0;
          }
          "weather"
        ];
        rightWidgets = [
          (enabledWidget "cpuUsage")
          {
            id = "memUsage";
            enabled = true;
            showSwap = true;
          }
          {
            id = "gpuTemp";
            enabled = true;
            selectedGpuIndex = 0;
            pciId = "";
            minimumWidth = true;
          }
          (enabledWidget "notificationButton")
          (enabledWidget "battery")
          (enabledWidget "controlCenterButton")
        ];
      })
    ];

    # --- DISPLAYS & WIDGET SCREENS ---
    displayNameMode = monitorIdentity.displayNameMode;
    displaySnapToEdge = true;
    displayProfileAutoSelect = false;
    showDock = false;
    screenPreferences = {
      wallpaper = [];
      notifications = [monitorIdentity.primary.dmsDisplayName];
      osd = [monitorIdentity.primary.dmsDisplayName];
      toast = [monitorIdentity.primary.dmsDisplayName];
      notepad = [monitorIdentity.primary.dmsDisplayName];
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
    widgetColorMode = "colorful";
    blurEnabled = true;
    blurBorderColor = "primary";
    blurBorderOpacity = 0.60;
    popupTransparency = 0.60;
    notepadTransparencyOverride = 0.70;
    systemMonitorTransparency = 0.70;

    # --- WORKSPACES ---
    showWorkspaceIndex = true;
    showWorkspaceName = false;
    showWorkspacePadding = false;
    showWorkspaceApps = false;
    workspaceFollowFocus = false;
    showOccupiedWorkspacesOnly = true;
    reverseScrolling = false;
    workspaceColorMode = "default";
    workspaceOccupiedColorMode = "none";
    workspaceUnfocusedColorMode = "default";
    workspaceUrgentColorMode = "default";
    workspaceFocusedBorderEnabled = false;
    workspaceFocusedBorderColor = "primary";
    workspaceFocusedBorderThickness = 2;

    # --- LAUNCHER ---
    launcherLogoMode = "os";
    launcherLogoColorOverride = "primary";
    launcherLogoSizeOffset = 5;
    sortAppsAlphabetically = false;
    appLauncherGridColumns = 4;
    dankLauncherV2Size = "compact";
    dankLauncherV2ShowFooter = false;
    dankLauncherV2BorderEnabled = true;
    dankLauncherV2BorderThickness = 2;
    dankLauncherV2BorderColor = "primary";
    launcherPluginVisibility = {
      dms_settings.allowWithoutTrigger = false;
      dms_notepad.allowWithoutTrigger = false;
      dms_settings_search.allowWithoutTrigger = false;
    };
    builtInPluginSettings = {
      dms_settings.enabled = false;
      dms_notepad.enabled = false;
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
    nightModeEnabled = sessionDefaults.nightModeEnabled;
    themeModeAutoEnabled = sessionDefaults.themeModeAutoEnabled;

    # --- OSD ---
    osdCapsLockEnabled = false;
    osdPowerProfileEnabled = true;

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
    # Intentionally unmanaged here: updater behavior depends on host-specific,
    # non-Nix commands, so we do not force it declaratively.

    # --- MATUGEN TEMPLATES ---
    runDmsMatugenTemplates = true;
    runUserMatugenTemplates = true;
    matugenTemplateGtk = true;
    matugenTemplateHyprland = true;
    matugenTemplateFirefox = false;
    matugenTemplateVesktop = false;
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
}
