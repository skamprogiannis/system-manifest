{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  patchDmsPackage = import ./patch-package.nix {inherit pkgs;};
  dmsPatchedPackage = patchDmsPackage {
    package = dmsBasePackage;
    pythonPrelude = ''
      settings_shell_alpha = "Math.min(1.0, Theme.popupTransparency + 0.08)"
      settings_header_alpha = "Math.min(1.0, Theme.popupTransparency + 0.10)"
    '';
    replacementsPython = ''
      root / "Modals/Settings/SettingsModal.qml": [
          ("property bool disablePopupTransparency: true", "property bool disablePopupTransparency: false"),
          ("color: Theme.surfaceContainer", "color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)"),
          (
              "                    color: Theme.surfaceContainer\n                    opacity: 0.5",
              f"                    color: Theme.withAlpha(Theme.surfaceContainer, {settings_header_alpha})\n                    opacity: 1.0",
          ),
          (
              "                color: Theme.surfaceContainerHigh",
              f"                color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
          ),
      ],
      root / "Modals/Settings/SettingsSidebar.qml": [
          (
              "    color: Theme.surfaceContainer",
              f"    color: Theme.withAlpha(Theme.surfaceContainer, {settings_shell_alpha})",
          ),
      ],
      root / "Modules/Settings/Widgets/SettingsCard.qml": [
          (
              "    color: Theme.surfaceContainerHigh",
              f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
          ),
      ],
      root / "Modules/Settings/Widgets/SettingsSliderCard.qml": [
          (
              "    color: Theme.surfaceContainerHigh",
              f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
          ),
      ],
      root / "Modules/Settings/Widgets/SettingsToggleCard.qml": [
          (
              "    color: Theme.surfaceContainerHigh",
              f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
          ),
      ],
      root / "Modules/Settings/Widgets/SystemMonitorVariantCard.qml": [
          (
              "    color: Theme.surfaceContainerHigh",
              f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
          ),
      ],
      root / "Widgets/DankPopout.qml": [
          (
              "targetColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)",
              'targetColor: Theme.withAlpha(Theme.surfaceContainer, root.layerNamespace === "dms:dash" ? Math.max(0.0, Theme.popupTransparency - 0.12) : Theme.popupTransparency)',
          ),
          (
              "color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)",
              'color: Theme.withAlpha(Theme.surfaceContainer, root.layerNamespace === "dms:dash" ? Math.max(0.0, Theme.popupTransparency - 0.12) : Theme.popupTransparency)',
          ),
      ],
      root / "Modules/DankDash/Overview/Card.qml": [
          (
              "color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)",
              "color: Theme.withAlpha(Theme.surfaceContainerHigh, Math.max(0.0, Theme.popupTransparency - 0.22))",
          ),
      ],
      root / "Modules/DankDash/Overview/CalendarOverviewCard.qml": [
          (
              "color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)",
              "color: Theme.withAlpha(Theme.surfaceContainerHigh, Math.max(0.0, Theme.popupTransparency - 0.22))",
          ),
      ],
      root / "Services/AppSearchService.qml": [
          (
              '                comment: "DMS",\n                action: "ipc:processlist",',
              '                comment: "Inspect processes and live system usage",\n                action: "ipc:processlist",',
          ),
          (
              '                comment: "DMS",\n                action: "ipc:color-picker",',
              '                comment: "Sample colors from anywhere on screen",\n                action: "ipc:color-picker",',
          ),
      ],
      root / "Common/settings/Lists.qml": [
          (
              "            mediaSize: 1,\n",
              "            mediaSize: 1,\n            showSeconds: true,\n",
          ),
          (
              "            if (isObj && order[i].mediaSize !== undefined)\n                item.mediaSize = order[i].mediaSize;\n",
              "            if (isObj && order[i].mediaSize !== undefined)\n                item.mediaSize = order[i].mediaSize;\n            if (isObj && order[i].showSeconds !== undefined)\n                item.showSeconds = order[i].showSeconds;\n",
          ),
      ],
      root / "Modules/DankBar/Widgets/Clock.qml": [
          (
              "            readonly property bool compact: widgetData?.clockCompactMode !== undefined ? widgetData.clockCompactMode : SettingsData.clockCompactMode\n",
              "            readonly property bool compact: widgetData?.clockCompactMode !== undefined ? widgetData.clockCompactMode : SettingsData.clockCompactMode\n            readonly property bool showSeconds: widgetData?.showSeconds !== undefined ? widgetData.showSeconds : SettingsData.showSeconds\n",
          ),
          (
              "                    visible: SettingsData.showSeconds\n",
              "                    visible: showSeconds\n",
          ),
          (
              "                        visible: SettingsData.showSeconds\n",
              "                        visible: showSeconds\n",
          ),
          (
              "                precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes\n",
              "                precision: showSeconds ? SystemClock.Seconds : SystemClock.Minutes\n",
          ),
      ],
      # Expose a clearHistory IPC command so keybinds can wipe the History tab.
      # The built-in clearAll IPC only calls clearAllNotifications(); this adds
      # a sibling function that delegates to NotificationService.clearHistory().
      root / "Modals/NotificationModal.qml": [
          (
              '        function clearAll(): string {\n            notificationModal.clearAll();\n            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";\n        }',
              '        function clearAll(): string {\n            notificationModal.clearAll();\n            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";\n        }\n\n        function clearHistory(): string {\n            NotificationService.clearHistory();\n            return "NOTIFICATION_MODAL_CLEAR_HISTORY_SUCCESS";\n        }',
          ),
      ],
    '';
  };
in {
  imports = [
    inputs.dms.homeModules.dank-material-shell
  ];

  xdg.configFile."DankMaterialShell/.firstlaunch".text = "";

  home.activation.ensureWritableDmsSession = lib.hm.dag.entryAfter ["writeBoundary"] ''
        state_dir="$HOME/.local/state/DankMaterialShell"
        session_file="$state_dir/session.json"

        mkdir -p "$state_dir"

        if [ -L "$session_file" ] || { [ -e "$session_file" ] && [ ! -w "$session_file" ]; }; then
          tmp_file=$(mktemp)
          if ! cat "$session_file" > "$tmp_file" 2>/dev/null; then
            cat > "$tmp_file" <<'EOF'
    {"nightModeEnabled":false,"nightModeAutoEnabled":false,"themeModeAutoEnabled":false,"themeModeShareGammaSettings":false,"nightModeUseIPLocation":false}
    EOF
          fi
          rm -f "$session_file"
          mv "$tmp_file" "$session_file"
          chmod 600 "$session_file"
        elif [ ! -e "$session_file" ]; then
          cat > "$session_file" <<'EOF'
    {"nightModeEnabled":false,"nightModeAutoEnabled":false,"themeModeAutoEnabled":false,"themeModeShareGammaSettings":false,"nightModeUseIPLocation":false}
    EOF
          chmod 600 "$session_file"
        fi
  '';

  programs.dank-material-shell = {
    enable = true;
    package = dmsPatchedPackage;
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
              mediaSize = 1;
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
          maximizeDetection = false;
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
              id = "focusedWindow";
              enabled = true;
            }
            {
              id = "workspaceSwitcher";
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
          maximizeDetection = false;
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
          leftWidgets = [
            {
              id = "launcherButton";
              enabled = true;
            }
            {
              id = "workspaceSwitcher";
              enabled = true;
            }
            {
              id = "systemTray";
              enabled = true;
            }
            {
              id = "runningApps";
              enabled = true;
              runningAppsCompactMode = true;
              runningAppsGroupByApp = false;
              runningAppsCurrentWorkspace = true;
              runningAppsCurrentMonitor = false;
            }
            {
              id = "focusedWindow";
              enabled = true;
            }
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
              pciId = "";
              minimumWidth = true;
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
          maximizeDetection = false;
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
      widgetColorMode = "colorful";
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
      nightModeEnabled = false;
      themeModeAutoEnabled = false;

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
  };
}
