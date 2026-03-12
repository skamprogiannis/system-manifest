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

  wayland.windowManager.hyprland.settings = {
    monitor = [
      ",preferred,auto,1"
    ];
  };

  programs.zellij.settings = {
    pane_frames = false;
    simplified_ui = true;
    default_layout = "compact";
  };

  systemd.user.services.dms.environment = {
    QS_NO_GL = "1";
    QT_QUICK_BACKEND = "software";
    LIBGL_ALWAYS_SOFTWARE = "1";
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
