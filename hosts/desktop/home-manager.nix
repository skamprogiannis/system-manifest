{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../home.nix
    ../../modules/home/dms/desktop.nix
  ];

  wayland.windowManager.hyprland.settings = {
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
