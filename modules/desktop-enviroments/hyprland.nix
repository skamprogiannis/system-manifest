{
  pkgs,
  inputs,
  lib,
  ...
}: let
  hyprlandBase = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  # Remove the uwsm session entry — DMS greeter ignores Hidden=true so the
  # .desktop file must be physically absent from the sessions directory.
  hyprlandNoUwsm = let
    joined = pkgs.symlinkJoin {
      name = hyprlandBase.name;
      paths = [hyprlandBase];
      passthru =
        hyprlandBase.passthru
        // {
          providedSessions = ["hyprland"];
        };
      postBuild = "rm -f $out/share/wayland-sessions/hyprland-uwsm.desktop";
    };
  in
    joined
    // {
      # Forward attributes the NixOS hyprland module accesses on cfg.package
      inherit (hyprlandBase) version;
      # The NixOS hyprland module probes pkg.override for enableXWayland;
      # provide a no-op so the probe succeeds without triggering a rebuild.
      override = _: joined;
    };
in {
  programs.hyprland = {
    enable = true;
    package = hyprlandNoUwsm;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  xdg.portal = {
    enable = true;
    config.hyprland = {
      default = ["hyprland" "gtk"];
      "org.freedesktop.impl.portal.Settings" = ["gtk"];
      "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
      "org.freedesktop.impl.portal.Screenshot" = ["hyprland"];
    };
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };

  services.power-profiles-daemon.enable = true;
  services.accounts-daemon.enable = true;
  services.gvfs.enable = true;
}
