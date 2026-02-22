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
    cursorTheme = {
      name = "Dracula-cursors";
      package = pkgs.dracula-theme;
      size = 24;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
  };

  # Also ensure standard hicolor icons are present for apps that need them
  home.packages = with pkgs; [
    hicolor-icon-theme
  ];

  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.dracula-theme;
    name = "Dracula-cursors";
    size = 24;
  };

  home.file.".icons/Dracula-cursors".source = "${pkgs.dracula-theme}/share/icons/Dracula-cursors";

  # GTK 4 settings are managed via dconf
  dconf.settings = {
    # System-wide Interface Settings (Fonts)
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Dracula";
      icon-theme = "Dracula";
      font-name = "Adwaita 11";
      document-font-name = "Adwaita 11";
      monospace-font-name = "JetBrainsMono Nerd Font 11";
    };

    # GNOME Terminal Profile (The Cattle Fix)
    "org/gnome/terminal/legacy/profiles:/:default" = {
      font = "JetBrainsMono Nerd Font 11";
      use-system-font = false;
    };

    # Favorites Bar (Sync USB to Desktop)
    "org/gnome/shell" = {
      favorite-apps = [
        "com.mitchellh.ghostty.desktop"
        "brave-browser.desktop"
        "discord.desktop"
        "pearpass.desktop"
        "Mailspring.desktop"
        "org.gnome.Nautilus.desktop"
      ];
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

  # Hide CLI/TUI apps from GNOME app overview
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
  };
}
