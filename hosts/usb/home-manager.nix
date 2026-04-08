{
  config,
  pkgs,
  lib,
  ...
}: {
  # Keep this file as thin host wiring only. Use `hostType` for lightweight
  # shared-module branches, and dedicated `.../usb.nix` modules for heavier
  # host-specific patching or service overrides.
  imports = [
    ../../home.nix
    ../../modules/home/dms/usb.nix
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
  # Auto-detect monitor (USB is portable across machines)
  wayland.windowManager.hyprland.settings = {
    monitor = [
      ",preferred,auto,1"
    ];
  };
}
