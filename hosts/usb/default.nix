{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../common/default.nix
    ../../modules/nixos/gnome.nix
    ../../modules/nixos/hyprland.nix
  ];

  networking.hostName = "nixos-usb";

  # ISO naming
  image.fileName = "nixos-usb.iso";
  isoImage.volumeID = "NixOS-USB";

  # Speed up booting by not compressing the squashfs
  # Helpful for testing, but makes the ISO larger.
  # Set to true for production if space is an issue on the USB.
  isoImage.squashfsCompression = "zstd";

  # Enable generic hardware support
  hardware.enableAllFirmware = true;

  # Ensure the user stefan is created with a default password (optional)
  # In ISO mode, nixos-rebuild switch might be limited, but software will be there.
  users.users.stefan.initialPassword = "nixos";
}
