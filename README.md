# NixOS System Manifest

My personal NixOS configuration — a declarative, reproducible system built around Hyprland with glassmorphism aesthetics, dual Greek/English keyboard support, and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) as the desktop shell.

Managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop` and `usb` (live/portable system).
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics powered by the [hyprglass](https://github.com/hyprnux/hyprglass) blur/vibrancy plugin (`light` theme, `default` preset), patched locally for current Hyprland API compatibility. Ghostty uses native `background-opacity` for true liquid-glass (background transparent, text fully opaque).
- **USB: Dual Session** — USB host boots with GDM offering **Hyprland** as the primary portable session plus **GNOME** as a fallback. That fallback stays intentionally minimal so Hyprland launchers do not inherit the stock GNOME app bundle. Uses a **hybrid squashfs** Nix store (compressed read-only image + tmpfs overlay) for near-ISO boot performance on lab machines, and routes Docker's heavy writable state to ephemeral host-local scratch storage when available, falling back to tmpfs when no suitable host partition can be mounted.
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
- **AI Integrated:** Built-in configuration for **GitHub Copilot CLI** with per-repo `AGENTS.md` instructions. Global Copilot instructions live at `~/.copilot/copilot-instructions.md`.
- **Greeter Avatar:** AccountsService user metadata + declarative avatar asset provisioning for consistent DMS greeter profile image rendering.
- **Modular Architecture:** Configuration split across `hosts/` (system-level) and `modules/home/` (user-level) for maintainability.
- **Voiden:** Declarative AppImage wrapper for the Voiden offline-first API client.
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
| `wallpaper-selector` | `github:skamprogiannis/wallpaper-selector` | Forked Quickshell wallpaper selector source, wrapped declaratively in Home Manager |
| `pearpass-app-desktop` | `github:tetherto/pearpass-app-desktop` | PearPass AppImage source for NixOS wrapper |
| `voiden` | `https://voiden.md/api/download/stable/linux/x64/Voiden-1.3.1.AppImage` | Offline-first API client packaged as AppImage wrapper |
| `visual-explainer` | `github:nicobailon/visual-explainer` | HTML visualization generator for architecture diagrams and code explanations |
| `impeccable` | `github:pbakaus/impeccable` | Frontend design skill with 20 commands for typography, color, layout, and motion |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **Glassmorphism Aesthetics:** Ghostty uses `background-opacity = 0.40` (native RGBA) so the terminal background is near-transparent while text stays fully opaque, giving a liquid-glass terminal. GTK4 popover styling also softens the Ghostty context menu with a lighter outer border and more translucency. The hyprglass Hyprland plugin is active for blur/tint/refraction effects on transparent surfaces.
- **Dynamic Theming:** Wallpaper-driven Matugen theming keeps Hyprland, GTK, and supported apps visually in sync across desktop and USB profiles.
- **Brave transparency note:** Chromium/Brave does not support the same reliable transparent-shell/opaque-content model used by Vesktop in this setup, so Brave remains opaque for readability and stability.
- **Cursor:** Adwaita (system default).
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions; `Escape` exits any mode back to Normal and is unbound in Normal mode so it passes through to terminal apps (Vim, Copilot CLI, etc.).
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts.
- **Window Controls:** Super-based Hyprland keybindings cover moving, resizing, monitor focus, and monitor-to-monitor window moves.
- **Hard Quit:** `Super+Shift+X` force-terminates the active app process for clients like Vesktop or ProtonVPN that minimize to tray on normal close.
- **Launcher Shortcuts:** Common launch actions cover Yazi, wallpapers, screenshots, and the DMS notepad.
- **DMS Shell:** Core shell layout, widget placement, and launcher behavior are managed declaratively in Nix.
- **Screenshots:** `dms screenshot` handles region/window/full capture with image-to-clipboard. `screenshot-path-copy` wraps it to copy the file path instead (useful for sharing with AI agents). Screen recording via **Kooha** GUI.
- **GitHub Copilot CLI:** Copilot is integrated into the Neovim + terminal workflow with repository-specific instructions.
- **Browser Automation:** PinchTab is installed declaratively so the Copilot browser-automation skill has the CLI it documents.
- **DNS:** Quad9 (`9.9.9.9`) for privacy-focused DNS resolution.
- **XDG directories:** Lowercase paths such as `~/downloads`, `~/pictures`, and `~/wallpapers` are canonical. Legacy uppercase XDG folders are migrated into the lowercase layout when it is safe to do so, and Yazi assigns the expected special-folder icons to those lowercase names.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `zs` | Zellij sessionizer — fuzzy-find a project and attach or create a dev session with Neovim, shell, and Copilot workflow tabs |
| `screenshot-path-copy` | Wraps `dms screenshot` to copy the saved file path to clipboard (instead of image) |
| `wallpaper-hook` | Daemon: picks wallpaper via linux-wallpaperengine, extracts palette via Matugen, reloads Hyprland border and GTK4 colours |
| `wallpaper-selector` | Toggle wallpaper selector UI (`open` can force-open for scripts) |
| `wallpaper-apply` | Internal apply entrypoint used by selector/playlist scripts (`static` or `dynamic`) |
| `wallpaper-engine-sync` | Syncs Wallpaper Engine wallpapers into `~/wallpapers/wallpaper-engine` and updates selector assets |
| `wallpaper-library-sync` | Clones/fetches/resets the static wallpapers repo rooted at `~/wallpapers` and keeps generated `.wallpaper-engine/` assets ignored |
| `hypr-nav` | Hyprland focus movement with workspace wrapping at boundaries |
| `hypr-quit-active` | Force-quits the active app process when a client minimizes to tray instead of exiting |
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

This is the standard `nix flake check` command. In this repo it runs the checks defined in `flake.nix`: both `desktop` and `usb` system builds, plus lightweight `script-smoke` coverage and a `shellcheck` pass over the generated custom shell entrypoints. GitHub Actions runs those host and script checks in separate jobs so failures stay isolated in CI. `nix fmt` uses Alejandra through the flake formatter output.

Validation is automated, but deployment is still manual: `nixos-rebuild switch --flake .#desktop` applies the desktop system, while `update-usb` rebuilds and syncs the USB image.

### Update USB Drive

```bash
sudo update-usb /path/to/system-manifest/checkouts/main
```

`update-usb` defaults to `--mode prebuild`, which builds locally and syncs the final squashfs image to the USB.

```bash
sudo update-usb --mode prebuild /path/to/system-manifest/checkouts/<worktree>
```

Use `--in-place` when local disk space is tight:

```bash
sudo update-usb --in-place /path/to/system-manifest/checkouts/<worktree>
```

The script handles preflight checks, safe cleanup on `Ctrl+C`, and first-boot Home Manager activation.

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
