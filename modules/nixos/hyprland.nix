{pkgs, inputs, ...}: {
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  services.power-profiles-daemon.enable = true;
  services.accounts-daemon.enable = true;
  services.gvfs.enable = true;
}
