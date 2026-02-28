{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    dracula-theme
  ];

  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.dracula-theme;
    name = "Dracula-cursors";
    size = 24;
  };

  # Set cursor theme in dconf for GTK4 apps
  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = "Dracula-cursors";
    cursor-size = 24;
  };

  # Note: To use Hollow Knight cursors from ~/downloads:
  # 1. Convert them to XCursor format using tools like `ani2xcursor`.
  # 2. Place them in ~/.icons/HollowKnight/cursors.
  # 3. Update 'name' here to "HollowKnight".
}
