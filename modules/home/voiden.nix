{pkgs, ...}: let
  version = "2.3.4";
  appImageName = "Voiden-${version}.AppImage";
  src = pkgs.fetchurl {
    url = "https://voiden.md/api/download/stable/linux/x64/${appImageName}";
    hash = "sha256-antO3kK5eHStYhXIkoCRf1KJm2/8y7/E2WwobuY7E24=";
  };

  extracted = pkgs.appimageTools.extract {
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
