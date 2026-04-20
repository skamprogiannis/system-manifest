# NixOS System Manifest

My personal NixOS configuration — a declarative, reproducible system built around Hyprland with glassmorphism aesthetics, dual Greek/English keyboard support, and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) as the desktop shell.

Managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop` and `usb` (live/portable system).
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics powered by the [hyprglass](https://github.com/hyprnux/hyprglass) blur/vibrancy plugin (`light` theme, `default` preset), patched locally for current Hyprland API compatibility. Ghostty uses native `background-opacity` for true liquid-glass (background transparent, text fully opaque).
- **USB: Dual Session** — USB host boots with GDM offering **Hyprland** as the primary portable session plus **GNOME** as a fallback. That fallback stays intentionally minimal so Hyprland launchers do not inherit the stock GNOME app bundle. Uses a **hybrid squashfs** Nix store (compressed read-only image + tmpfs overlay) for near-ISO boot performance on lab machines; only new `/nix/store` writes use the tmpfs upper layer, while `/home` stays on the persistent encrypted USB root filesystem. Docker's heavy writable state is routed to ephemeral host-local scratch storage when available, falling back to tmpfs when no suitable host partition can be mounted.
- **Gaming Mode:** A dedicated specialisation (`gaming-box`) that boots directly into Steam Big Picture Mode with Gamescope.
- **Media & Productivity:**
  - **Spotify Player:** Terminal-based Spotify client (`spotify_player`) with streaming support. The wrapper authenticates interactively before bootstrapping the background daemon so the login callback port is not stolen by a headless service on fresh setups.
  - **Transmission:** BitTorrent daemon with `tremc` TUI frontend.
  - **Mailspring:** Email client; credentials stored via GNOME Keyring (runs standalone, no GNOME shell required).
  - **Obsidian:** Note-taking application with Home Manager plugin management.
  - **PearPass:** Declarative wrapper for the PearPass P2P password manager AppImage.
  - **Brave + Vimium C:** Declarative browser setup with preseeded extension settings and portable keymaps.
- **Vesktop:** Discord client with declarative translucency and wallpaper-aware theming.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim (via nixvim), plus Clang build essentials. Neovim is also registered as the default text editor via an `nvim-text` desktop entry.
- **AI Integrated:** Built-in configuration for **GitHub Copilot CLI** with per-repo `AGENTS.md` instructions plus curated skills for visualization, browser automation, static analysis, frontend design, and concise response modes. Global Copilot instructions live at `~/.copilot/copilot-instructions.md`.
- **Modular Architecture:** Configuration split across `hosts/` (system-level) and `modules/home/` (user-level) for maintainability.
- **Voiden:** Declarative AppImage wrapper for the Voiden offline-first API client.
- **Binary Caches:** Configured for `hyprland.cachix.org`, `nix-community.cachix.org`, and `ghostty.cachix.org`.

## Flake Inputs

Packages tracked independently of nixpkgs for tighter version control:

| Input | Source | Why |
|-------|--------|-----|
| `hyprland` | `github:hyprwm/Hyprland` | nixpkgs lags behind Hyprland releases; required for hyprglass plugin API compatibility |
| `ghostty` | `github:ghostty-org/ghostty` | Stays on latest release; uses `ghostty.cachix.org` for fast installs |
| `home-manager` | `github:nix-community/home-manager` | Tracks nixpkgs-unstable |
| `nixvim` | `github:nix-community/nixvim` | Full Neovim config in Nix |
| `spotify-player` | `github:aome510/spotify-player` | Picks up latest client fixes before nixpkgs |
| `skwd-wall` | `github:liixini/skwd-wall` | Quickshell wallpaper selector with built-in matugen, Wallhaven, Steam Workshop, and color sorting |
| `pearpass-app-desktop` | `github:tetherto/pearpass-app-desktop` | PearPass AppImage source for NixOS wrapper |
| `visual-explainer` | `github:nicobailon/visual-explainer` | HTML visualization generator for architecture diagrams and code explanations |
| `impeccable` | `github:pbakaus/impeccable` | Frontend design skill with 20 commands for typography, color, layout, and motion |
| `caveman` | `github:JuliusBrussee/caveman` | Copilot skill suite for concise low-token responses plus terse commit/review helpers |
| `trailofbits-skills` | `github:trailofbits/skills` | Security and analysis skill marketplace used here as the upstream source for the compact `static-analysis` Copilot skill |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **Glassmorphism Aesthetics:** Ghostty uses `background-opacity = 0.40` (native RGBA) so the terminal background is near-transparent while text stays fully opaque, giving a liquid-glass terminal. GTK4 popover styling also softens the Ghostty context menu with a lighter outer border and more translucency. The hyprglass Hyprland plugin is active for blur/tint/refraction effects on transparent surfaces.
- **Dynamic Theming:** Wallpaper-driven Matugen theming via [skwd-wall](https://github.com/liixini/skwd-wall) keeps Hyprland, Zathura, Vesktop, and DMS visually in sync. skwd-wall's built-in matugen generates Material Design 3 color tokens on each wallpaper change, and the current wallpaper cache is reused to keep DMS and the greeter aligned during switches.
- **skwd-wall State:** `skwd-wall` UI settings write to `~/.config/skwd-wall/config.json`, but each Home Manager activation resets that file back to the declarative defaults from Nix. Local API keys can live outside git in `~/.config/skwd-wall/secrets.env`.
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions; `Escape` exits any mode back to Normal and is unbound in Normal mode so it passes through to terminal apps (Vim, Copilot CLI, etc.).
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts.
- **Window Controls:** Super-based Hyprland keybindings cover moving, resizing, monitor focus, and monitor-to-monitor window moves.
- **Hard Quit:** `Super+Shift+X` force-terminates the active app process for clients like Vesktop or ProtonVPN that minimize to tray on normal close.
- **Launcher Shortcuts:** Common launch actions cover Yazi, wallpapers, screenshots, and the DMS notepad.
- **DMS Shell:** Core shell layout, widget placement, and launcher behavior are managed declaratively in Nix.
- **Screenshots:** `dms screenshot` handles region/window/full capture with image-to-clipboard. `screenshot-path-copy` wraps it to copy the file path instead (useful for sharing with AI agents).
- **Screen Recording:** `gsr-record` wraps GPU Screen Recorder for region, active-window, and focused-monitor capture, saving clips to `~/videos/screencasts`.
- **GitHub Copilot CLI:** Copilot is integrated into the Neovim + terminal workflow with repository-specific instructions.
- **Browser Automation:** PinchTab is installed declaratively so the Copilot browser-automation skill has the CLI it documents.
- **Static Analysis:** CodeQL, Semgrep, and SARIF tooling are installed declaratively to back the compact `static-analysis` Copilot skill.
- **DNS:** Quad9 (`9.9.9.9`) for privacy-focused DNS resolution.
- **XDG directories:** Lowercase paths such as `~/downloads`, `~/pictures`, and `~/wallpapers` are canonical. Legacy uppercase XDG folders are migrated into the lowercase layout when it is safe to do so, and Yazi assigns the expected special-folder icons to those lowercase names.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `zellij-sessionizer` | Zellij sessionizer — fuzzy-find a project and attach or create a dev session with Neovim and Copilot workflow tabs (`zs` is the short alias) |
| `screenshot-path-copy` | Wraps `dms screenshot` to copy the saved file path to clipboard (instead of image) |
| `hypr-nav` | Hyprland focus movement with workspace wrapping at boundaries |
| `hypr-quit-active` | Force-quits the active app process when a client minimizes to tray instead of exiting |
| `gsr-record` | Toggles GPU Screen Recorder for region, focused monitor, or active-window capture and saves clips under `~/videos/screencasts` |
| `transmission-port-sync` | Syncs Transmission's configured peer port (for example after a VPN-forwarded port change) |
| `copilot-sessions-sync` | Syncs `~/.copilot/session-state/` between desktop and USB (`to-usb` / `from-usb`) |
| `specify` | Spec Kit CLI wrapper — scaffolds spec-driven development for new projects |
| `setup-persistent-usb` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `update-usb` | Updates the USB image using prebuild mode by default, with `--in-place` as a lower-disk-space fallback |

## Usage

### Rebuild Desktop

```bash
sudo nixos-rebuild switch --flake .#desktop
```

### Dry Run (validate config without applying)

```bash
nixos-rebuild dry-build --flake .#desktop
```

### Flake Check (both host builds)

```bash
nix flake check
```

In this repo, `nix flake check` runs the checks defined in `flake.nix`: `desktop`, `usb`, `script-smoke`, and `shellcheck`. GitHub Actions keeps those host and script checks in separate jobs so CI failures stay isolated, while deployment remains manual via `nixos-rebuild switch --flake .#desktop` or `update-usb`.

### Update USB Drive

```bash
sudo update-usb /path/to/system-manifest/main
```

`update-usb` defaults to `--mode prebuild`, which builds locally and syncs the final squashfs image to the USB.

It now prints the source `configurationRevision`, resolves the installed `/nix/var/nix/profiles/system` target, and verifies that the final `nix-store.squashfs` on the USB actually contains that exact system path.

Always pass the worktree path that contains `flake.nix`, not the repo container root.

```bash
sudo update-usb --mode prebuild /path/to/system-manifest/<worktree>
```

Use `--in-place` when local disk space is tight:

```bash
sudo update-usb --in-place /path/to/system-manifest/<worktree>
```

The script handles preflight checks, safe cleanup on `Ctrl+C`, first-boot Home Manager activation, and post-install revision verification. After booting the USB, confirm the running image with `nixos-version --json` and `readlink -f /run/current-system`.

`update-usb` and `nix flake check` prove the image builds correctly, but USB-only runtime issues still require a real boot on target hardware to verify rendering, cursor, DMS, and similar session behavior.

### Initialize / Reformat Persistent USB

```bash
sudo setup-persistent-usb /dev/sdX
```

`setup-persistent-usb` takes an explicit target disk path (for safety). It wipes the disk, creates `NIXOS_BOOT` + `NIXOS_USB_CRYPT` partitions, initializes LUKS, and formats the encrypted root as ext4.

### Switch to Gaming Mode

Select **"NixOS - desktop-gaming-box"** from the bootloader menu (GRUB).

### Sync Copilot Sessions (Desktop ↔ USB)

```bash
copilot-sessions-sync to-usb    # before leaving for a lab machine
copilot-sessions-sync from-usb  # after returning
```

The script syncs the invoking user's `~/.copilot/session-state/` and escalates with `sudo` only for the USB mount/unlock steps.

## License

This repository is licensed under **GNU GPL v3.0**. See [LICENSE](./LICENSE).
