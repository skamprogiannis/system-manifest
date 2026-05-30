{pkgs, ...}: {
  imports = [
    ../common/default.nix
    ../../modules/desktop-enviroments/hyprland.nix
    ../desktop/dms-greeter.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "laptop";

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelParams = [
    "quiet"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "udev.log_level=3"
  ];

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
  };

  services.power-profiles-daemon.enable = true;

  environment.systemPackages = with pkgs; [
    efibootmgr
    pciutils
    usbutils
  ];
}
