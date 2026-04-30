{
  config,
  pkgs,
  ...
}: let
  firefoxDesktopFile = pkgs.runCommand "firefox-desktop-with-comment" {} ''
    cp ${(config.programs.firefox.package or pkgs.firefox)}/share/applications/firefox.desktop $out
    ${pkgs.gnused}/bin/sed -i '/^GenericName=/a Comment=Fast, standards-focused web browser' $out
  '';
in {
  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    # GTK 3: Catppuccin Mocha
    gtk3.extraConfig.gtk-theme-name = "catppuccin-mocha-blue-standard";
    gtk4.theme = null;
    # GTK 4: matugen dynamic colors + coherent translucent popovers/menus.
    # Paint the shell itself so GTK/WebKit apps do not get a transparent wrapper
    # around a separate opaque inner contents node.
    gtk4.extraCss = ''
      @import url("dank-colors.css");

      popover.background,
      menu {
        background-image: none;
        background-color: alpha(#11111b, 0.80);
        border: 1px solid alpha(#cdd6f4, 0.05);
        border-radius: 14px;
        box-shadow: 0 10px 28px alpha(#000000, 0.32);
      }

      popover.background > contents,
      popover contents,
      menu > contents {
        background-image: none;
        background-color: transparent;
        border: none;
        box-shadow: none;
      }
    '';
  };

  # Catppuccin GTK theme (GTK 3 only — GTK 4 uses matugen/dank-colors.css) + icon packs
  home.packages = with pkgs; [
    (catppuccin-gtk.override { variant = "mocha"; })
    dracula-icon-theme
    hicolor-icon-theme
  ];

  home.file.".local/share/applications/firefox.desktop".source = firefoxDesktopFile;
  # Steam drops per-game icons into ~/.local/share/icons/hicolor; provide the
  # theme metadata there so Qt/Quickshell launchers can resolve those icons.
  home.file.".local/share/icons/hicolor/index.theme".source =
    "${pkgs.hicolor-icon-theme}/share/icons/hicolor/index.theme";
  # Override steam.desktop locally so launchers hide Steam's jump-list actions.
  home.file.".local/share/applications/steam.desktop".text = ''
    [Desktop Entry]
    Name=Steam
    Comment=Application for managing and playing games on Steam
    Exec=steam %U
    Icon=steam
    Terminal=false
    Type=Application
    Categories=Network;FileTransfer;Game;
    MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
    PrefersNonDefaultGPU=true
    X-KDE-RunOnDiscreteGpu=true
  '';

  # GTK 4 settings are managed via dconf
  dconf.settings = {
    # System-wide Interface Settings (Fonts)
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "catppuccin-mocha-blue-standard";
      icon-theme = "Papirus-Dark";
      font-name = "Noto Sans 9";
      document-font-name = "Noto Sans 9";
      monospace-font-name = "JetBrainsMono Nerd Font 9";
    };
  };

  # Fontconfig: Ensure non-GNOME apps (Hyprland, TUI) see the same fonts
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = ["JetBrainsMono Nerd Font" "Noto Sans" "Noto Sans CJK JP"];
      sansSerif = ["Noto Sans" "Adwaita" "Noto Sans CJK JP"];
      serif = ["Noto Serif" "Noto Sans" "Noto Serif CJK JP"];
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
      genericName = "Terminal File Manager";
      comment = "Browse files in Yazi using Ghostty";
      exec = "${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi %F";
      icon = "system-file-manager";
      terminal = false;
      mimeType = ["inode/directory"];
      categories = ["System" "Utility" "FileManager"];
    };
    khal = {
      name = "ikhal";
      noDisplay = true;
    };
    tremc = {
      name = "tremc";
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
      comment = "Edit text and code in Ghostty";
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

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "inode/directory" = ["yazi.desktop"];
    };
    defaultApplications = {
      "inode/directory" = ["yazi.desktop"];
    };
  };
}
