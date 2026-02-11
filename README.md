# NixOS System Manifest

This repository contains the declarative configuration for my NixOS system, managed via **Nix Flakes** and **Home Manager**.

## 🚀 Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `home-desktop` and `laptop`.
- **Dual Desktop Environment:**
  - **GNOME:** Stable, daily driver environment.
  - **Hyprland:** Tiling window manager with a custom "Cyberpunk" aesthetic.
- **Gaming Mode:** A dedicated "Specialisation" (`gaming-box`) that strips away the desktop environment and boots directly into Steam Big Picture Mode for maximum performance.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim (managed via custom modules).
- **AI Integrated:** Built-in configuration for **OpenCode** (AI Terminal Agent) with Context7 documentation support.
- **Modular Architecture:** Configuration split into `hosts/` and `modules/` for maintainability.

## 🎨 Typography ("Cattle Mode")

Fonts are treated as infrastructure, not pets. We enforce a strictly consistent typography stack across all environments (Desktop, Laptop, Live USB, TTY).

- **Monospace:** `JetBrains Mono Nerd Font` (For Terminals, Code, and GNOME UI)
- **UI/Sans:** `Adwaita` (GNOME Default)
- **Serif:** `Noto Serif`

This is enforced via `fontconfig` for the system and explicit `dconf` locks for GNOME and Terminal profiles, ensuring no configuration drift occurs between reinstalls or new machines.

## 🛠️ Usage

### Rebuild System

```bash
# Standard Rebuild (automatically detects host)
sudo nixos-rebuild switch --flake .
```

### Switch to Gaming Mode

Select **"NixOS - gaming-box"** from the bootloader menu (GRUB).

### Directory Structure

- `flake.nix`: Entry point and inputs.
- `hosts/`: Host-specific configurations.
  - `common/`: Shared system configuration (Boot, Networking, basic packages).
  - `home-desktop/`: Desktop-specific hardware and overrides.
  - `laptop/`: Laptop-specific hardware and power management.
- `home.nix`: User-level config entry point.
- `modules/`: Feature-specific modules (Brave, Ghostty, Hyprland, Neovim, etc.).

## 🤖 AI Workflow (OpenCode)

This repository works hand-in-hand with the **OpenCode** agent.

- **Generations:** Git commits are strictly kept 1:1 with NixOS generations (`gen(N)`).
- **Agents:** See `AGENTS.md` for operational rules and bug reporting workflows.
