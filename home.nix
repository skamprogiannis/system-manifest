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
    ./modules/home/hyprland.nix
    ./modules/home/dms
    ./modules/home/pearpass.nix
    ./modules/home/xdg.nix
    ./modules/home/brave.nix
    ./modules/home/gh-copilot
    ./modules/home/firefox.nix
    ./modules/home/theme.nix
    ./modules/home/obsidian.nix
    ./modules/home/spotify.nix
    ./modules/home/zellij.nix
    ./modules/home/scripts
    ./modules/home/wallpaper
    ./modules/home/wallpaper-selector.nix
    ./modules/home/cursors.nix
    ./modules/home/vesktop.nix
    ./modules/home/keyring.nix
    ./modules/home/voiden.nix
  ];

  # --- PACKAGES ---
  home.packages = with pkgs; [
    # GUI
    imv
    gpu-screen-recorder
    mpv
    linux-wallpaperengine
    vesktop
    pkgs.mailspring
    obsidian
    protonvpn-gui

    # CLI / Tools
    alejandra
    clang
    clang-tools
    cppcheck
    curl
    fastfetch
    fd
    ffmpegthumbnailer
    file
    imagemagick
    gcr
    # Wrap copilot CLI so keytar.node can find libsecret at runtime
    (pkgs.symlinkJoin {
      name = "github-copilot-cli-wrapped";
      paths = [pkgs.github-copilot-cli];
      postBuild = ''
        rm -f $out/bin/copilot
        cp ${pkgs.github-copilot-cli}/bin/.copilot-wrapped $out/bin/upstream-copilot
        chmod +x $out/bin/upstream-copilot

        # Keep executable basename "copilot" (gh checks PATH for this name),
        # but run the real binary with filtered args and NixOS runtime libs.
        cat > $out/bin/copilot <<'EOF'
        #!${pkgs.bash}/bin/bash
        if [[ -n "$LD_LIBRARY_PATH" ]]; then
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
          pkgs.libsecret
          pkgs.glib
          pkgs.gcc-unwrapped.lib
        ]}:$LD_LIBRARY_PATH"
        else
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
          pkgs.libsecret
          pkgs.glib
          pkgs.gcc-unwrapped.lib
        ]}"
        fi

        if [[ -z "$GH_TOKEN" && -f "$HOME/.config/github-pat" ]]; then
          export GH_TOKEN="$(<"$HOME/.config/github-pat")"
        fi

        args=()
        for arg in "$@"; do
          if [[ "$arg" == "--no-warnings" ]]; then
            continue
          fi
          args+=("$arg")
        done

        # The upstream loader behavior depends on argv0 ending in "copilot".
        # Use a symlinked binary name that preserves this suffix.
        real="$(dirname "$0")/upstream-copilot"
        if [[ ! -x "$real" ]]; then
          echo "copilot runtime binary not found: $real" >&2
          exit 1
        fi

        exec "$real" --no-auto-update "''${args[@]}"
        EOF
        chmod +x $out/bin/copilot
      '';
    })
    glow
    gnumake
    go
    gopls
    jq
    libsecret
    nodejs_22
    nodePackages.typescript-language-server
    nodePackages.prettier
    nodePackages.eslint
    omnisharp-roslyn
    pacvim
    pandoc
    python3
    python3Packages.python-lsp-server
    ripgrep
    ruff
    rust-analyzer
    statix
    transmission_4
    tremc
    uv
    wget
    wl-clipboard
    # Disk Utilities
    dosfstools
    e2fsprogs
    ncdu
    parted

    # Fonts
    nerd-fonts.jetbrains-mono
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];

  fonts.fontconfig.enable = true;

  home.file.".inputrc".text = ''
    set editing-mode vi
    set show-mode-in-prompt on
    set vi-ins-mode-string "\1\e[6 q\2"
    set vi-cmd-mode-string "\1\e[2 q\2"
  '';

  # Persistent undo directory for neovim
  home.file."${config.xdg.stateHome}/nvim/undo/.keep" = {
    text = ''

    '';
  };

  programs.home-manager.enable = true;

  # Prevent long shutdown delays for user services
  systemd.user.settings.Manager.DefaultTimeoutStopSec = "2s";

  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      set -o vi
      # Arrow keys for history search in Vi mode
      bind '"\e[A": history-search-backward'
      bind '"\e[B": history-search-forward'
    '';
  };
  home.stateVersion = "24.11";

  home.sessionPath = ["$HOME/.local/bin"];

  home.shellAliases = {
    cat = "bat";
    pearpass-dev = "cd ~/repositories/pearpass-app-desktop && npx pear run -d .";
    tremc = "systemd-inhibit --why='Downloading torrents' --who='tremc' --what='sleep:idle' tremc";
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "Catppuccin Mocha";
      italic-text = "always";
    };
  };

  programs.lazygit = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    shellWrapperName = "y";
    theme = {
      icon = {
        # Use path-aware glob rules for repo roots/worktrees; plain dir-name rules
        # remain for the top-level container folders.
        prepend_globs = [
          {
            url = "**/repositories/*/";
            text = "";
            fg = "#00bcd4";
          }
          {
            url = "**/system-manifest/checkouts/";
            text = "";
            fg = "#00bcd4";
          }
          {
            url = "**/system-manifest/checkouts/*/";
            text = "";
            fg = "#00bcd4";
          }
          {
            url = "**/system-manifest/checkouts/*/hosts/";
            text = "";
            fg = "#00bcd4";
          }
          {
            url = "**/system-manifest/checkouts/*/modules/";
            text = "";
            fg = "#00bcd4";
          }
        ];

        prepend_dirs = [
          {
            name = "desktop";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "documents";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "downloads";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "games";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "music";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "pictures";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "public";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "repositories";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "screenshots";
            text = "󰄄";
            fg = "#00bcd4";
          }
          {
            name = "system-manifest";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "tabletop-games";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "templates";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "videos";
            text = "";
            fg = "#00bcd4";
          }
          {
            name = "wallpapers";
            text = "";
            fg = "#00bcd4";
          }
        ];
      };
    };
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.zathura = {
    enable = true;
    options.selection-clipboard = "clipboard";
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };

  # Systemd service for transmission-daemon
  systemd.user.services.transmission-daemon = {
    Unit = {
      Description = "Transmission BitTorrent Daemon";
      After = ["network.target"];
    };
    Service = {
      ExecStart = "${pkgs.transmission_4}/bin/transmission-daemon -f --no-auth --config-dir %h/.config/fragments --port 9091 --rpc-bind-address 127.0.0.1 --allowed 127.0.0.1";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };

  xdg.desktopEntries.btop = {
    name = "btop";
    exec = "ghostty -e btop";
    noDisplay = true;
  };

  xdg.desktopEntries."Mailspring" = {
    name = "Mailspring";
    comment = "The best email app for people and teams at work";
    genericName = "Mail Client";
    exec = "mailspring --password-store=gnome-libsecret %U";
    icon = "mailspring";
    categories = ["Network" "Email"];
    mimeType = ["x-scheme-handler/mailto" "x-scheme-handler/mailspring"];
  };

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/magnet" = ["tremc.desktop"];
      "application/x-bittorrent" = ["tremc.desktop"];
    };
    defaultApplications = {
      "x-scheme-handler/magnet" = ["tremc.desktop"];
      "application/x-bittorrent" = ["tremc.desktop"];
      "image/png" = ["imv.desktop"];
      "image/jpeg" = ["imv.desktop"];
      "image/gif" = ["imv.desktop"];
      "image/webp" = ["imv.desktop"];
      "image/bmp" = ["imv.desktop"];
      "image/tiff" = ["imv.desktop"];
      "image/svg+xml" = ["imv.desktop"];
      "application/pdf" = ["org.pwmt.zathura.desktop"];
      "text/plain" = ["nvim-text.desktop"];
      "text/markdown" = ["nvim-text.desktop"];
      "text/css" = ["nvim-text.desktop"];
      "application/json" = ["nvim-text.desktop"];
      "application/x-shellscript" = ["nvim-text.desktop"];
    };
  };
}
