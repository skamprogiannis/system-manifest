{
  config,
  pkgs,
  lib,
  ...
}: {
  # Keep this file as thin host wiring only. Use `hostType` only for
  # lightweight shared-module branches, and dedicated `.../usb.nix` modules
  # for host-owned services, runtime/session files, or heavier overrides.
  imports = [
    ../../home.nix
    ../../modules/home/dms/usb.nix
    ../../modules/home/scripts/usb.nix
    ../../modules/home/spotify/usb.nix
  ];

  system_manifest.navigation.wrapWorkspaces = true;

  # USB-only marker consumed by wallpaper helpers so power-saver can act as
  # a lightweight mode without changing desktop behavior.
  xdg.configFile."system-manifest/usb-light-mode-enabled".text = "1\n";

  programs.zellij.settings = {
    pane_frames = false;
    simplified_ui = true;
    default_layout = "dev";
  };
  # Auto-detect monitor (USB is portable across machines)
  wayland.windowManager.hyprland.settings = {
    monitor = [
      ",preferred,auto,1"
    ];
  };
}
