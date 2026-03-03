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

    nativeBuildInputs = [pkgs.gnutar pkgs.gzip];

    installPhase = ''
            mkdir -p $out/share/icons/HollowKnight/cursors
            tar -xzf $src/HollowKnight.tar.gz --strip-components=1 -C $out/share/icons/HollowKnight

            # Go to the cursors directory
            cd $out/share/icons/HollowKnight/cursors

            # --- SYMLINK BAKING ---
            # Keep base pointer names on the arrow cursor and reserve hand cursor names for clickable targets.

            # Pointers (primary arrow)
            ln -sf Normal left_ptr
            ln -sf Normal default
            ln -sf Normal arrow
            ln -sf Normal ptr
            ln -sf Normal top_left_arrow
            ln -sf Link pointer
            ln -sf Normal context-menu

            # Hands / links
            ln -sf Link pointing_hand
            ln -sf Link hand1
            ln -sf Link hand2
            ln -sf Link openhand
            ln -sf Link closedhand
            ln -sf Link grab
            ln -sf Link grabbing
            ln -sf Link zoom-in
            ln -sf Link zoom-out
            ln -sf Link dnd-link
            ln -sf Link link

            # Text & Precision
            ln -sf xterm text
            ln -sf xterm ibeam
            ln -sf xterm vertical-text
            ln -sf plus cell
            ln -sf plus crosshair
            ln -sf plus cross
            ln -sf plus precision

            # Help / special pointers
            ln -sf question_arrow help
            ln -sf question_arrow whats_this
            ln -sf alias shortcut
            ln -sf copy copy_arrow

            # Movement & Resize
            ln -sf sb_h_double_arrow h_double_arrow
            ln -sf sb_h_double_arrow e-resize
            ln -sf sb_h_double_arrow w-resize
            ln -sf sb_h_double_arrow col-resize
            ln -sf sb_v_double_arrow v_double_arrow
            ln -sf sb_v_double_arrow n-resize
            ln -sf sb_v_double_arrow s-resize
            ln -sf sb_v_double_arrow row-resize
            ln -sf size_bdiag ne-resize
            ln -sf size_bdiag sw-resize
            ln -sf size_fdiag nw-resize
            ln -sf size_fdiag se-resize
            ln -sf fleur move
            ln -sf size_all all-scroll

            # Status
            ln -sf watch wait
            ln -sf watch busy
            ln -sf X_cursor not-allowed
            ln -sf X_cursor no-drop
            ln -sf X_cursor forbidden
            ln -sf X_cursor dnd-no-drop
            ln -sf crossed_circle dnd-none
            ln -sf copy dnd-copy

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
}
