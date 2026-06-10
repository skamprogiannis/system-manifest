{...}: {
  imports = [
    ../../home.nix
    ../../modules/home/dms/laptop.nix
  ];

  system_manifest.navigation.wrapWorkspaces = true;

  programs.zellij.settings.default_layout = "dev";

  wayland.windowManager.hyprland.settings = {
    monitor = {
      output = "";
      mode = "preferred";
      position = "auto";
      scale = "1";
    };
  };
}
