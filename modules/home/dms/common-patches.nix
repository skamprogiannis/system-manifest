let
  settingsModal = ''
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
  '';

  settingsSidebar = ''
    root / "Modals/Settings/SettingsSidebar.qml": [
        (
            "    color: Theme.surfaceContainer",
            f"    color: Theme.withAlpha(Theme.surfaceContainer, {settings_shell_alpha})",
        ),
    ],
  '';

  settingsCard = ''
    root / "Modules/Settings/Widgets/SettingsCard.qml": [
        (
            "    color: Theme.surfaceContainerHigh",
            f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
        ),
    ],
  '';

  settingsSliderCard = ''
    root / "Modules/Settings/Widgets/SettingsSliderCard.qml": [
        (
            "    color: Theme.surfaceContainerHigh",
            f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
        ),
    ],
  '';

  settingsToggleCard = ''
    root / "Modules/Settings/Widgets/SettingsToggleCard.qml": [
        (
            "    color: Theme.surfaceContainerHigh",
            f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
        ),
    ],
  '';

  systemMonitorVariantCard = ''
    root / "Modules/Settings/Widgets/SystemMonitorVariantCard.qml": [
        (
            "    color: Theme.surfaceContainerHigh",
            f"    color: Theme.withAlpha(Theme.surfaceContainerHigh, {settings_shell_alpha})",
        ),
    ],
  '';

  overviewCard = ''
    root / "Modules/DankDash/Overview/Card.qml": [
        (
            "color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)",
            "color: Theme.withAlpha(Theme.surfaceContainerHigh, Math.max(0.0, Theme.popupTransparency - 0.22))",
        ),
    ],
  '';

  calendarOverviewCard = ''
    root / "Modules/DankDash/Overview/CalendarOverviewCard.qml": [
        (
            "color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)",
            "color: Theme.withAlpha(Theme.surfaceContainerHigh, Math.max(0.0, Theme.popupTransparency - 0.22))",
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

  modalBorderFallback = ''
    (
        "                        border.color: BlurService.borderColor",
        "                        border.color: BlurService.enabled ? BlurService.borderColor : Theme.outlineMedium",
    ),
    (
        "                        border.width: BlurService.borderWidth",
        "                        border.width: BlurService.enabled ? BlurService.borderWidth : 1",
    ),
  '';

  launcherBorderFallback = ''
    (
        "                border.color: BlurService.borderColor",
        "                border.color: BlurService.enabled ? BlurService.borderColor : root.borderColor",
    ),
    (
        "                border.width: BlurService.borderWidth",
        "                border.width: BlurService.enabled ? BlurService.borderWidth : root.borderWidth",
    ),
  '';

  notificationPopupBorderFallback = ''
    (
        "            border.color: BlurService.borderColor",
        '            border.color: BlurService.enabled ? BlurService.borderColor : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)',
    ),
    (
        "            border.width: BlurService.borderWidth",
        "            border.width: BlurService.enabled ? BlurService.borderWidth : 1",
    ),
  '';
in {
  pythonPrelude = ''
    settings_shell_alpha = "Math.min(1.0, Theme.popupTransparency + 0.08)"
    settings_header_alpha = "Math.min(1.0, Theme.popupTransparency + 0.10)"
  '';

  # These patches stay even when a setting with the same name exists below.
  # Upstream DMS still hardcodes several surfaces and does not fully thread
  # per-widget options like showSeconds through the components we rely on.
  defaultReplacementsPython = ''
    ${settingsModal}
    ${settingsSidebar}
    ${settingsCard}
    ${settingsSliderCard}
    ${settingsToggleCard}
    ${systemMonitorVariantCard}
    root / "Widgets/DankPopout.qml": [
      ${dankPopoutBase}
      ${popoutBorderFallback}
    ],
    root / "Modals/Common/DankModal.qml": [
      ${modalBorderFallback}
    ],
    root / "Modals/DankLauncherV2/DankLauncherV2Modal.qml": [
      ${launcherBorderFallback}
    ],
    root / "Modules/Notifications/Popup/NotificationPopup.qml": [
      ${notificationPopupBorderFallback}
    ],
    ${overviewCard}
    ${calendarOverviewCard}
    ${appSearchService}
    ${commonLists}
    ${clockWidget}
    # Expose a clearHistory IPC command so keybinds can wipe the History tab.
    # The built-in clearAll IPC only calls clearAllNotifications(); this adds
    # a sibling function that delegates to NotificationService.clearHistory().
    ${notificationModal}
  '';

  # USB keeps the same settings-adjacent transparency patches because upstream
  # still hardcodes those QML paths; the extra blocks below are specific to the
  # software-rendered USB path and should not leak into desktop.
  usbReplacementsPython = ''
    ${settingsModal}
    ${settingsSidebar}
    ${settingsCard}
    ${settingsSliderCard}
    ${settingsToggleCard}
    ${systemMonitorVariantCard}
    root / "Widgets/DankPopout.qml": [
      ${dankPopoutBase}
      ${popoutBorderFallback}
    ],
    root / "Modals/Common/DankModal.qml": [
      ${modalBorderFallback}
    ],
    root / "Modals/DankLauncherV2/DankLauncherV2Modal.qml": [
      ${launcherBorderFallback}
    ],
    root / "Modules/Notifications/Popup/NotificationPopup.qml": [
      ${notificationPopupBorderFallback}
    ],
    ${overviewCard}
    ${calendarOverviewCard}
    ${appSearchService}
    root / "Widgets/CachingImage.qml": [
        (
            '        staticImg.source = cPath || encoded;',
            '        staticImg.source = encoded;',
        ),
    ],
    root / "Modules/DankDash/WallpaperTab.qml": [
        (
            "import QtQuick.Effects",
            "import QtQuick.Effects\nimport Quickshell",
        ),
        (
            "                            maxCacheSize: 256\n\n                            layer.enabled: true",
            '                            maxCacheSize: 256\n\n                            layer.enabled: Quickshell.env("QT_QUICK_BACKEND") !== "software"',
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
    root / "Widgets/DankCircularImage.qml": [
        (
            "import QtQuick.Window\nimport QtQuick.Effects",
            "import QtQuick.Window\nimport QtQuick.Effects\nimport Quickshell",
        ),
        (
            "    property int imageStatus: activeImage.status",
            '    property int imageStatus: activeImage.status\n    readonly property bool softwareQtQuick: Quickshell.env("QT_QUICK_BACKEND") === "software"',
        ),
        (
            "        visible: false",
            "        visible: root.softwareQtQuick && root.isAnimated",
        ),
        (
            "        visible: false",
            '        visible: root.softwareQtQuick && !root.isAnimated && root.imageSource !== ""',
        ),
        (
            '        visible: root.activeImage.status === Image.Ready && root.imageSource !== ""',
            '        visible: !root.softwareQtQuick && root.activeImage.status === Image.Ready && root.imageSource !== ""',
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
            "        saveSettings();\n        if (typeof imagePath === \"string\" && imagePath.length > 0 && imagePath[0] !== \"#\") {\n            _skwdWallApplyProcess.running = false;\n            _skwdWallApplyProcess.command = [\"skwd\", \"wall\", \"apply\", JSON.stringify({type: \"static\", path: imagePath})];\n            _skwdWallApplyProcess.running = true;\n        }\n\n        if (typeof Theme !== \"undefined\") {\n            Theme.generateSystemThemesFromCurrentTheme();\n        }\n    }\n\n    function setWallpaperColor",
        ),
        (
            "        saveSettings();\n        Qt.callLater(() => {\n            isSwitchingMode = false;\n        });\n    }\n\n    function setDoNotDisturb",
            "        saveSettings();\n        if (typeof Theme !== \"undefined\") {\n            Theme.generateSystemThemesFromCurrentTheme();\n        }\n        Qt.callLater(() => {\n            isSwitchingMode = false;\n        });\n    }\n\n    function setDoNotDisturb",
        ),
        (
            "        saveSettings();\n\n        if (typeof Theme !== \"undefined\" && typeof Quickshell !== \"undefined\" && typeof SettingsData !== \"undefined\") {\n            var screens = Quickshell.screens;\n            if (screens.length > 0) {\n                var targetMonitor = (SettingsData.matugenTargetMonitor && SettingsData.matugenTargetMonitor !== \"\") ? SettingsData.matugenTargetMonitor : screens[0].name;\n                if (screenName === targetMonitor) {\n                    Theme.generateSystemThemesFromCurrentTheme();\n                }\n            }\n        }\n    }\n\n    function setWallpaperTransition",
            "        saveSettings();\n        if (typeof path === \"string\" && path.length > 0 && path[0] !== \"#\") {\n            _skwdWallApplyProcess.running = false;\n            _skwdWallApplyProcess.command = [\"skwd\", \"wall\", \"apply\", JSON.stringify({type: \"static\", path: path, outputs: [screenName]})];\n            _skwdWallApplyProcess.running = true;\n        }\n\n        if (typeof Theme !== \"undefined\" && typeof Quickshell !== \"undefined\" && typeof SettingsData !== \"undefined\") {\n            var screens = Quickshell.screens;\n            if (screens.length > 0) {\n                var targetMonitor = (SettingsData.matugenTargetMonitor && SettingsData.matugenTargetMonitor !== \"\") ? SettingsData.matugenTargetMonitor : screens[0].name;\n                if (screenName === targetMonitor) {\n                    Theme.generateSystemThemesFromCurrentTheme();\n                }\n            }\n        }\n    }\n\n    function setWallpaperTransition",
        ),
    ],
  '';
}
