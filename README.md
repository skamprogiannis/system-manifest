# NixOS System Manifest

Personal, flake-based NixOS configuration with Home Manager, Hyprland, Dank Material Shell (DMS), and a portable USB installation.

## Hosts

| Host | Purpose |
| --- | --- |
| `desktop` | NVIDIA desktop: full Hyprland environment, gaming, local AI, development tools |
| `laptop` | UEFI dual-boot Hyprland workstation |
| `usb` | Portable NixOS with persistent encrypted storage and optional RAM/host-scratch boot modes |

## Highlights

- **Desktop:** Hyprland, DMS, Ghostty, wallpaper-driven theming, Vesktop, Brave, and Spotify.
- **Development:** Go, Python, TypeScript, Neovim/Nixvim, Codex CLI and the official ChatGPT desktop app with Codex on all hosts, reusable skills, and static-analysis tools. Opt-in `codex-auto` enables bounded native delegation with task-specific model/effort choices and native auto-review.
- **Local AI:** Desktop-only Ollama models, on-demand Open WebUI (DMS launcher), and always-on local SearXNG.
- **Gaming:** Steam, GameMode, Gamescope, and optional Bannerlord dialogue/voice integrations.
- **Productivity:** Transmission, local Whisper dictation (`Super+T`), Obsidian, and screenshots.
- **Portability:** USB squashfs store, rollback generations, optional encrypted host scratch, and Codex session sync.

## Getting started

Run these commands **from the system-manifest worktree**, not another project's flake:

```bash
cd ~/system-manifest/main
git pull --ff-only
nixos-rebuild dry-build --flake .#desktop
sudo nixos-rebuild switch --flake .#desktop
```

For the laptop, use `.#laptop`. Update the USB using:

```bash
sudo update-usb ~/system-manifest/main
```

Deployment is manual. `nix flake check` validates configured host and support checks; it does not activate a host or replace device testing.

## Everyday commands

| Command | Purpose |
| --- | --- |
| `ai-search launch` | Start Open WebUI and open its standalone Brave window |
| `ai-search start\|stop\|status` | Control Open WebUI independently |
| `searxngctl start\|stop\|status` | Control SearXNG (normally starts at boot) |
| `torrent gui` | Open Transmission's local interface |
| `codex-auto status` | Inspect native workflow ownership and local delegation limits (offline) |
| `wallpaper-sync status --json` | Inspect desktop wallpaper synchronization |
| `nixos-usb-store-status` | Inspect USB store mode |
| `usb-host-scratch status` | Inspect portable host-scratch state |
| `codex-state-sync to-usb\|from-usb` | Sync active Codex sessions with the USB |

On the desktop, `services.ollama.syncModels = true` removes **every undeclared Ollama model**, including manually downloaded models. The declared inventory lives in `hosts/desktop/default.nix`.

## Documentation

- [System and desktop reference](docs/system.md): local AI, inputs, visual environment, and installed commands.
- [USB operations](docs/usb.md): install, update, rollback, scratch modes, and session synchronization.
- [CI and validation](docs/ci.md): check registry, workflows, and validation expectations.
- [Maintainer notes](docs/maintainers.md) and [agent instructions](AGENTS.md): development conventions and subsystem invariants.
- [Visual design](DESIGN.md) and [product principles](PRODUCT.md).
- [Codex workflow](modules/home/codex/WORKFLOW.md).
- [Bannerlord dialogue](modules/home/bannerlord-codex/README.md), [Bannerlord speech](modules/home/bannerlord-speech/README.md), and [desktop dictation](modules/home/desktop-dictation/README.md).

## License

Licensed under [GPL-3.0](LICENSE).
