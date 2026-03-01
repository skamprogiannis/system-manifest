{
  pkgs,
  lib,
  ...
}: let
  hollow-knight-cursors = pkgs.stdenv.mkDerivation {
    pname = "hollow-knight-cursors";
    version = "1.0.0";

    src = pkgs.fetchFromGitHub {
      owner = "Ducker227";
      repo = "Hollow-knight-Cursor-Linux";
      rev = "0e76633e94674a7bf86b738e0556fe2b0c8b8cd3";
      sha256 = "sha256-3qv8G+QRxNJ6DNqEhE0gYZ1MTsAHNsZAsqzG0ffvGkU=";
    };

    nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ];

    installPhase = ''
      mkdir -p $out/share/icons/HollowKnight
      tar -xzf $src/HollowKnight.tar.gz -C $out/share/icons/
    '';
  };
in {
  home.packages = [
    hollow-knight-cursors
    pkgs.dracula-theme # Keep as an option
  ];

  home.pointerCursor = {
    package = hollow-knight-cursors;
    name = "HollowKnight";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Set cursor theme in dconf for GTK4 apps
  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = "HollowKnight";
    cursor-size = 24;
  };
}
