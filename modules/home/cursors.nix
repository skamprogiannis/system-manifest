{
  pkgs,
  config,
  lib,
  ...
}: let
  hollow-knight-cursors = pkgs.stdenv.mkDerivation {
    pname = "hollow-knight-cursors";
    version = "1.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "Ducker227";
      repo = "Hollow-knight-Cursor-Linux";
      rev = "0e76633e94674a7bf86b738e0556fe2b0c8b8cd3";
      sha256 = "sha256-3qv8G+QRxNJ6DNqEhE0gYZ1MTsAHNsZAsqzG0ffvGkU=";
    };

    nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ];

    installPhase = ''
      mkdir -p $out/share/icons/HollowKnight/cursors
      tar -xzf $src/HollowKnight.tar.gz --strip-components=1 -C $out/share/icons/HollowKnight
      
      # Go to the cursors directory to create missing symlinks
      cd $out/share/icons/HollowKnight/cursors

      # --- SYMLINK BAKING ---
      # Ensure common modern names point to HK icons to prevent Adwaita fallbacks
      # Using -sf to force creation even if the file already exists (prevent build failure)
      
      # Pointers / Hands
      ln -sf hand1 pointer
      ln -sf hand1 pointing_hand
      ln -sf hand2 progress
      ln -sf hand2 alias
      
      # Text & Precision
      ln -sf xterm text
      ln -sf xterm ibeam
      ln -sf plus cell
      ln -sf pencil crosshair
      
      # Movement & Resize
      ln -sf sb_h_double_arrow h_double_arrow
      ln -sf sb_h_double_arrow e-resize
      ln -sf sb_h_double_arrow w-resize
      ln -sf sb_h_double_arrow col-resize
      ln -sf sb_v_double_arrow v_double_arrow
      ln -sf sb_v_double_arrow n-resize
      ln -sf sb_v_double_arrow s-resize
      ln -sf sb_v_double_arrow row-resize
      
      # Status
      ln -sf watch wait
      ln -sf watch busy
      ln -sf X_cursor not-allowed
      ln -sf X_cursor no-drop
      ln -sf X_cursor forbidden
      
      # Interactive
      ln -sf hand1 grab
      ln -sf hand1 grabbing
      ln -sf hand1 zoom-in
      ln -sf hand1 zoom-out
      
      # Fix index.theme to inherit ONLY as a last resort
      cat <<EOF > $out/share/icons/HollowKnight/index.theme
[Icon Theme]
Name=HollowKnight
Comment=Hollow Knight themed cursors
Inherits=Adwaita,hicolor
EOF
    '';
  };
in {
  home.packages = [
    hollow-knight-cursors
  ];

  home.pointerCursor = {
    package = hollow-knight-cursors;
    name = "HollowKnight";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Source of truth for other modules
  # Use: config.home.pointerCursor.name and config.home.pointerCursor.size
}
