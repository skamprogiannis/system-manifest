# NixOS System Manifest

This repository contains the declarative configuration for my NixOS system, managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop` and `usb` (live system).
- **Dual Desktop Environment:**
  - **GNOME:** Stable, daily driver environment.
  - **Hyprland:** Tiling window manager with custom aesthetics.
- **Gaming Mode:** A dedicated "Specialisation" (`gaming-box`) that strips away the desktop environment and boots directly into Steam Big Picture Mode with Gamescope.
- **Media & Productivity:**
  - **Spotify Player:** Terminal-based Spotify client with streaming support.
  - **Fragments:** GTK-based BitTorrent client using Transmission daemon.
  - **Evolution & Geary:** Email clients configured with GNOME Keyring.
  - **Obsidian:** Note-taking application.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim (via nixvim).
- **AI Integrated:** Built-in configuration for **OpenCode** (AI Terminal Agent) with Context7 documentation support.
- **Modular Architecture:** Configuration split into `hosts/` and `modules/` for maintainability.
- **Workflow Optimizations:**
  - **AI-First Screenshots:** Advanced screenshot utility (`screenshot-path`) that copies absolute paths to clipboard by default (for OpenCode) and images when modified by `Shift`.
  - **Dynamic Theming:** Matugen-powered Hyprland borders and dynamic video wallpapers (`mpvpaper`) synced via a custom `wallpaper-hook` daemon.
  - **Zellij Navigation:** Refactored keybindings to use `Alt` for navigation, freeing up standard `Ctrl` shortcuts for internal application use.
  - **System Cleanup:** Stripped out legacy GNOME components (`xterm`, `rygel`) to ensure a lean, stable environment.
  - **Multi-Monitor Logic:** Explicit workspace pinning to ensure `DP-1` (Primary) and `HDMI-A-1` (Secondary) behave predictably.

## Typography

Fonts are treated as infrastructure, not pets. We enforce a strictly consistent typography stack across all environments (Desktop, Laptop, USB, TTY).

- **Monospace:** `JetBrains Mono Nerd Font` (For Terminals, Code, and GNOME UI)
- **UI/Sans:** `Adwaita` (GNOME Default)
- **Serif:** `Noto Serif`

This is enforced via `fontconfig` for the system and explicit `dconf` locks for GNOME and Terminal profiles.

## Usage

### Rebuild System

```bash
# Rebuild for desktop (or laptop, usb)
sudo nixos-rebuild switch --flake .#desktop
```

### Dry Run Build

```bash
# Check for errors without applying
sudo nixos-rebuild dry-build --flake .#desktop
```

### Switch to Gaming Mode

Select **"NixOS - desktop-gaming-box"** from the bootloader menu (GRUB).

## Directory Structure

- `flake.nix`: Entry point and NixOS/Home Manager inputs.
- `hosts/`: Host-specific configurations.
  - `common/`: Shared system configuration (Boot, Networking, Audio, Printing).
  - `desktop/`: Desktop-specific hardware, bootloader, and NVIDIA drivers.
  - `usb/`: Live USB configuration.
- `home.nix`: User-level config entry point.
- `modules/`:
  - `home/`: User-facing configurations (Ghostty, Hyprland, Neovim, Brave, Firefox, etc.).
  - `nixos/`: System-level module configurations (GNOME, Hyprland).
## Custom Scripts & Workflows

### `zs` (Zellij Sessionizer)
A lightning-fast project manager. Type `zs` in any terminal to fuzzy-find your repositories. It automatically launches a Zellij session with a custom horizontal layout: Neovim (with Neo-tree on the right) takes the top 80%, and a raw terminal takes the bottom 20%. It also launches an OpenCode instance in a background tab.

### `desktop-widget`
A script that uses `nwg-wrapper` and `fastfetch` to paint system statistics directly onto the Hyprland wallpaper. It runs automatically on startup.

### `update_usb.sh` & `setup_persistent_usb.sh`
*   `setup_persistent_usb.sh`: Run this ONCE to completely format a target USB drive with a LUKS-encrypted ext4 partition and a generic EFI boot sector.
*   `update_usb.sh`: Run this to compile and push your current NixOS flake configuration onto the portable USB drive.

### `sync-transmission-port`
Updates Transmission's `settings.json` with a new port and restarts the daemon. Usage: `sync-transmission-port <port_number>`.

### `generate-thumbnails`
Scans `~/wallpapers` for MP4 files and uses `ffmpeg` to generate static PNG thumbnails in a `.thumbnails` subdirectory. These thumbnails are used by the DMS UI so you don't have to load raw video files into the wallpaper picker.
