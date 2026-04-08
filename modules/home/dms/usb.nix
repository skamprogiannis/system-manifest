{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  dmsBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;
  usbDmsPackage = dmsBasePackage.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      ${pkgs.python3}/bin/python3 - <<PY
from pathlib import Path
import stat

root = Path("$out/share/quickshell/dms")
settings_shell_alpha = "Math.min(1.0, Theme.popupTransparency + 0.08)"
settings_header_alpha = "Math.min(1.0, Theme.popupTransparency + 0.10)"

replacements = {
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
    root / "Widgets/CachingImage.qml": [
        (
            '        staticImg.source = cPath || encoded;',
            '        staticImg.source = encoded;',
        ),
    ],

}

for path, edits in replacements.items():
    path.chmod(path.stat().st_mode | stat.S_IWUSR)
    text = path.read_text(encoding="utf-8")
    for old, new in edits:
        if old not in text:
            raise SystemExit(f"Expected snippet not found in {path}: {old}")
        text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
PY
    '';
  });
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
