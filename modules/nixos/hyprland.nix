{pkgs, inputs, ...}: {
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
  };

  services.power-profiles-daemon.enable = true;
  services.accounts-daemon.enable = true;
  services.gvfs.enable = true;
}
