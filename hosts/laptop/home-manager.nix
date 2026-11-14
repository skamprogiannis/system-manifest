{...}: {
  imports = [
    ../../home.nix
    ../../modules/home/dms/laptop.nix
  ];

  wayland.windowManager.hyprland.settings = {
    monitor = {
      output = "";
      mode = "preferred";
      position = "auto";
      scale = "1";
    };
  };
}
