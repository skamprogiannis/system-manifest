{
  pkgs,
  lib,
  ...
}: let
  version = "1.6.3";
  appImageName = "Voiden-${version}.AppImage";
  src = pkgs.fetchurl {
    url = "https://voiden.md/api/download/stable/linux/x64/${appImageName}";
    hash = "sha256-1cR32d8M1/4YnXsFO0K8eI2mLQ2OnpDOH2i6TNx3Lxc=";
  };

  extracted = pkgs.appimageTools.extractType2 {
    pname = "voiden";
    inherit version src;
  };

  app = pkgs.appimageTools.wrapType2 {
    pname = "voiden";
    inherit version src;
    extraPkgs = pkgs:
      with pkgs; [
        webkitgtk_4_1
        gtk4
        libadwaita
        graphene
        libsoup_3
        gnome-themes-extra
        gtk3
      ];
  };
in {
  home.packages = [app];

  xdg.desktopEntries.voiden = {
    name = "Voiden";
    comment = "Offline-first API client";
    exec = "${app}/bin/voiden %U";
    icon = "${extracted}/resources/logo-dark.png";
    categories = ["Development" "Network"];
    terminal = false;
  };
}
