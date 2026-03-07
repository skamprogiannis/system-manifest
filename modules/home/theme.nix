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
    gtk4 = {
      extraCss = ''
        /* rgba() transparency for Nautilus and GTK4 apps.
         * Dracula palette: bg=#282a36 (40,42,54), current-line=#44475a (68,71,90)
         * libadwaita uses its own named color variables (NOT theme_bg_color).
         * Setting window_bg_color etc. as rgba() makes backgrounds transparent
         * while text/icons remain fully opaque. */
        @define-color window_bg_color rgba(40, 42, 54, 0.82);
        @define-color window_fg_color #f8f8f2;
        @define-color headerbar_bg_color rgba(68, 71, 90, 0.88);
        @define-color headerbar_backdrop_color rgba(68, 71, 90, 0.72);
        @define-color sidebar_bg_color rgba(40, 42, 54, 0.75);
        @define-color view_bg_color rgba(40, 42, 54, 0.78);
        @define-color popover_bg_color rgba(68, 71, 90, 0.92);
        @define-color card_bg_color rgba(68, 71, 90, 0.6);
      '';
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
    # Hide individual Zathura plugin desktop entries — only the main one should appear
    "org.pwmt.zathura-djvu" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; };
    "org.pwmt.zathura-pdf-mupdf" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; };
    "org.pwmt.zathura-cb" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; };
    "org.pwmt.zathura-ps" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; };
    # Neovim in Ghostty — used as the default text editor
    "nvim-text" = {
      name = "Neovim";
      genericName = "Text Editor";
      exec = "ghostty -e nvim %F";
      icon = "nvim";
      terminal = false;
      mimeType = [
        "text/plain"
        "text/markdown"
        "text/css"
        "text/javascript"
        "text/x-script.python"
        "application/json"
        "application/x-shellscript"
        "application/x-sh"
      ];
      categories = ["Utility" "TextEditor"];
    };
  };
}
