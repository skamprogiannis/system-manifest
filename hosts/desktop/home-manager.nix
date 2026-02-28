{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../home.nix
  ];

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "HDMI-A-1, 1920x1080@60, 0x0, 1"
      "DP-1, 1920x1080@60, 1920x0, 1"
    ];

    workspace = [
      "1, monitor:DP-1, default:true"
      "2, monitor:DP-1"
      "3, monitor:DP-1"
      "4, monitor:DP-1"
      "5, monitor:DP-1"
      "6, monitor:DP-1"
      "7, monitor:DP-1"
      "8, monitor:DP-1"
      "9, monitor:DP-1"
      "10, monitor:HDMI-A-1, default:true"
    ];
  };

  programs.zellij.settings.default_layout = "dev";
}
