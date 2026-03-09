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
    # GTK 3: keep Dracula via extraConfig (theme package installed below)
    gtk3.extraConfig.gtk-theme-name = "Dracula";
    # GTK 4: use matugen dynamic colors instead of Dracula
    gtk4.extraCss = ''@import url("dank-colors.css");'';
  };

  # Dracula theme (GTK 3 only — GTK 4 uses matugen/dank-colors.css) + hicolor icons
  home.packages = with pkgs; [
    dracula-theme
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
    "org.pwmt.zathura-djvu" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; settings.Hidden = "true"; };
    "org.pwmt.zathura-pdf-mupdf" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; settings.Hidden = "true"; };
    "org.pwmt.zathura-cb" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; settings.Hidden = "true"; };
    "org.pwmt.zathura-ps" = { name = "Zathura"; exec = "zathura %U"; noDisplay = true; settings.Hidden = "true"; };
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
