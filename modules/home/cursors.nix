{
  pkgs,
  lib,
  ...
}: let
  silksong-cursors = pkgs.stdenv.mkDerivation {
    pname = "silksong-cursors";
    version = "1.0.0";

    src = pkgs.fetchFromGitHub {
      owner = "emanuelghdev";
      repo = "silksong-cursor";
      rev = "4901f603c4004c3e742886f4a8677055745107e3";
      sha256 = "sha256-R3yX9e9zSOfi/K8I8V9NqYhS6I5V8S+KxXyG4IuP1E8=";
    };

    installPhase = ''
      mkdir -p $out/share/icons/Silksong-Cursors
      cp -r * $out/share/icons/Silksong-Cursors/
    '';
  };
in {
  home.packages = [silksong-cursors];

  home.pointerCursor = {
    package = silksong-cursors;
    name = "Silksong-Cursors";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Set cursor theme in dconf for GTK4 apps
  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = "Silksong-Cursors";
    cursor-size = 24;
  };
}
