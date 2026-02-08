{
  pkgs,
  lib,
  ...
}: {
  # Enable the GNOME Desktop Environment
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Exclude GNOME bloat
  environment.gnome.excludePackages = with pkgs; [
    gnome-maps
    gnome-weather
    gnome-contacts
    gnome-photos
    gnome-tour
    cheese # Old GNOME Camera
    snapshot # New GNOME Camera
  ];
}
