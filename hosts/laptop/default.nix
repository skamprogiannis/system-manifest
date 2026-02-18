{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../common/default.nix
    ../../modules/nixos/gnome.nix
    ../../modules/nixos/hyprland.nix
  ];

  networking.hostName = "laptop";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable touchpad support
  services.libinput.enable = true;
}
