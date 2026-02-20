{pkgs, ...}: {
  programs.hyprland.enable = true;

  services.power-profiles-daemon.enable = true;
  services.accounts-daemon.enable = true;
}
