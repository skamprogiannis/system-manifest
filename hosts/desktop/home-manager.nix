{
  config,
  pkgs,
  lib,
  ...
}: {
  # Keep this file as thin host wiring only. Shared modules may branch on
  # `hostType` for lightweight defaults, but desktop-owned runtime behavior,
  # patches, or session contracts should stay in dedicated host modules.
  imports = [
    ../../home.nix
    ../../modules/home/dms/desktop.nix
    ../../modules/home/scripts/usb.nix
  ];

  system_manifest.scripts.enableSetupPersistentUsb = false;

  wayland.windowManager.hyprland.settings = {
    workspace_rule = [
      {
        workspace = "1";
        monitor = "DP-1";
        default = true;
      }
      {
        workspace = "2";
        monitor = "DP-1";
      }
      {
        workspace = "3";
        monitor = "DP-1";
      }
      {
        workspace = "4";
        monitor = "DP-1";
      }
      {
        workspace = "5";
        monitor = "DP-1";
      }
      {
        workspace = "6";
        monitor = "DP-1";
      }
      {
        workspace = "7";
        monitor = "DP-1";
      }
      {
        workspace = "8";
        monitor = "DP-1";
      }
      {
        workspace = "9";
        monitor = "DP-1";
      }
      {
        workspace = "10";
        monitor = "HDMI-A-1";
        default = true;
      }
    ];
  };

  programs.zellij.settings.default_layout = "dev";
}
