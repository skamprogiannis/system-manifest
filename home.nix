{
  config,
  pkgs,
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
  ];

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    brave
    discord
    obsidian
    protonmail-bridge
    spotify

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
    zellij
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
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  home.stateVersion = "24.11";
}
