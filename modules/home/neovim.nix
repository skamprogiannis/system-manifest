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
      clipboard = "unnamedplus";
      swapfile = false;
      number = true;
    };

    # Filetype-specific column rulers
    autoCmd = [
      {
        event = "FileType";
        pattern = "gitcommit";
        command = "setlocal colorcolumn=50,72"; # subject line / body wrap
      }
      {
        event = "FileType";
        pattern = "go";
        command = "setlocal colorcolumn=100"; # Uber Go style guide
      }
      {
        event = "FileType";
        pattern = [ "javascript" "typescript" "javascriptreact" "typescriptreact" ];
        command = "setlocal colorcolumn=100";
      }
      {
        event = "FileType";
        pattern = "cs";
        command = "setlocal colorcolumn=120"; # Microsoft C# conventions
      }
    ];

    initExtra = ''
      -- Set mapleader to Space
      vim.g.mapleader = ' '
    '';

    colorschemes.dracula.enable = true;

    # Transparent background — let Ghostty's RGBA glass show through
    extraConfigLuaPost = ''
      vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "SignColumn", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "LineNr", { bg = "NONE" })
    '';

    plugins = {
      lsp = {
        enable = true;
        servers = {
          gopls.enable = true;
          ts_ls.enable = true;
          rust_analyzer = {
            enable = true;
            installCargo = false;
            installRustc = false;
          };
          pylsp.enable = true;
          omnisharp.enable = true;
          nil_ls.enable = true;
        };
        keymaps = {
          lspBuf = {
            "gd" = "definition";
            "gr" = "references";
            "K" = "hover";
            "<leader>rn" = "rename";
            "<leader>ca" = "code_action";
          };
        };
      };

      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "path"; }
            { name = "buffer"; }
          ];
          snippet.expand = ''
            function(args)
              require('luasnip').lsp_expand(args.body)
            end
          '';
          mapping = {
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = ''
              cmp.mapping(function(fallback)
                local luasnip = require('luasnip')
                if cmp.visible() then
                  cmp.select_next_item()
                elseif luasnip.expand_or_jumpable() then
                  luasnip.expand_or_jump()
                else
                  fallback()
                end
              end, { 'i', 's' })
            '';
            "<S-Tab>" = ''
              cmp.mapping(function(fallback)
                local luasnip = require('luasnip')
                if cmp.visible() then
                  cmp.select_prev_item()
                elseif luasnip.jumpable(-1) then
                  luasnip.jump(-1)
                else
                  fallback()
                end
              end, { 'i', 's' })
            '';
          };
        };
      };

      luasnip.enable = true;

      web-devicons.enable = true;
      neo-tree = {
        enable = true;
        settings = {
          close_if_last_window = true;
          window = {
            position = "right";
            width = 30;
            mappings = {
              "l" = "close_node";
              "h" = "open";
            };
          };
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
      startify = {
        enable = true;
        configuration = {
          session_directory = "$HOME/.local/share/nvim/session";
          session_delete_buffers = true;
          session_autoload = 1;
          session_autosave = "yes";
          session_save_on_exit = "yes";
        };
      };
    };

    extraPlugins = with pkgs.vimPlugins; [
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
