# NixOS System Manifest

My personal NixOS configuration — a declarative, reproducible system built around Hyprland with glassmorphism aesthetics, dual Greek/English keyboard support, and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) as the desktop shell.

Managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop` and `usb` (live/portable system).
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics powered by the [hyprglass](https://github.com/hyprnux/hyprglass) blur/vibrancy plugin (`glass` preset). Ghostty uses native `background-opacity` for true liquid-glass (background transparent, text fully opaque).
- **USB: Dual Session** — USB host boots with GDM offering a session picker between **GNOME** and **Hyprland**. Uses a **hybrid squashfs** Nix store (compressed read-only image + tmpfs overlay) for near-ISO boot performance on lab machines.
- **Gaming Mode:** A dedicated specialisation (`gaming-box`) that boots directly into Steam Big Picture Mode with Gamescope.
- **Media & Productivity:**
  - **Spotify Player:** Terminal-based Spotify client (`spotify_player`) with streaming support.
  - **Transmission:** BitTorrent daemon with `tremc` TUI frontend.
  - **Mailspring:** Email client; credentials stored via GNOME Keyring (runs standalone, no GNOME shell required).
  - **Obsidian:** Note-taking application with Home Manager plugin management.
  - **Vesktop:** Discord client (Translucence CSS theme managed imperatively).
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim (via nixvim). Neovim uses the Dracula colorscheme with a transparent background (matches Ghostty glass). Also registered as the default text editor via an `nvim-text` XDG desktop entry (opens in Ghostty).
- **AI Integrated:** Built-in configuration for **GitHub Copilot CLI** with per-repo `AGENTS.md` instructions. Global Copilot instructions at `~/.copilot/AGENTS.md`.
- **Modular Architecture:** Configuration split across `hosts/` (system-level) and `modules/home/` (user-level) for maintainability.
- **PearPass:** Declarative wrapper for the PearPass P2P password manager AppImage, with native messaging support for browser extensions.
- **Binary Caches:** Configured for `hyprland.cachix.org`, `nix-community.cachix.org`, and `ghostty.cachix.org` — pre-built binaries avoid local compilation.

## Flake Inputs

Packages tracked independently of nixpkgs for tighter version control:

| Input | Source | Why |
|-------|--------|-----|
| `hyprland` | `github:hyprwm/Hyprland` | nixpkgs lags behind Hyprland releases; required for hyprglass plugin API compatibility |
| `ghostty` | `github:ghostty-org/ghostty` | Stays on latest release; uses `ghostty.cachix.org` for fast installs |
| `home-manager` | `github:nix-community/home-manager` | Tracks nixpkgs-unstable |
| `nixvim` | `github:nix-community/nixvim` | Full Neovim config in Nix |
| `spotify-player` | `github:aome510/spotify-player` | Picks up latest client fixes before nixpkgs |
| `pearpass-app-desktop` | `github:tetherto/pearpass-app-desktop` | P2P password manager; AppImage wrapped with FHS env for NixOS |
| `visual-explainer` | `github:nicobailon/visual-explainer` | HTML visualization generator for architecture diagrams and code explanations |
| `impeccable` | `github:pbakaus/impeccable` | Frontend design skill with 20 commands for typography, color, layout, and motion |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **Glassmorphism Aesthetics:** Ghostty uses `background-opacity = 0.35` (native RGBA) so the terminal background is near-transparent while text stays fully opaque, giving a liquid-glass terminal. `minimum-contrast = 3.0` improves legibility by enforcing a stronger foreground/background contrast floor. The hyprglass Hyprland plugin is active for blur/tint effects on transparent surfaces.
- **Dynamic Theming:** Matugen-powered Hyprland border colours, GTK4/Nautilus colours, and video wallpapers via **linux-wallpaperengine** synced via a custom `wallpaper-hook` daemon. GTK uses the **Dracula** theme; Ghostty uses the built-in **Dracula** colour scheme.
- **Cursor:** Adwaita (system default). HollowKnight cursor theme is built and available for future use.
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions; `Escape` exits any mode back to Normal and is unbound in Normal mode so it passes through to terminal apps (Vim, Copilot CLI, etc.).
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts.
- **Window Controls:** `Super` + left-drag moves windows, `Super` + right-drag resizes. `Super+Ctrl+H/J/K/L` (or arrows) resizes in directions. `Super` + `-` shrinks and `Super` + `+` grows the window.
- **Window Controls:** `Super` + left-drag moves windows, `Super` + right-drag resizes. `Super` + `-` shrinks and `Super` + `+` grows the active window.
- **Launcher Shortcuts:** `Super+E` opens **Yazi** in Ghostty; `Super+Shift+E` opens **Nautilus**.
- **Screenshots:** `dms screenshot` handles region/window/full capture with image-to-clipboard. `screenshot-path-copy` wraps it to copy the file path instead (useful for sharing with AI agents). Screen recording via **Kooha** GUI.
- **GitHub Copilot CLI:** `Ctrl+Y` opens Neovim. `gh copilot` launched from the Zellij `copilot` tab.
- **DNS:** Quad9 (`9.9.9.9`) for privacy-focused DNS resolution.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `zs` | Zellij sessionizer — fuzzy-find project in `~/repositories`, attach or create session with 80/20 Neovim/terminal layout |
| `screenshot-path-copy` | Wraps `dms screenshot` to copy the saved file path to clipboard (instead of image) |
| `wallpaper-hook` | Daemon: picks wallpaper via linux-wallpaperengine, extracts palette via Matugen, reloads Hyprland border and GTK4/Nautilus colours |
| `generate-thumbnails` | Generates JPG thumbnails for WallpaperEngine projects in `~/wallpapers` for the DMS wallpaper picker |
| `hypr-nav` | Hyprland focus movement with workspace wrapping at boundaries |
| `sync-transmission-port` | Updates transmission-daemon listening port |
| `sync-copilot-sessions` | Syncs `~/.copilot/session-state/` between desktop and USB (`to-usb` / `from-usb`) |
| `specify` | Spec Kit CLI wrapper — scaffolds spec-driven development for new projects |
| `setup_persistent_usb.sh` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `update_usb.sh` | Builds the `usb` flake output, installs it onto the USB, then creates a squashfs image of the Nix store for fast boot performance |

## Usage

### Rebuild Desktop

```bash
sudo nixos-rebuild switch --flake .#desktop
```

### Dry Run (validate config without applying)

```bash
nixos-rebuild dry-build --flake .#desktop
```

### Update USB Drive

```bash
sudo ./update_usb.sh
```

The script auto-fetches `squashfs-tools` via `nix-shell` if needed. After `nixos-install`, it compresses `/nix/store` into a squashfs image. At boot, the USB mounts this compressed image via overlayfs — reads are sequential and fast (like an ISO), while writes go to a 2 GB tmpfs (volatile, reset on reboot).

### Switch to Gaming Mode

Select **"NixOS - desktop-gaming-box"** from the bootloader menu (GRUB).

### Sync Copilot Sessions (Desktop ↔ USB)

```bash
sync-copilot-sessions to-usb    # before leaving for a lab machine
sync-copilot-sessions from-usb  # after returning
```
