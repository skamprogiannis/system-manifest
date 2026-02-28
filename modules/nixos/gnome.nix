{
  pkgs,
  lib,
  ...
}: {
  # Enable the GNOME Desktop Environment
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    btop
    seahorse # GNOME Keyring GUI Manager
  ];

  # Exclude GNOME bloat
  environment.gnome.excludePackages = with pkgs; [
    gnome-maps
    gnome-weather
    gnome-contacts
    gnome-photos
    gnome-tour
    gnome-console
    gnome-terminal
    cheese
    snapshot
    rygel
    yelp
    simple-scan
    gnome-color-manager
    gnome-music
    totem
    epiphany
    gnome-system-monitor
    gnome-calendar
    gnome-clocks
    gnome-characters
    gnome-font-viewer
    gnome-logs
    gnome-connections
    gnome-user-share
    papers
    decibels
  ];
}
