# NixOS System Manifest

This repository contains the declarative configuration for my NixOS system, managed via **Nix Flakes** and **Home Manager**.

## 🚀 Features

- **Dual Desktop Environment:**
  - **GNOME:** Stable, daily driver environment.
  - **Hyprland:** Tiling window manager with a custom "Cyberpunk" aesthetic.
- **Gaming Mode:** A dedicated "Specialisation" (`gaming-box`) that strips away the desktop environment and boots directly into Steam Big Picture Mode for maximum performance.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim.
- **AI Integrated:** Built-in configuration for **OpenCode** (AI Terminal Agent) with Context7 documentation support. (Note: Personal AI model authentication required).
- **Modular Architecture:** Configuration split into `modules/` for maintainability.

## 🛠️ Usage

### Rebuild System

```bash
# Standard Rebuild
sudo nixos-rebuild switch --flake .
```

### Switch to Gaming Mode

Select **"NixOS - gaming-box"** from the bootloader menu (GRUB).

### Directory Structure

- `flake.nix`: Entry point and inputs (NixOS Unstable).
- `configuration.nix`: System-level config (Boot, Hardware, Graphics, GRUB Theme).
- `home.nix`: User-level config (Imports modules).
- `modules/`:
  - `hyprland.nix`: Window manager & aesthetics.
  - `ghostty.nix`: Terminal configuration.
  - `neovim.nix`: Editor setup.
  - `opencode.nix`: AI agent configuration.
  - `pearpass.nix`: Custom wrapper for PearPass password manager.

## 🤖 AI Workflow (OpenCode)

This repository works hand-in-hand with the **OpenCode** agent.

- **Generations:** Git commits are kept 1:1 with NixOS generations (`gen(1)`, `gen(2)`, etc.).
- **Agents:** See `AGENTS.md` for operational rules and tips.
