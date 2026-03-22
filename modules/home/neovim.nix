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

      cmp.enable = false;

      blink-cmp = {
        enable = true;
        settings = {
          keymap.preset = "default";
          appearance.nerd_font_variant = "mono";
          sources.default = [ "lsp" "path" "snippets" "buffer" ];
          signature.enabled = true;
        };
      };

      web-devicons.enable = true;
      undotree.enable = true;

      conform-nvim = {
        enable = true;
        settings = {
          format_on_save = {
            timeout_ms = 2000;
            lsp_fallback = false;
          };
          formatters_by_ft = {
            javascript = [ "prettier" ];
            typescript = [ "prettier" ];
            javascriptreact = [ "prettier" ];
            typescriptreact = [ "prettier" ];
            python = [ "ruff_format" ];
            nix = [ "alejandra" ];
          };
        };
      };

      lint = {
        enable = true;
        lintersByFt = {
          javascript = [ "eslint" ];
          typescript = [ "eslint" ];
          javascriptreact = [ "eslint" ];
          typescriptreact = [ "eslint" ];
          python = [ "ruff" ];
          nix = [ "statix" ];
        };
      };

      lualine = {
        enable = true;
        settings.options.theme = "dracula";
      };

      gitsigns = {
        enable = true;
        settings.signs = {
          add.text = "▎";
          change.text = "▎";
          delete.text = "";
          topdelete.text = "";
          changedelete.text = "▎";
        };
      };

      which-key.enable = true;

      flash.enable = true;
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
      snacks = {
        enable = true;
        settings = {
          dashboard.enabled = true;
          notifier.enabled = true;
          gitBrowse.enabled = true;
          indent.enabled = false;
          scroll.enabled = false;
          animate.enabled = false;
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
      # --- Git hunks (gitsigns) ---
      {
        mode = "n";
        key = "]h";
        action = "<cmd>Gitsigns next_hunk<cr>";
        options.desc = "Next git hunk";
      }
      {
        mode = "n";
        key = "[h";
        action = "<cmd>Gitsigns prev_hunk<cr>";
        options.desc = "Prev git hunk";
      }
      {
        mode = "n";
        key = "<leader>hs";
        action = "<cmd>Gitsigns stage_hunk<cr>";
        options.desc = "Stage hunk";
      }
      {
        mode = "n";
        key = "<leader>hu";
        action = "<cmd>Gitsigns undo_stage_hunk<cr>";
        options.desc = "Undo stage hunk";
      }
      {
        mode = "n";
        key = "<leader>hp";
        action = "<cmd>Gitsigns preview_hunk<cr>";
        options.desc = "Preview hunk";
      }
      # --- Flash jump ---
      {
        mode = [ "n" "o" "v" ];
        key = "s";
        action = "<cmd>lua require('flash').jump()<cr>";
        options.desc = "Flash jump";
      }
      {
        mode = [ "n" "o" "v" ];
        key = "S";
        action = "<cmd>lua require('flash').treesitter()<cr>";
        options.desc = "Flash treesitter jump";
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
