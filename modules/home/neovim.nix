{
  config,
  pkgs,
  ...
}: {
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    opts = {
      hlsearch = true;
    };

    colorschemes.dracula.enable = true;

    plugins = {
      web-devicons.enable = true;
      neo-tree = {
        enable = true;
        closeIfLastWindow = true;
        window = {
          position = "right";
          width = 30;
        };
      };
      treesitter = {
        enable = true;
        settings = {
          ensure_installed = "all";
          highlight.enable = true;
        };
      };
      telescope.enable = true;
      # vim-be-good is not a standard module yet, adding to extraPlugins
    };

    extraPlugins = with pkgs.vimPlugins; [
      opencode-nvim # vscode style sidebar for opencode
      vim-be-good
    ];

    keymaps = [
      {
        mode = "n";
        key = "<C-e>";
        action = "<cmd>Neotree toggle<cr>";
        options.desc = "Toggle File Explorer";
      }
      # --- Move Lines Down ---
      # Alt+Down
      {
        mode = "n";
        key = "<A-Down>";
        action = ":m .+1<CR>==";
        options.desc = "Move line down";
      }
      {
        mode = "i";
        key = "<A-Down>";
        action = "<Esc>:m .+1<CR>==gi";
        options.desc = "Move line down";
      }
      {
        mode = "v";
        key = "<A-Down>";
        action = ":m '>+1<CR>gv=gv";
        options.desc = "Move line down";
      }
      # --- Move Lines Up ---
      # Alt+Up
      {
        mode = "n";
        key = "<A-Up>";
        action = ":m .-2<CR>==";
        options.desc = "Move line up";
      }
      {
        mode = "i";
        key = "<A-Up>";
        action = "<Esc>:m .-2<CR>==gi";
        options.desc = "Move line up";
      }
      {
        mode = "v";
        key = "<A-Up>";
        action = ":m '<-2<CR>gv=gv";
        options.desc = "Move line up";
      }
    ];
  };

  # Keep aliases for muscle memory, though vi/vim alias options above handle most
  home.shellAliases = {
    vimtutor = "nvim +Tutor";
  };

  # Directly override the vimtutor binary to be sure
  home.file.".local/bin/vimtutor" = {
    executable = true;
    text = ''
      #!/bin/sh
      exec nvim +Tutor
    '';
  };
}
