# NixOS System Manifest

Declarative infrastructure source-of-truth. Defines system state, configurations, and packages for NixOS. Managed via **Nix Flakes** and **Home Manager**.

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

## Custom Scripts & Workflows

- **`zs` (Zellij Sessionizer)**: A custom adaptation of the popular `tmux-sessionizer` workflow. Uses `fzf` to quickly jump between projects in `~/repositories`, automatically bootstrapping a pre-configured 80/20 horizontal Vim/Terminal layout alongside a background OpenCode instance.
- **`sync-transmission-port`**: Synchronizes the transmission-daemon port with a specified value and restarts the service.
- **`generate-thumbnails`**: Generates PNG thumbnails for video files in `~/wallpapers` for use in the DMS wallpaper picker.
- **`setup_persistent_usb.sh`**: Initializes a fresh persistent NixOS installation on a target USB drive with LUKS encryption.
- **`update_usb.sh`**: Compiles and pushes the current NixOS flake configuration onto the portable USB drive.

## Usage

### Rebuild System
```bash
sudo nixos-rebuild switch --flake .#desktop
```

### Switch to Gaming Mode
Select **"NixOS - desktop-gaming-box"** from the bootloader menu (GRUB).
