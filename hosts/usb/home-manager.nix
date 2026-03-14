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

  programs.zellij.settings = {
    pane_frames = false;
    simplified_ui = true;
    default_layout = "compact";
  };

  # DMS software rendering: QS_NO_GL disables QuickShell's GL backend.
  # QT_QUICK_BACKEND=software uses Qt's software rasterizer for QML.
  # We do NOT set LIBGL_ALWAYS_SOFTWARE — let Hyprland use whatever GPU
  # the host machine provides (Intel iGPU, AMD, etc.).
  systemd.user.services.dms.environment = {
    QS_NO_GL = "1";
    QT_QUICK_BACKEND = "software";
  };

  # Lightweight Hyprland config for USB (no blur, no hyprglass, no animations)
  wayland.windowManager.hyprland.settings = {
    monitor = [
      ",preferred,auto,1"
    ];

    decoration = {
      blur.enabled = lib.mkForce false;
      shadow.enabled = lib.mkForce false;
      dim_inactive = lib.mkForce false;
    };

    animations.enabled = lib.mkForce false;
  };

  # Disable hyprglass plugin on USB (GPU-heavy)
  wayland.windowManager.hyprland.plugins = lib.mkForce [];

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
