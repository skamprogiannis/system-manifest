# NixOS System Manifest

This repository contains the declarative configuration for my NixOS system, managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop`, `laptop`, and `usb` (live system).
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
  - `laptop/`: Laptop-specific power management.
  - `usb/`: Live USB configuration.
- `home.nix`: User-level config entry point.
- `modules/`:
  - `home/`: User-facing configurations (Ghostty, Hyprland, Neovim, Brave, Firefox, etc.).
  - `nixos/`: System-level module configurations (GNOME, Hyprland).
