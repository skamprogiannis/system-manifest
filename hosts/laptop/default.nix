{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../common/default.nix
    ../../modules/nixos/gnome.nix
    ../../modules/nixos/hyprland.nix
    # ./hardware-configuration.nix # Run 'nixos-generate-config' to generate this!
  ];

  networking.hostName = "laptop";

  # Enable touchpad support
  services.libinput.enable = true;
}
