{lib, ...}: {
  imports = [
    ../common/default.nix
    ./host-scratch.nix
    ../../modules/desktop-enviroments/hyprland.nix
    ../desktop/dms-greeter.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos-usb";

  # Bootloader (Hollow GRUB style)
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    useOSProber = false;
    # Ensure it installs to the removable media path for maximum USB compatibility
    # (EFI/BOOT/BOOTX64.EFI) so any BIOS picks it up.
    efiInstallAsRemovable = true;
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # Ensure the USB doesn't try to load Nvidia drivers from the host
  services.xserver.videoDrivers = lib.mkForce ["modesetting" "fbdev"];

  specialisation = {
    host-auto-store.configuration = {
      boot.loader.grub.configurationName = "host-auto-store";
      system.nixos.tags = ["host-auto-store"];
      systemManifest.usb.store.mode = "host-auto";
    };

    ram-store.configuration = {
      boot.loader.grub.configurationName = "ram-store";
      system.nixos.tags = ["ram-store"];
      systemManifest.usb.store.mode = "ram-backed";
    };
  };

  # User setup
  users.users.stefan.initialPassword = "nixos";
}
