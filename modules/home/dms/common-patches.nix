{skwdWallPackage}: let
  skwdBin = "\\\"${skwdWallPackage}/bin/skwd\\\"";

  overviewCard = ''
    root / "Modules/DankDash/Overview/Card.qml": [
        (
            "color: Theme.nestedSurface",
            "color: Theme.withAlpha(Theme.nestedSurface, Math.max(0.0, Theme.popupTransparency - 0.22))",
        ),
    ],
  '';

  calendarOverviewCard = ''
    root / "Modules/DankDash/Overview/CalendarOverviewCard.qml": [
        (
            "color: Theme.nestedSurface",
            "color: Theme.withAlpha(Theme.nestedSurface, Math.max(0.0, Theme.popupTransparency - 0.22))",
        ),
    ],
  '';

  appSearchService = ''
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
  '';

  launcherSourceClassifier = ''
    root / "Modals/DankLauncherV2/ControllerUtils.js": [
        (
            '    if (exec.indexOf("/nix/store/") !== -1\n        || exec.indexOf("/run/current-system/sw/") !== -1\n        || exec.indexOf("/etc/profiles/per-user/") !== -1)\n        return "nix";\n\n    return "system";',
            '    if (exec.indexOf("steam://rungameid/") !== -1)\n        return "system";\n\n    if (exec.indexOf("/nix/store/") !== -1\n        || exec.indexOf("/run/current-system/sw/") !== -1\n        || exec.indexOf("/etc/profiles/per-user/") !== -1)\n        return "nix";\n\n    if (cmd0.length > 0 && cmd0.indexOf("/") === -1)\n        return "nix";\n\n    return "system";',
        ),
    ],
  '';

  commonLists = ''
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
  '';

  clockWidget = ''
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
            "                        visible: SettingsData.showSeconds\n",
            "                        visible: showSeconds\n",
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
  '';

  notificationModal = ''
    root / "Modals/NotificationModal.qml": [
        (
            '        function clearAll(): string {\n            notificationModal.clearAll();\n            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";\n        }',
            '        function clearAll(): string {\n            notificationModal.clearAll();\n            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";\n        }\n\n        function clearHistory(): string {\n            NotificationService.clearHistory();\n            return "NOTIFICATION_MODAL_CLEAR_HISTORY_SUCCESS";\n        }',
        ),
    ],
  '';

  dankPopoutBase = ''
    (
        "targetColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)",
        'targetColor: Theme.withAlpha(Theme.surfaceContainer, root.layerNamespace === "dms:dash" ? Math.max(0.0, Theme.popupTransparency - 0.12) : Theme.popupTransparency)',
    ),
  '';

  popoutBorderFallback = ''
    (
        "                border.width: BlurService.borderWidth",
        "                border.width: BlurService.enabled ? BlurService.borderWidth : 1",
    ),
  '';

  modalStandaloneBorderFallback = ''
    (
                        "                        border.color: BlurService.borderColor",
                        "                        border.color: BlurService.enabled ? BlurService.borderColor : Theme.outlineMedium",
    ),
    (
                        "                        border.width: BlurService.borderWidth",
                        "                        border.width: BlurService.enabled ? BlurService.borderWidth : 1",
    ),
  '';

  modalConnectedBorderFallback = ''
    (
        '                        border.color: (root.connectedSurfaceOverride || root.frameOwnsConnectedChrome) ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor',
        '                        border.color: (root.connectedSurfaceOverride || root.frameOwnsConnectedChrome) ? Theme.withAlpha(BlurService.borderColor, 0) : (BlurService.enabled ? BlurService.borderColor : Theme.outlineMedium)',
    ),
    (
        '                        border.width: (root.connectedSurfaceOverride || root.frameOwnsConnectedChrome) ? 0 : BlurService.borderWidth',
        '                        border.width: (root.connectedSurfaceOverride || root.frameOwnsConnectedChrome) ? 0 : (BlurService.enabled ? BlurService.borderWidth : 1)',
    ),
  '';

  launcherBorderFallback = ''
    (
        "                borderColor: root.borderColor",
        "                borderColor: BlurService.enabled ? BlurService.borderColor : root.borderColor",
    ),
    (
        "                borderWidth: root.borderWidth",
        "                borderWidth: BlurService.enabled ? BlurService.borderWidth : root.borderWidth",
    ),
    (
        "                border.color: BlurService.borderColor",
        "                border.color: BlurService.enabled ? BlurService.borderColor : root.borderColor",
    ),
    (
        "                border.width: BlurService.borderWidth",
        "                border.width: BlurService.enabled ? BlurService.borderWidth : root.borderWidth",
    ),
    (
        "                color: \"transparent\"\n                border.color:",
        "                color: \"transparent\"\n                antialiasing: true\n                border.color:",
    ),
  '';

  notificationPopupBorderFallback = ''
    (
        '            border.color: win.connectedFrameMode ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor',
        '            border.color: win.connectedFrameMode ? Theme.withAlpha(BlurService.borderColor, 0) : (BlurService.enabled ? BlurService.borderColor : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12))',
    ),
    (
        "            border.width: win.connectedFrameMode ? 0 : BlurService.borderWidth",
        "            border.width: win.connectedFrameMode ? 0 : (BlurService.enabled ? BlurService.borderWidth : 1)",
    ),
  '';

  wallpaperCyclingExternalSet = ''
    root / "Services/WallpaperCyclingService.qml": [
        (
            "        function clear(): string {\n            SessionData.setWallpaper(\"\");",
            "        function externalSet(path: string, mode: string): string {\n            if (!path) {\n                return \"ERROR: No path provided\";\n            }\n\n            SessionData.wallpaperCyclingEnabled = false;\n            SessionData.perMonitorWallpaper = false;\n            SessionData.perModeWallpaper = false;\n            SessionData.monitorWallpapers = ({});\n            SessionData.monitorWallpapersLight = ({});\n            SessionData.monitorWallpapersDark = ({});\n            SessionData.monitorCyclingSettings = ({});\n            SessionData.isLightMode = mode === \"light\";\n            SessionData.wallpaperPath = path;\n            SessionData.wallpaperPathLight = path;\n            SessionData.wallpaperPathDark = path;\n            SessionData.saveSettings();\n\n            if (typeof Theme !== \"undefined\") {\n                Theme.generateSystemThemesFromCurrentTheme();\n            }\n\n            return \"SUCCESS: External wallpaper set to \" + path;\n        }\n\n        function clear(): string {\n            SessionData.setWallpaper(\"\");",
        ),
    ],
  '';
in {
  # Keep only behavior that upstream DMS does not expose declaratively.
  defaultReplacementsPython = ''
    root / "Widgets/DankPopoutStandalone.qml": [
      ${dankPopoutBase}
      ${popoutBorderFallback}
    ],
    root / "Modals/Common/DankModalStandalone.qml": [
      ${modalStandaloneBorderFallback}
    ],
    root / "Modals/Common/DankModalConnected.qml": [
      ${modalConnectedBorderFallback}
    ],
    root / "Modals/DankLauncherV2/DankLauncherV2ModalStandalone.qml": [
      ${launcherBorderFallback}
    ],
    root / "Modules/Notifications/Popup/NotificationPopup.qml": [
      ${notificationPopupBorderFallback}
    ],
    ${overviewCard}
    ${calendarOverviewCard}
    ${appSearchService}
    ${launcherSourceClassifier}
    ${commonLists}
    ${clockWidget}
    ${wallpaperCyclingExternalSet}
    # Expose a clearHistory IPC command so keybinds can wipe the History tab.
    # The built-in clearAll IPC only calls clearAllNotifications(); this adds
    # a sibling function that delegates to NotificationService.clearHistory().
    ${notificationModal}
  '';

  # USB-specific patches support the software-rendered portable session.
  usbReplacementsPython = ''
    root / "Widgets/DankPopoutStandalone.qml": [
      ${dankPopoutBase}
      ${popoutBorderFallback}
    ],
    root / "Modals/Common/DankModalStandalone.qml": [
      ${modalStandaloneBorderFallback}
    ],
    root / "Modals/Common/DankModalConnected.qml": [
      ${modalConnectedBorderFallback}
    ],
    root / "Modals/DankLauncherV2/DankLauncherV2ModalStandalone.qml": [
      ${launcherBorderFallback}
    ],
    root / "Modules/Notifications/Popup/NotificationPopup.qml": [
      ${notificationPopupBorderFallback}
    ],
    ${overviewCard}
    ${calendarOverviewCard}
    ${appSearchService}
    ${launcherSourceClassifier}
    ${wallpaperCyclingExternalSet}
    root / "DankCommon/Widgets/CachingImage.qml": [
        (
            "import QtQuick\nimport qs.DankCommon.Common",
            "import QtQuick\nimport Quickshell\nimport qs.DankCommon.Common",
        ),
        (
            "                if (root._fromCache || root.isRemoteUrl || !root.cachePath)",
            '                if (root._fromCache || root.isRemoteUrl || !root.cachePath || Quickshell.env("QT_QUICK_BACKEND") === "software")',
        ),
        (
            "        // Cache-first; a miss errors and falls back to encodedImagePath\n        _fromCache = true;\n        staticImg.source = `''${Paths.stringify(Paths.imagecache)}/''${hash}@''${maxCacheSize}x''${maxCacheSize}.png`;",
            "        if (Quickshell.env(\"QT_QUICK_BACKEND\") === \"software\") {\n            _fromCache = false;\n            staticImg.source = encoded;\n            return;\n        }\n        // Cache-first; a miss errors and falls back to encodedImagePath\n        _fromCache = true;\n        staticImg.source = `''${Paths.stringify(Paths.imagecache)}/''${hash}@''${maxCacheSize}x''${maxCacheSize}.png`;",
        ),
    ],
    root / "Modules/Settings/WallpaperTab.qml": [
        (
            "    Component.onCompleted: {",
            """    function launchSkwdWall() {
        Quickshell.execDetached(["skwd-wall"]);
    }

    Component.onCompleted: {""",
        ),
        (
            "        mainWallpaperBrowserLoader.active = true;",
            "        launchSkwdWall();\n        return;",
        ),
        (
            "        lightWallpaperBrowserLoader.active = true;",
            "        launchSkwdWall();\n        return;",
        ),
        (
            "        darkWallpaperBrowserLoader.active = true;",
            "        launchSkwdWall();\n        return;",
        ),
        (
            "                                                    SessionData.setMonitorWallpaper(selectedMonitorName, selectedColor);",
            "                                                    root.launchSkwdWall();\n                                                    return;",
        ),
        (
            "                                                    SessionData.setWallpaperColor(selectedColor);",
            "                                                    root.launchSkwdWall();\n                                                    return;",
        ),
        (
            "                                                SessionData.setMonitorWallpaper(selectedMonitorName, \"\");",
            "                                                root.launchSkwdWall();\n                                                return;",
        ),
        (
            "                                                SessionData.clearWallpaper();",
            "                                                root.launchSkwdWall();\n                                                return;",
        ),
    ],
    root / "Modules/DankBar/BarCanvas.qml": [
        (
            "import QtQuick.Shapes",
            "import QtQuick.Shapes\nimport Quickshell",
        ),
        (
            "    property real wing: gothEnabled ? barWindow._wingR : 0",
            '    property real wing: gothEnabled ? barWindow._wingR : 0\n    readonly property int shapeRendererType: Quickshell.env("QT_QUICK_BACKEND") === "software" ? Shape.SoftwareRenderer : Shape.CurveRenderer',
        ),
        (
            "            preferredRendererType: Shape.CurveRenderer",
            "            preferredRendererType: root.shapeRendererType",
        ),
        (
            "            preferredRendererType: Shape.CurveRenderer",
            "            preferredRendererType: root.shapeRendererType",
        ),
    ],
    root / "Common/SessionData.qml": [
        (
            "    Process {\n        id: sessionWritableCheckProcess",
            "    Process {\n        id: _skwdWallApplyProcess\n        running: false\n    }\n    Process {\n        id: sessionWritableCheckProcess",
        ),
        (
            "        saveSettings();\n\n        if (typeof Theme !== \"undefined\") {\n            Theme.generateSystemThemesFromCurrentTheme();\n        }\n    }\n\n    function setWallpaperColor",
            "        saveSettings();\n        if (typeof imagePath === \"string\" && imagePath.length > 0 && imagePath[0] !== \"#\") {\n            _skwdWallApplyProcess.running = false;\n            _skwdWallApplyProcess.command = [${skwdBin}, \"wall\", \"apply\", JSON.stringify({type: \"static\", path: imagePath})];\n            _skwdWallApplyProcess.running = true;\n        }\n\n        if (typeof Theme !== \"undefined\") {\n            Theme.generateSystemThemesFromCurrentTheme();\n        }\n    }\n\n    function setWallpaperColor",
        ),
        (
            "        saveSettings();\n        Qt.callLater(() => {\n            isSwitchingMode = false;\n        });\n    }\n\n    function setDoNotDisturb",
            "        saveSettings();\n        if (typeof Theme !== \"undefined\") {\n            Theme.generateSystemThemesFromCurrentTheme();\n        }\n        Qt.callLater(() => {\n            isSwitchingMode = false;\n        });\n    }\n\n    function setDoNotDisturb",
        ),
        (
            "        saveSettings();\n\n        if (typeof Theme !== \"undefined\" && typeof Quickshell !== \"undefined\" && typeof SettingsData !== \"undefined\") {\n            var screens = Quickshell.screens;\n            if (screens.length > 0) {\n                var targetMonitor = (SettingsData.matugenTargetMonitor && SettingsData.matugenTargetMonitor !== \"\") ? SettingsData.matugenTargetMonitor : screens[0].name;\n                if (screenName === targetMonitor) {\n                    Theme.generateSystemThemesFromCurrentTheme();\n                }\n            }\n        }\n    }\n\n    function setWallpaperTransition",
            "        saveSettings();\n        if (typeof path === \"string\" && path.length > 0 && path[0] !== \"#\") {\n            _skwdWallApplyProcess.running = false;\n            _skwdWallApplyProcess.command = [${skwdBin}, \"wall\", \"apply\", JSON.stringify({type: \"static\", path: path, outputs: [screenName]})];\n            _skwdWallApplyProcess.running = true;\n        }\n\n        if (typeof Theme !== \"undefined\" && typeof Quickshell !== \"undefined\" && typeof SettingsData !== \"undefined\") {\n            var screens = Quickshell.screens;\n            if (screens.length > 0) {\n                var targetMonitor = (SettingsData.matugenTargetMonitor && SettingsData.matugenTargetMonitor !== \"\") ? SettingsData.matugenTargetMonitor : screens[0].name;\n                if (screenName === targetMonitor) {\n                    Theme.generateSystemThemesFromCurrentTheme();\n                }\n            }\n        }\n    }\n\n    function setWallpaperTransition",
        ),
    ],
  '';
}
