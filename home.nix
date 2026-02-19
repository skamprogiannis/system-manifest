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
    evolution
    geary
    gnome-online-accounts
    obsidian
    protonvpn-gui

    # CLI / Tools
    alejandra
    btop
    cliphist
    curl
    dig
    fastfetch
    fd
    fragments
    gh
    git
    glow
    go
    nodejs_22
    opencode
    pacvim
    pandoc
    python3
    ripgrep
    ruff
    sops
    spotify-player
    transmission_4
    wget
    wl-clipboard
    zellij

    # Disk Utilities
    dosfstools
    e2fsprogs
    parted

    # Fonts
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.enable = true;

  sops = {
    age.keyFile = "/home/stefan/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets/secrets.yaml;
    secrets.spotify_client_id = {};
    secrets.spotify_client_secret = {};

    templates."spotify-player-app-toml" = {
      path = "${config.xdg.configHome}/spotify-player/app.toml";
      content = ''
        client_id = "${config.sops.placeholder.spotify_client_id}"
        client_secret = "${config.sops.placeholder.spotify_client_secret}"
        client_port = 8888
        login_redirect_uri = "http://127.0.0.1:8888/callback"

        [device]
        name = "nixos-desktop"
        device_type = "computer"
        volume = 90
        bitrate = 320
        audio_cache = true
        normalization = false
      '';
    };

    templates."spotify-player-underscore-app-toml" = {
      path = "${config.xdg.configHome}/spotify_player/app.toml";
      content = ''
        client_id = "${config.sops.placeholder.spotify_client_id}"
        client_secret = "${config.sops.placeholder.spotify_client_secret}"
        client_port = 8888
        login_redirect_uri = "http://127.0.0.1:8888/callback"

        [device]
        name = "nixos-desktop"
        device_type = "computer"
        volume = 90
        bitrate = 320
        audio_cache = true
        normalization = false
      '';
    };
  };

  # Force sops-nix to start on login to ensure secrets are rendered
  systemd.user.services.sops-nix.Install.WantedBy = [ "default.target" ];

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


