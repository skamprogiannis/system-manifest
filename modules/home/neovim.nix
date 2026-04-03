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
      undodir = "${config.home.homeDirectory}/.local/state/nvim/undo";
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
        pattern = [ "c" "cpp" ];
        command = "setlocal tabstop=4 shiftwidth=4 softtabstop=4 colorcolumn=100";
      }
      {
        event = "FileType";
        pattern = "cs";
        command = "setlocal colorcolumn=120"; # Microsoft C# conventions
      }
    ];

    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "mocha";
      settings.transparent_background = true;
    };

    # Transparent background — let Ghostty's RGBA glass show through
    extraConfigLuaPost = ''
      -- Snacks dashboard expects Lazy.nvim stats. Nixvim doesn't use lazy.nvim,
      -- so expose equivalent stats by counting packaged start plugins.
      do
        local ok = pcall(require, "lazy.stats")
        if not ok then
          local fallback_start = (vim.uv and vim.uv.hrtime) and vim.uv.hrtime() or nil
          local cached_startup_ms = nil
          local cached_clk_tck = nil

          local function read_first_line(path)
            local file = io.open(path, "r")
            if not file then
              return nil
            end
            local line = file:read("*l")
            file:close()
            return line
          end

          local function get_clk_tck()
            if cached_clk_tck then
              return cached_clk_tck
            end
            local out = vim.fn.system({ "getconf", "CLK_TCK" })
            if vim.v.shell_error ~= 0 then
              return nil
            end
            local value = tonumber(vim.fn.trim(out))
            if not value or value <= 0 then
              return nil
            end
            cached_clk_tck = value
            return cached_clk_tck
          end

          local function linux_process_elapsed_ms()
            local stat_line = read_first_line("/proc/self/stat")
            local uptime_line = read_first_line("/proc/uptime")
            if not stat_line or not uptime_line then
              return nil
            end

            local fields = stat_line:match("^%d+ %b() (.+)$")
            if not fields then
              return nil
            end

            local start_ticks = nil
            local field_index = 0
            for field in fields:gmatch("%S+") do
              field_index = field_index + 1
              if field_index == 20 then
                start_ticks = tonumber(field)
                break
              end
            end

            local uptime_s = tonumber(uptime_line:match("^(%S+)"))
            local clk_tck = get_clk_tck()
            if not start_ticks or not uptime_s or not clk_tck then
              return nil
            end

            local elapsed_ms = (uptime_s - (start_ticks / clk_tck)) * 1000
            if elapsed_ms < 0 then
              return nil
            end
            return math.floor(elapsed_ms + 0.5)
          end

          local function fallback_elapsed_ms()
            if not (fallback_start and vim.uv and vim.uv.hrtime) then
              return 0
            end
            return math.floor(((vim.uv.hrtime() - fallback_start) / 1e6) + 0.5)
          end

          local function compute_startup_ms()
            return linux_process_elapsed_ms() or fallback_elapsed_ms()
          end

          vim.api.nvim_create_autocmd("VimEnter", {
            once = true,
            callback = function()
              cached_startup_ms = compute_startup_ms()
            end,
          })

          local function nixvim_stats()
            local seen = {}
            local count = 0
            for _, root in ipairs(vim.opt.packpath:get()) do
              if root:find("vim-pack-dir", 1, true) then
                local plugins = vim.fn.globpath(root .. "/pack/*/start", "*", false, true)
                for _, plugin_dir in ipairs(plugins) do
                  if vim.fn.isdirectory(plugin_dir) == 1 and not seen[plugin_dir] then
                    seen[plugin_dir] = true
                    count = count + 1
                  end
                end
              end
            end

            if cached_startup_ms == nil then
              cached_startup_ms = compute_startup_ms()
            end

            return {
              startuptime = cached_startup_ms,
              loaded = count,
              count = count,
            }
          end

          package.preload["lazy.stats"] = function()
            return {
              stats = nixvim_stats,
            }
          end
        end
      end

      vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "SignColumn", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "LineNr", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "Visual", { bg = "#3f4152", bold = true })

      -- Consistent rounded borders on all floats via winborder (Neovim 0.11+)
      vim.o.winblend = 12
      if vim.fn.exists("+winborder") == 1 then
        vim.o.winborder = "rounded"
      end
      vim.diagnostic.config({
        float = {
          focusable = false,
          style = "minimal",
          winblend = 12,
        },
      })

      -- git-worktree + snacks picker wrapper

      _G.git_worktree_picker = function()
        local lines = vim.fn.systemlist("git worktree list --porcelain")
        local items = {}
        local entry = {}
        for _, line in ipairs(lines) do
          local path  = line:match("^worktree (.+)")
          local branch = line:match("^branch refs/heads/(.+)")
          if path then
            entry.path = path
          elseif branch then
            entry.branch = branch
          elseif line == "" and entry.path then
            table.insert(items, {
              text = string.format("%-30s  %s", entry.branch or "(detached)", entry.path),
              wt_path = entry.path,
            })
            entry = {}
          end
        end
        if entry.path then
          table.insert(items, {
            text = string.format("%-30s  %s", entry.branch or "(detached)", entry.path),
            wt_path = entry.path,
          })
        end
        Snacks.picker.pick("worktrees", {
          finder  = function() return items end,
          title   = "Git Worktrees",
          confirm = function(picker, item)
            picker:close()
            require("git-worktree").switch_worktree(item.wt_path)
          end,
        })
      end
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
          clangd.enable = true;
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
          c = [ "clang_format" ];
          cpp = [ "clang_format" ];
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
          c = [ "cppcheck" ];
          cpp = [ "cppcheck" ];
        };
      };

      lualine = {
        enable = true;
        settings.options.theme = "auto";
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

      treesitter = {
        enable = true;
        settings = {
          ensure_installed = "all";
          highlight.enable = true;
        };
      };
      snacks = {
        enable = true;
        settings = {
          dashboard.enabled = true;
          notifier.enabled = true;
          gitBrowse.enabled = true;
          picker.enabled = true;
          indent.enabled = false;
          scroll.enabled = false;
          animate.enabled = false;
        };
      };
    };

    extraPlugins = with pkgs.vimPlugins; [
      vim-be-good
      git-worktree-nvim
    ];

    keymaps = [
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
      # --- Find / Explorer (snacks picker) ---
      {
        mode = "n";
        key = "<leader>e";
        action = "<cmd>lua Snacks.explorer()<cr>";
        options.desc = "File explorer";
      }
      {
        mode = "n";
        key = "<leader>ff";
        action = "<cmd>lua Snacks.picker.files()<cr>";
        options.desc = "Find files";
      }
      {
        mode = "n";
        key = "<leader>fg";
        action = "<cmd>lua Snacks.picker.grep()<cr>";
        options.desc = "Live grep";
      }
      {
        mode = "n";
        key = "<leader>fr";
        action = "<cmd>lua Snacks.picker.recent()<cr>";
        options.desc = "Recent files";
      }
      {
        mode = "n";
        key = "<leader>fb";
        action = "<cmd>lua Snacks.picker.buffers()<cr>";
        options.desc = "Buffers";
      }
      {
        mode = "n";
        key = "<leader>fh";
        action = "<cmd>lua Snacks.picker.help()<cr>";
        options.desc = "Help tags";
      }
      # --- Format ---
      {
        mode = [ "n" "v" ];
        key = "<leader>cf";
        action = "<cmd>lua require('conform').format({ async = true })<cr>";
        options.desc = "Format buffer";
      }
      # --- Git worktrees ---
      {
        mode = "n";
        key = "<leader>gw";
        action = "<cmd>lua _G.git_worktree_picker()<cr>";
        options.desc = "Git worktrees";
      }
      # --- Diagnostics ---
      {
        mode = "n";
        key = "<leader>cd";
        action = "<cmd>lua vim.diagnostic.open_float()<cr>";
        options.desc = "Line diagnostics";
      }
      {
        mode = "n";
        key = "<leader>sd";
        action = "<cmd>lua Snacks.picker.diagnostics()<cr>";
        options.desc = "Diagnostics";
      }
      {
        mode = "n";
        key = "<leader>sD";
        action = "<cmd>lua Snacks.picker.diagnostics_buffer()<cr>";
        options.desc = "Buffer diagnostics";
      }
      {
        mode = "n";
        key = "]d";
        action = "<cmd>lua vim.diagnostic.goto_next()<cr>";
        options.desc = "Next diagnostic";
      }
      {
        mode = "n";
        key = "[d";
        action = "<cmd>lua vim.diagnostic.goto_prev()<cr>";
        options.desc = "Prev diagnostic";
      }
    ];
  };

}
