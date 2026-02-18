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
    ./modules/home/git.nix
    ./modules/home/ghostty.nix
    ./modules/home/neovim.nix
    ./modules/home/opencode.nix
    ./modules/home/hyprland.nix
    ./modules/home/pearpass.nix
    ./modules/home/xdg.nix
    ./modules/home/brave.nix
    ./modules/home/firefox.nix
    ./modules/home/theme.nix
    ./modules/home/obsidian.nix
    ./modules/home/vpn.nix
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
    sops

    # Disk Utilities
  ];

  sops = {
    age.keyFile = "/home/stefan/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets/secrets.yaml;
    secrets.spotify_client_id = {};
    secrets.spotify_client_secret = {};

    templates."app.toml" = {
      path = "${config.xdg.configHome}/spotify-player/app.toml";
      content = ''
        [device]
        name = "nixos-desktop"
        device_type = "computer"
        volume = 90
        bitrate = 320
        audio_cache = true
        normalization = false

        [client]
        client_id = "${config.sops.placeholder.spotify_client_id}"
        client_secret = "${config.sops.placeholder.spotify_client_secret}"
        client_port = 8888
        login_redirect_uri = "http://127.0.0.1:8888/callback"
      '';
    };
  };

  programs.spotify-player = {
    enable = true;
  };

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
  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      set -o vi
    '';
  };
  home.stateVersion = "24.11";

  home.sessionPath = ["$HOME/.local/bin"];

  home.shellAliases = {
    pearpass-dev = "cd ~/repositories/pearpass-app-desktop && npx pear run -d .";
  };
}
