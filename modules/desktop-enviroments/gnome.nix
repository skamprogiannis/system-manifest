{
  pkgs,
  lib,
  ...
}: {
  # Enable the GNOME Desktop Environment
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services."gdm-password".enableGnomeKeyring = true;

  environment.systemPackages = with pkgs; [
    btop
    seahorse # GNOME Keyring GUI Manager
  ];

  # GNOME is only a fallback session here, so keep its app bundle minimal.
  environment.gnome.excludePackages = with pkgs; [
    baobab
    gnome-maps
    gnome-weather
    gnome-contacts
    gnome-photos
    gnome-tour
    gnome-calculator
    gnome-console
    gnome-terminal
    gnome-control-center
    gnome-disk-utility
    gnome-shell-extensions
    cheese
    snapshot
    rygel
    yelp
    simple-scan
    gnome-color-manager
    gnome-music
    gnome-text-editor
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
    loupe
    eog
    nautilus
    papers
    decibels
  ];
}
