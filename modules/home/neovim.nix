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

    globals.mapleader = " ";

    opts = {
      hlsearch = true;
      swapfile = false;
      number = true;
      relativenumber = true;
      expandtab = true;
      tabstop = 4;
      shiftwidth = 4;
      softtabstop = 4;
      undofile = true;
      undodir = "$HOME/.local/state/nvim/undo";
    };

    # Filetype-specific column rulers and indentation
    autoCmd = [
      {
        event = "FileType";
        pattern = "gitcommit";
        command = "setlocal colorcolumn=50,72"; # subject line / body wrap
      }
      {
        event = "FileType";
        pattern = "go";
        # gofmt uses real tabs; display them at width 4
        command = "setlocal noexpandtab tabstop=4 shiftwidth=4 softtabstop=4 colorcolumn=100";
      }
      {
        event = "FileType";
        pattern = [ "javascript" "typescript" "javascriptreact" "typescriptreact" ];
        # Prettier standard: 2 spaces
        command = "setlocal tabstop=2 shiftwidth=2 softtabstop=2 colorcolumn=100";
      }
      {
        event = "FileType";
        pattern = "nix";
        # alejandra/nixfmt: 2 spaces
        command = "setlocal tabstop=2 shiftwidth=2 softtabstop=2";
      }
      {
        event = "FileType";
        pattern = "cs";
        command = "setlocal colorcolumn=120"; # Microsoft C# conventions
      }
    ];

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
      undotree.enable = true;
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
      # --- Clipboard (system) ---
      {
        mode = [ "n" "v" ];
        key = "<leader>y";
        action = ''"+y'';
        options.desc = "Yank to system clipboard";
      }
      {
        mode = "n";
        key = "<leader>Y";
        action = ''"+Y'';
        options.desc = "Yank to EOL to system clipboard";
      }
      {
        mode = "n";
        key = "<leader>p";
        action = ''"+p'';
        options.desc = "Paste from system clipboard (after)";
      }
      {
        mode = "n";
        key = "<leader>P";
        action = ''"+P'';
        options.desc = "Paste from system clipboard (before)";
      }
      # --- Void-register delete (preserve yank) ---
      {
        mode = [ "n" "v" ];
        key = "<leader>d";
        action = ''"_d'';
        options.desc = "Delete to void register (keep yank intact)";
      }
      # --- Paste-over without clobbering register ---
      {
        mode = "v";
        key = "<leader>p";
        action = ''"_dP'';
        options.desc = "Paste over selection (keep yank intact)";
      }
      # --- Move lines ---
      {
        mode = "n";
        key = "<leader>j";
        action = ":m .+1<CR>==";
        options.desc = "Move line down";
      }
      {
        mode = "n";
        key = "<leader>k";
        action = ":m .-2<CR>==";
        options.desc = "Move line up";
      }
      {
        mode = "v";
        key = "<leader>j";
        action = ":m '>+1<CR>gv=gv";
        options.desc = "Move selection down";
      }
      {
        mode = "v";
        key = "<leader>k";
        action = ":m '<-2<CR>gv=gv";
        options.desc = "Move selection up";
      }
      # --- UndoTree ---
      {
        mode = "n";
        key = "<leader>u";
        action = "<cmd>UndotreeToggle<cr>";
        options.desc = "Toggle UndoTree";
      }

      # --- Telescope ---
      {
        mode = "n";
        key = "<leader>ff";
        action = "<cmd>Telescope find_files<cr>";
        options.desc = "Find files";
      }
      {
        mode = "n";
        key = "<leader>fg";
        action = "<cmd>Telescope live_grep<cr>";
        options.desc = "Live grep";
      }
      {
        mode = "n";
        key = "<leader>fb";
        action = "<cmd>Telescope buffers<cr>";
        options.desc = "Buffers";
      }
      {
        mode = "n";
        key = "<leader>fh";
        action = "<cmd>Telescope help_tags<cr>";
        options.desc = "Help tags";
      }
    ];
  };

}
