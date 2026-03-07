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
         * libadwaita uses CSS custom properties for colors, not plain selectors.
         * We set both --window-bg-color and background-color for full coverage. */
        :root, window {
          --window-bg-color: rgba(40, 42, 54, 0.82);
          --headerbar-bg-color: rgba(68, 71, 90, 0.88);
          --sidebar-bg-color: rgba(40, 42, 54, 0.75);
          --view-bg-color: rgba(40, 42, 54, 0.78);
          --popover-bg-color: rgba(68, 71, 90, 0.92);
        }
        window,
        .background {
          background-color: rgba(40, 42, 54, 0.82);
        }
        headerbar {
          background-color: rgba(68, 71, 90, 0.88);
        }
        headerbar:backdrop {
          background-color: rgba(68, 71, 90, 0.72);
        }
        .sidebar, .nautilus-window .sidebar {
          background-color: rgba(40, 42, 54, 0.75);
        }
        .view, .content-view {
          background-color: rgba(40, 42, 54, 0.78);
        }
        popover > contents {
          background-color: rgba(68, 71, 90, 0.92);
        }
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
