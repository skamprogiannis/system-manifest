{
  config,
  pkgs,
  ...
}: {
  gtk = {
    enable = true;
    iconTheme = {
      name = "Dracula";
      package = pkgs.dracula-icon-theme;
    };
    theme = {
      name = "Dracula";
      package = pkgs.dracula-theme;
    };
  };

  # Also ensure standard hicolor icons are present for apps that need them
  home.packages = with pkgs; [
    hicolor-icon-theme
  ];

  # GTK 4 settings are managed via dconf
  dconf.settings = {
    # System-wide Interface Settings (Fonts)
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Dracula";
      icon-theme = "Dracula";
      font-name = "Adwaita 9";
      document-font-name = "Adwaita 9";
      monospace-font-name = "JetBrainsMono Nerd Font 9";
    };
  };

  # Fontconfig: Ensure non-GNOME apps (Hyprland, TUI) see the same fonts
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = ["JetBrainsMono Nerd Font"];
      sansSerif = ["Adwaita"];
      serif = ["Noto Serif"];
    };
  };

  # Make Qt apps look like GTK
  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  # Hide CLI/TUI apps from app launchers (wofi, rofi, etc.)
  xdg.desktopEntries = {
    nvim = {
      name = "Neovim";
      noDisplay = true;
    };
    yazi = {
      name = "Yazi";
      noDisplay = true;
    };
    khal = {
      name = "ikhal";
      noDisplay = true;
    };
    tremc = {
      name = "tremc";
      noDisplay = true;
    };
    "ibus-setup" = {
      name = "IBus Preferences";
      noDisplay = true;
    };
  };
}
