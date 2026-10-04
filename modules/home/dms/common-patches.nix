{}: let
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

  notificationModal = ''
    root / "Modals/NotificationModal.qml": [
        (
            '        function clearAll(): string {\n            notificationModal.clearAll();\n            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";\n        }',
            '        function clearAll(): string {\n            notificationModal.clearAll();\n            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";\n        }\n\n        function clearHistory(): string {\n            NotificationService.clearHistory();\n            return "NOTIFICATION_MODAL_CLEAR_HISTORY_SUCCESS";\n        }',
        ),
    ],
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
            "        function externalSet(path: string, mode: string): string {\n            if (!path) {\n                return \"ERROR: No path provided\";\n            }\n\n            SessionData.wallpaperCyclingEnabled = false;\n            SessionData.perMonitorWallpaper = false;\n            SessionData.perModeWallpaper = false;\n            SessionData.monitorWallpapers = ({});\n            SessionData.monitorWallpapersLight = ({});\n            SessionData.monitorWallpapersDark = ({});\n            SessionData.monitorCyclingSettings = ({});\n            SessionData.isLightMode = mode === \"light\";\n            SessionData.wallpaperPath = path;\n            SessionData.wallpaperPathLight = path;\n            SessionData.wallpaperPathDark = path;\n            SessionData.saveSettings();\n\n            return \"SUCCESS: External wallpaper set to \" + path;\n        }\n\n        function clear(): string {\n            SessionData.setWallpaper(\"\");",
        ),
    ],
  '';

  niriScreenshotDirectory = ''
    root / "Services/NiriService.qml": [
        (
            'readonly property string screenshotsDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.PicturesLocation)) + "/Screenshots"',
            'readonly property string screenshotsDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.PicturesLocation)) + "/screenshots"',
        ),
    ],
  '';

  # DMS unified its standalone and connected hosts; preserve local glass on both.
  # CalendarOverviewCard inherits Card, and upstream now includes locked idle wake.
  common = ''
    root / "Modules/DankDash/Overview/Card.qml": [
        ("    restRadius: DashMetrics.cardRadius", "    restRadius: DashMetrics.cardRadius\n    color: Theme.withAlpha(surfaceColor, Math.max(0.0, Theme.popupTransparency - 0.22))"),
    ],
    root / "Modals/DankLauncherV2/ControllerUtils.js": [
        ("    if (exec.indexOf(\"/nix/store/\") !== -1 || exec.indexOf(\"/run/current-system/sw/\") !== -1 || exec.indexOf(\"/etc/profiles/per-user/\") !== -1)\n        return \"nix\";\n\n    return \"system\";", "    if (exec.indexOf(\"steam://rungameid/\") !== -1)\n        return \"system\";\n\n    if (exec.indexOf(\"/nix/store/\") !== -1 || exec.indexOf(\"/run/current-system/sw/\") !== -1 || exec.indexOf(\"/etc/profiles/per-user/\") !== -1)\n        return \"nix\";\n\n    if (cmd0.length > 0 && cmd0.indexOf(\"/\") === -1)\n        return \"nix\";\n\n    return \"system\";"),
    ],
    root / "Widgets/DankPopoutHost.qml": [
        ("    property string layerNamespace: popoutHandle.layerNamespace", "    property string layerNamespace: popoutHandle.layerNamespace\n    readonly property color localReadableSurface: root.layerNamespace === \"dms:dash\" ? Theme.withAlpha(Theme.hostSurface, Math.max(0.0, Theme.popupTransparency - 0.12)) : Theme.readableSurface"),
        ("readonly property color surfaceColor: root.usesConnectedSurfaceChrome ? Theme.connectedSurfaceColor : Theme.readableSurface", "readonly property color surfaceColor: root.usesConnectedSurfaceChrome ? Theme.connectedSurfaceColor : root.localReadableSurface"),
        ("readonly property color surfaceBorderColor: root.usesConnectedSurfaceChrome ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor", "readonly property color surfaceBorderColor: root.usesConnectedSurfaceChrome ? Theme.withAlpha(BlurService.borderColor, 0) : (BlurService.enabled ? BlurService.borderColor : Theme.outlineMedium)"),
        ("readonly property real surfaceBorderWidth: root.usesConnectedSurfaceChrome ? 0 : BlurService.borderWidth", "readonly property real surfaceBorderWidth: root.usesConnectedSurfaceChrome ? 0 : (BlurService.enabled ? BlurService.borderWidth : 1)"),
        ("surfaceColor: Theme.readableSurface", "surfaceColor: root.localReadableSurface"),
        ("targetColor: root._fluidMotionActive ? Theme.readableSurface : \"transparent\"", "targetColor: root._fluidMotionActive ? root.localReadableSurface : \"transparent\""),
        ("color: Theme.readableSurface", "color: root.localReadableSurface"),
        ("border.color: BlurService.borderColor", "border.color: BlurService.enabled ? BlurService.borderColor : Theme.outlineMedium"),
        ("border.width: BlurService.borderWidth", "border.width: BlurService.enabled ? BlurService.borderWidth : 1"),
    ],
    root / "Modals/Common/DankModalHost.qml": [
        ("border.color: root.frameOwnsConnectedChrome ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor", "border.color: root.frameOwnsConnectedChrome ? Theme.withAlpha(BlurService.borderColor, 0) : (BlurService.enabled ? BlurService.borderColor : Theme.outlineMedium)"),
        ("border.width: root.frameOwnsConnectedChrome ? 0 : BlurService.borderWidth", "border.width: root.frameOwnsConnectedChrome ? 0 : (BlurService.enabled ? BlurService.borderWidth : 1)"),
    ],
    root / "Modals/DankLauncherV2/DankLauncherV2ModalHost.qml": [
        ("                    borderColor: root.borderColor", "                    borderColor: BlurService.enabled ? BlurService.borderColor : root.borderColor"),
        ("                    borderWidth: root.borderWidth", "                    borderWidth: BlurService.enabled ? BlurService.borderWidth : root.borderWidth"),
        ("                    border.color: BlurService.borderColor", "                    border.color: BlurService.enabled ? BlurService.borderColor : root.borderColor"),
        ("                    border.width: BlurService.borderWidth", "                    border.width: BlurService.enabled ? BlurService.borderWidth : root.borderWidth"),
        ("                    color: \"transparent\"\n                    border.color:", "                    color: \"transparent\"\n                    antialiasing: true\n                    border.color:"),
    ],
    ${appSearchService}
    ${wallpaperCyclingExternalSet}
    ${niriScreenshotDirectory}
    root / "Modules/Notifications/Popup/NotificationPopup.qml": [
      ${notificationPopupBorderFallback}
    ],
  '';
in {
  defaultReplacementsPython = ''
    ${common}
    ${commonLists}
    ${notificationModal}
    root / "Modules/DankBar/Widgets/Clock.qml": [
        ("                    id: clock", "                    id: clock\n                    showSeconds: root.widgetData?.showSeconds !== undefined ? root.widgetData.showSeconds : SettingsData.showSeconds"),
    ],
    root / "Widgets/ClockContent.qml": [
        ("    property bool vertical: false", "    property bool vertical: false\n    property bool showSeconds: SettingsData.showSeconds"),
        ("SettingsData.getEffectiveTimeFormat()", "SettingsData.getEffectiveTimeFormat(root.showSeconds)"),
        ("if (SettingsData.showSeconds)", "if (root.showSeconds)"),
        ("precision: SettingsData.showSeconds ?", "precision: root.showSeconds ?"),
    ],
    root / "Common/SettingsData.qml": [
        ("    function getEffectiveTimeFormat() {", "    function getEffectiveTimeFormat(seconds = showSeconds) {"),
        ("return showSeconds ? \"hh:mm:ss\"", "return seconds ? \"hh:mm:ss\""),
        ("return showSeconds ? \"hh:mm:ss AP\"", "return seconds ? \"hh:mm:ss AP\""),
        ("return showSeconds ? \"h:mm:ss AP\"", "return seconds ? \"h:mm:ss AP\""),
    ],
  '';

  # Portable software rendering cannot capture GPU-backed cache thumbnails.
  usbReplacementsPython = ''
    ${common}
    root / "DankCommon/Widgets/CachingImage.qml": [
        ("import QtQuick\n", "import QtQuick\nimport Quickshell\n"),
        ("                if (!root._cacheTarget)", "                if (!root._cacheTarget || Quickshell.env(\"QT_QUICK_BACKEND\") === \"software\")"),
        ("        _cacheTarget = `''${Paths.stringify(Paths.imagecache)}/''${hash}@''${maxCacheSize}x''${maxCacheSize}.png`;", "        if (Quickshell.env(\"QT_QUICK_BACKEND\") === \"software\") {\n            staticImg.sourceSize = Qt.size(maxCacheSize, maxCacheSize);\n            staticImg.source = encoded;\n            return;\n        }\n        _cacheTarget = `''${Paths.stringify(Paths.imagecache)}/''${hash}@''${maxCacheSize}x''${maxCacheSize}.png`;"),
    ],
    root / "Modules/DankBar/BarSurface.qml": [
        ("import QtQuick.Shapes", "import QtQuick.Shapes\nimport Quickshell"),
        ("preferredRendererType: Shape.CurveRenderer", "preferredRendererType: Quickshell.env(\"QT_QUICK_BACKEND\") === \"software\" ? Shape.SoftwareRenderer : Shape.CurveRenderer"),
    ],
    root / "Modules/Settings/WallpaperColorsTab.qml": [
        ("    function openBrowser() {\n        wallpaperBrowserLoader.active = true;\n        if (wallpaperBrowserLoader.item)\n            wallpaperBrowserLoader.item.open();\n    }", "    function openBrowser() {\n        Quickshell.execDetached([\"skwd-wall-v2\"]);\n    }"),
        ("    function applyWallpaper(path) {\n        if (perMonitor) {\n            SessionData.setMonitorWallpaper(selectedScreen, path);\n            SessionData.setMonitorCyclingFolderPath(selectedScreen, \"\");\n            return;\n        }\n        SessionData.setWallpaper(path);\n        SessionData.wallpaperCyclingFolderPath = \"\";\n        SessionData.saveSettings();\n    }", "    function applyWallpaper(path) {\n        Quickshell.execDetached([\"skwd-wall-v2\"]);\n    }"),
        ("    function pickColor() {\n        const picker = PopoutService.colorPickerModal;\n        if (!picker)\n            return;\n        picker.selectedColor = currentWallpaper.startsWith(\"#\") ? currentWallpaper : Theme.primary;\n        picker.pickerTitle = I18n.tr(\"Choose Wallpaper Color\", \"wallpaper color picker title\");\n        picker.onColorSelectedCallback = function (color) {\n            root.applyWallpaper(color.toString());\n        };\n        picker.show();\n    }", "    function pickColor() {\n        Quickshell.execDetached([\"skwd-wall-v2\"]);\n    }"),
        ("    function clearWallpaper() {\n        SessionData.setMaterialWallpaper(materialTarget, materialEntry);\n    }", "    function clearWallpaper() {\n        Quickshell.execDetached([\"skwd-wall-v2\"]);\n    }"),
        ("    function selectSeed(seed) {\n        if (!SessionData.setMaterialWallpaperSeed(materialTarget, seed))\n            return;\n        SettingsData.setMatugenSeedColor(\"\");\n    }", "    function selectSeed(seed) {\n        Quickshell.execDetached([\"skwd-wall-v2\"]);\n    }"),
        ("    function pickSeed() {\n        const picker = PopoutService.colorPickerModal;\n        if (!picker)\n            return;\n        picker.selectedColor = materialEntry.seed;\n        picker.pickerTitle = I18n.tr(\"Seed color\");\n        picker.onColorSelectedCallback = function (color) {\n            root.selectSeed(Theme.withAlpha(color, 1).toString());\n        };\n        picker.show();\n    }", "    function pickSeed() {\n        Quickshell.execDetached([\"skwd-wall-v2\"]);\n    }"),
        ("onResetRequested: SessionData.setMaterialWallpaperPreset(root.materialTarget, Art.defaultPreset)", "onResetRequested: root.clearWallpaper()"),
        ("onSelected: preset => SessionData.setMaterialWallpaperPreset(root.materialTarget, preset)", "onSelected: preset => root.clearWallpaper()"),
        ("onClicked: SessionData.setMonitorWallpaper(root.selectedScreen, \"\")", "onClicked: root.clearWallpaper()"),
    ],
  '';
}
