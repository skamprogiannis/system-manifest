# Plan: NixVim Migration & Ghostty Fix

## 1. NixVim Migration

We will replace the standard `programs.neovim` with `programs.nixvim` to leverage the declarative configuration power of NixVim.

### 1.1 Update `flake.nix`

- **Add Input:** `nixvim` pointing to `github:nix-community/nixvim`.
- **Follows:** Ensure it follows `nixpkgs`.

### 1.2 Update `home.nix` or Flake Module

- **Import Module:** Add `inputs.nixvim.homeManagerModules.nixvim` to the home-manager modules list in `flake.nix`. This makes the `programs.nixvim` option available to `home.nix`.

### 1.3 Rewrite `modules/neovim.nix`

We will rewrite the entire file to use the new syntax.

- **Namespace:** Change `programs.neovim` to `programs.nixvim`.
- **Core Settings:**
  - `enable = true;`
  - `defaultEditor = true;`
  - `viAlias = true;`
  - `vimAlias = true;`
  - `colorschemes.dracula.enable = true;`
- **Plugins (Declarative):**
  - `plugins.treesitter.enable = true;` (with `settings.ensure_installed = "all"`)
  - `plugins.telescope.enable = true;`
  - `plugins.vim-be-good.enable = true;` (Check if module exists, else use `extraPlugins`)
  - `opencode-nvim`: Likely needs to go in `extraPlugins` unless a specific module exists.
- **Keymaps (The "Vimmy" Part):**
  - We will define a list of keymaps covering both `Alt+Up/Down` and the new `Alt+k/j`.
  - **Structure:**

    ```nix
    keymaps = [
      # Alt+Down / Alt+j (Move Down)
      { mode = "n"; key = "<A-Down>"; action = ":m .+1<CR>=="; }
      { mode = "n"; key = "<A-j>";    action = ":m .+1<CR>=="; }
      { mode = "i"; key = "<A-Down>"; action = "<Esc>:m .+1<CR>==gi"; }
      { mode = "i"; key = "<A-j>";    action = "<Esc>:m .+1<CR>==gi"; }
      { mode = "v"; key = "<A-Down>"; action = ":m '>+1<CR>gv=gv"; }
      { mode = "v"; key = "<A-j>";    action = ":m '>+1<CR>gv=gv"; }

      # Alt+Up / Alt+k (Move Up)
      { mode = "n"; key = "<A-Up>";   action = ":m .-2<CR>=="; }
      { mode = "n"; key = "<A-k>";    action = ":m .-2<CR>=="; }
      { mode = "i"; key = "<A-Up>";   action = "<Esc>:m .-2<CR>==gi"; }
      { mode = "i"; key = "<A-k>";    action = "<Esc>:m .-2<CR>==gi"; }
      { mode = "v"; key = "<A-Up>";   action = ":m '<-2<CR>gv=gv"; }
      { mode = "v"; key = "<A-k>";    action = ":m '<-2<CR>gv=gv"; }
    ];
    ```

## 2. Ghostty Numpad Fix

We will fix the keypad enter issue by forcing it to send the correct text sequence.

### 2.1 Update `modules/ghostty.nix`

- Add a keybinding to the `settings` attribute.
  ```nix
  keybind = [ "kp_enter=text:\\x0d" ];
  ```
  _Note: `\x0d` is the hex code for Carriage Return (Enter)._

## 3. Execution Steps

1.  **Modify `flake.nix`**: Add `nixvim` input and module import.
2.  **Modify `modules/neovim.nix`**: Rewrite for NixVim.
3.  **Modify `modules/ghostty.nix`**: Add keybind.
4.  **Dry Run**: `nixos-rebuild dry-build --flake .#home-desktop`.
5.  **Apply**: `sudo nixos-rebuild switch --flake .#home-desktop`.
6.  **Verify**:
    - Check Neovim starts.
    - Test Alt+Down/Up and Alt+j/k.
    - Test Numpad Enter in Ghostty.
