{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  home.username = "stefan";
  home.homeDirectory = "/home/stefan";

  imports = [
    ./modules/git.nix
    ./modules/ghostty.nix
    ./modules/neovim.nix
    ./modules/opencode.nix
    ./modules/hyprland.nix
    ./modules/pearpass.nix
    ./modules/xdg.nix
    ./modules/brave.nix
    ./modules/theme.nix
    ./modules/obsidian.nix
  ];

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    discord
    obsidian
    protonmail-bridge
    geary
    protonvpn-gui

    # CLI / Tools
    fastfetch
    btop
    ripgrep
    fd
    wl-clipboard
    cliphist
    curl
    gh
    opencode
    alejandra
    nodejs_22
    nodePackages.prettier
    ruff
    go
    python3
    zellij
    pacvim
    pandoc
    glow
    dig
    spotify-player

    # Disk Utilities
    parted
    dosfstools
    e2fsprogs

    # Fonts
    pkgs.nerd-fonts.jetbrains-mono
    # Torrents
    fragments
  ];

  # --- GNOME KEYBINDINGS ---
  dconf.settings = {
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "ghostty";
      name = "Ghostty";
    };
    # Input sources for GNOME
    "org/gnome/desktop/input-sources" = {
      sources = [(lib.hm.gvariant.mkTuple ["xkb" "us+altgr-intl"]) (lib.hm.gvariant.mkTuple ["xkb" "gr"])];
    };
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = ["<Super>space"];
      switch-input-source-backward = ["<Shift><Super>space"];
      close = ["<Super>q"];
    };
    "org/gnome/gnome-screenshot" = {
      auto-save-directory = "file:///home/stefan/pictures/screenshots";
    };
    "org/gnome/shell" = {
      last-screenshot-directory = "file:///home/stefan/pictures/screenshots";
    };
    "org/gnome/shell/screenshot" = {
      last-save-directory = "file:///home/stefan/pictures/screenshots";
    };
  };

  programs.home-manager.enable = true;
  home.stateVersion = "24.11";

  home.sessionPath = ["$HOME/.local/bin"];

  home.shellAliases = {
    pearpass-dev = "cd ~/repositories/pearpass-app-desktop && npx pear run -d .";
  };
}
