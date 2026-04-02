{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../home.nix
  ];

  system_manifest.navigation.wrapWorkspaces = true;

  # USB-only marker consumed by wallpaper helpers so power-saver can act as
  # a lightweight mode without changing desktop behavior.
  xdg.configFile."system-manifest/usb-light-mode-enabled".text = "1\n";

  programs.zellij.settings = {
    pane_frames = false;
    simplified_ui = true;
    default_layout = "compact";
  };

  # DMS software rendering: QS_NO_GL disables QuickShell's GL backend.
  # QT_QUICK_BACKEND=software uses Qt's software rasterizer for QML.
  # We do NOT set LIBGL_ALWAYS_SOFTWARE — let Hyprland use whatever GPU
  # the host machine provides (Intel iGPU, AMD, etc.).
  systemd.user.services.dms.Service.Environment = [
    "QS_NO_GL=1"
    "QT_QUICK_BACKEND=software"
  ];

  # Auto-detect monitor (USB is portable across machines)
  wayland.windowManager.hyprland.settings = {
    monitor = [
      ",preferred,auto,1"
    ];
  };

  # Lock after 10 min, no monitor off, no suspend (override desktop defaults)
  programs.dank-material-shell.settings = {
    acLockTimeout = lib.mkForce 600;
    acMonitorTimeout = lib.mkForce 0;
    acSuspendTimeout = lib.mkForce 0;
    batteryLockTimeout = lib.mkForce 600;
    batteryMonitorTimeout = lib.mkForce 0;
    batterySuspendTimeout = lib.mkForce 0;
  };
}
