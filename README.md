# NixOS System Manifest

Declarative infrastructure source-of-truth. Defines system state, configurations, and packages for NixOS. Managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop` and `usb` (live system).
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics (hyprglass blur/vibrancy plugin). Fully stable — no GNOME dependency.
- **Gaming Mode:** A dedicated specialisation (`gaming-box`) that boots directly into Steam Big Picture Mode with Gamescope.
- **Media & Productivity:**
  - **Spotify Player:** Terminal-based Spotify client (`spotify_player`) with streaming support.
  - **Transmission:** BitTorrent daemon with `tremc` TUI frontend.
  - **Mailspring:** Email client; credentials stored via GNOME Keyring (keyring service runs standalone, no GNOME shell required).
  - **Obsidian:** Note-taking application (with Home Manager plugin management).
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim (via nixvim).
- **AI Integrated:** Built-in configuration for **OpenCode** (AI Terminal Agent) and **GitHub Copilot CLI** with per-repo `AGENTS.md` instructions. Global Copilot instructions at `~/.copilot/AGENTS.md`.
- **Modular Architecture:** Configuration split into `hosts/` and `modules/home/` for maintainability.
- **PearPass:** Declarative wrapper for the PearPass P2P password manager (pinned to a specific commit).
- **Binary Caches:** Configured for `hyprland.cachix.org`, `nix-community.cachix.org`, and `ghostty.cachix.org` — flake-pinned packages download pre-built binaries instead of compiling from source.

## Flake Inputs

Packages tracked independently of nixpkgs for tighter version control:

| Input | Source | Why |
|-------|--------|-----|
| `hyprland` | `github:hyprwm/Hyprland` | nixpkgs lags behind Hyprland releases; required for hyprglass plugin API compatibility |
| `ghostty` | `github:ghostty-org/ghostty` | Stays on latest release; uses `ghostty.cachix.org` for fast installs |
| `home-manager` | `github:nix-community/home-manager` | Tracks nixpkgs-unstable |
| `nixvim` | `github:nix-community/nixvim` | Full Neovim config in Nix |
| `spotify-player` | `github:aome510/spotify-player` | Picks up latest client fixes before nixpkgs |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **AI-First Screenshots:** `screenshot-path` copies the absolute file path to clipboard by default (ideal for AI agents); pass `image` as second arg to copy the image itself.
- **Glassmorphism Aesthetics:** High-end transparent UI with premium blur, vibrancy, and dynamic colour-matched borders via Hyprland + hyprglass plugin. Terminals and Nautilus use `opacity 0.82`; browsers and media players are fully opaque.
- **Dynamic Theming:** Matugen-powered Hyprland borders and video wallpapers (`mpvpaper`) synced via a custom `wallpaper-hook` daemon.
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions (pane, tab, scroll, resize), freeing standard `Ctrl` shortcuts for applications. `Alt+s` enters Scroll mode; `Escape` exits any mode; `Alt+,`/`.` moves tabs.
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts.
- **GitHub Copilot CLI:** `Ctrl+Y` opens Neovim. `gh copilot` launched from the Zellij `copilot` tab.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `zs` | Zellij sessionizer — fuzzy-find project in `~/repositories`, attach or create session with 80/20 Neovim/terminal layout |
| `screenshot-path` | Screenshot to file; copies path (default) or image (`image` arg) to clipboard |
| `wallpaper-hook` | Daemon: picks wallpaper, extracts palette via Matugen, reloads Hyprland colours |
| `generate-thumbnails` | Generates PNG thumbnails for video files in `~/wallpapers` for the DMS wallpaper picker |
| `hypr-nav` | Hyprland focus movement with workspace wrapping at boundaries |
| `sync-transmission-port` | Updates transmission-daemon listening port |
| `setup_persistent_usb.sh` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `update_usb.sh` | Builds the `usb` flake output and installs it onto the mounted USB drive |

## Usage

### Rebuild System

```bash
sudo nixos-rebuild switch --flake .#desktop
```

### Dry Run (validates config without applying changes)

```bash
nixos-rebuild dry-build --flake .#desktop
```

### Update USB Drive

```bash
sudo ./update_usb.sh
```

### Switch to Gaming Mode

Select **"NixOS - desktop-gaming-box"** from the bootloader menu (GRUB).
