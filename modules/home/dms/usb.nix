{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  patchDmsPackage = import ./patch-package.nix {inherit pkgs;};
  usbDmsPackage = patchDmsPackage {
    package = dmsBasePackage;
    pythonPrelude = ''
      settings_shell_alpha = "Math.min(1.0, Theme.popupTransparency + 0.08)"
      settings_header_alpha = "Math.min(1.0, Theme.popupTransparency + 0.10)"
    '';
    # USB keeps the same settings-adjacent transparency patches because upstream
    # still hardcodes those QML paths; the CachingImage tweak below is a separate
    # render-path fix rather than a setting DMS currently exposes.
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
              "                border.width: BlurService.borderWidth",
              "                border.width: BlurService.enabled ? BlurService.borderWidth : 1",
          ),
      ],
      root / "Modals/DankLauncherV2/DankLauncherV2Modal.qml": [
          (
              "                border.color: BlurService.borderColor",
              "                border.color: BlurService.enabled ? BlurService.borderColor : root.borderColor",
          ),
          (
              "                border.width: BlurService.borderWidth",
              "                border.width: BlurService.enabled ? BlurService.borderWidth : root.borderWidth",
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

    '';
  };
in {
  systemd.user.services.dms.Service.Environment = [
    "QS_NO_GL=1"
    "QT_QUICK_BACKEND=software"
    "QSG_RENDER_LOOP=basic"
  ];

  programs.dank-material-shell = {
    package = lib.mkForce usbDmsPackage;
    settings = {
      screenPreferences = lib.mkForce {
        notifications = [];
        osd = [];
        toast = [];
        notepad = [];
      };
      acLockTimeout = lib.mkForce 600;
      acMonitorTimeout = lib.mkForce 0;
      acSuspendTimeout = lib.mkForce 0;
      batteryLockTimeout = lib.mkForce 600;
      batteryMonitorTimeout = lib.mkForce 0;
      batterySuspendTimeout = lib.mkForce 0;
    };
  };
}
