# NixOS System Manifest

My personal NixOS configuration — a declarative, reproducible system built around Hyprland with glassmorphism aesthetics, dual Greek/English keyboard support, and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) as the desktop shell.

Managed via **Nix Flakes** and **Home Manager**.

## License

This repository is licensed under **GNU GPL v3.0**. See `LICENSE`.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop` and `usb` (live/portable system).
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics powered by the [hyprglass](https://github.com/hyprnux/hyprglass) blur/vibrancy plugin (`light` theme, `default` preset), patched locally for current Hyprland API compatibility. Ghostty uses native `background-opacity` for true liquid-glass (background transparent, text fully opaque).
- **USB: Dual Session** — USB host boots with GDM offering **Hyprland** as the primary portable session plus **GNOME** as a fallback. Uses a **hybrid squashfs** Nix store (compressed read-only image + tmpfs overlay) for near-ISO boot performance on lab machines.
- **Gaming Mode:** A dedicated specialisation (`gaming-box`) that boots directly into Steam Big Picture Mode with Gamescope.
- **Media & Productivity:**
  - **Spotify Player:** Terminal-based Spotify client (`spotify_player`) with streaming support.
  - **Transmission:** BitTorrent daemon with `tremc` TUI frontend.
  - **Mailspring:** Email client; credentials stored via GNOME Keyring (runs standalone, no GNOME shell required).
  - **Obsidian:** Note-taking application with Home Manager plugin management.
  - **PearPass:** Declarative wrapper for the PearPass P2P password manager AppImage.
  - **Brave + Vimium C:** Declarative extension install with profile preference patching (Rewards button, right vertical tabs, `Ctrl+\` tabbar toggle, hidden close `x`, sidebar/new-tab toggles) plus Vimium C state seeding for portable keymaps/options. Vimium snapshots live in `modules/home/brave/vimium-c/{local-settings,sync-settings}` and are applied via Home Manager activation when Brave is not running.
- **Vesktop:** Discord client with declarative `Translucence + Matugen` theming: generates a canonical `Translucence.theme.css` from DMS' cached Matugen palette, atomically replaces it to reduce live wallpaper-change flicker, uses the Dracula Discord icon for the Vesktop launcher, removes the stock image background, and uses stronger blur/readability tuning over true desktop transparency.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, and Neovim (via nixvim), plus Clang build essentials (`clang` + `gnumake`). Neovim uses the Dracula colorscheme with a transparent background (matches Ghostty glass). Also registered as the default text editor via an `nvim-text` XDG desktop entry (opens in Ghostty).
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
- **Dynamic Theming:** Matugen-powered Hyprland border colours, GTK4 colours, and video wallpapers via **linux-wallpaperengine** synced via a custom `wallpaper-hook` daemon. WE live captures now drive both DMS wallpaper state and full palette refresh so Settings / shell theming stay in sync, while selector thumbnails treat tiny preview assets as low-confidence and prefer better renders when available. GTK uses the **Dracula** theme, `Papirus-Dark` comes from the full Papirus icon theme so DMS can resolve real app icons without breaking Papirus' shared symlinks, and Ghostty uses the built-in **Dracula** colour scheme.
- **Brave transparency note:** Chromium/Brave does not support the same reliable transparent-shell/opaque-content model used by Vesktop in this setup, so Brave remains opaque for readability and stability.
- **Cursor:** Adwaita (system default).
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions; `Escape` exits any mode back to Normal and is unbound in Normal mode so it passes through to terminal apps (Vim, Copilot CLI, etc.).
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts.
- **Window Controls:** `Super` + left-drag moves windows, `Super` + right-drag resizes. `Super+Ctrl+H/L` resizes horizontally, `Super+Ctrl+K/J` grows or shrinks the active window in fine steps, and `Super+Ctrl+Up/Down` do the same in larger steps. `Super+Arrows` changes focus between monitors, while `Super+Shift+Arrows` moves the active window between monitors.
- **Launcher Shortcuts:** `Super+E` opens **Yazi** in Ghostty.
- **DMS declarative shell settings:** Live bar layout is mirrored from saved DMS settings, display config format is set to **Model** with snap enabled, DMS widgets use the **Colorful** style, OSD/toasts/notepad are pinned to the BenQ with fallback routing, popup/notepad/system-monitor opacity is set to `0.70`, occupied-only workspaces and OSD toggles are declared in Nix, the launcher uses the larger NixOS logo with a `2px` border while hiding DMS Settings/Notepad from normal launcher results, and DMS restarts reapply the cached wallpaper to avoid falling back to the stock background.
- **DMS updater policy on NixOS:** The built-in updater is intentionally left unmanaged declaratively because upstream updater helpers target Arch/Fedora package managers, not the NixOS rebuild workflow.
- **Notepad shortcut:** `Super+T` toggles the DMS notepad slideout.
- **Launcher behavior notes:** The built-in System Monitor entry stays available, Settings search stays behind the `?` trigger, and DMS Settings/Notepad stay out of the normal launcher list. `launchPrefix` (when set in DMS launcher settings) prepends a command to app launches, e.g. wrappers like `uwsm-app` or `systemd-run --user`.
- **Wallpaper Selector Rollout:** `Super+W` toggles the flake-packaged selector open/close; `Super+Shift+W` opens the DMS wallpaper dash fallback.
- **Wallpaper selector content policy:** Mature/Questionable items are always filtered out and the `:sus` toggle is removed.
- **Screenshots:** `dms screenshot` handles region/window/full capture with image-to-clipboard. `screenshot-path-copy` wraps it to copy the file path instead (useful for sharing with AI agents). Screen recording via **Kooha** GUI.
- **GitHub Copilot CLI:** `Ctrl+Y` opens Neovim. `gh copilot` launched from the Zellij `copilot` tab.
- **DNS:** Quad9 (`9.9.9.9`) for privacy-focused DNS resolution.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `zs` | Zellij sessionizer — fuzzy-find project in `~/repositories`, attach or create session with 80/20 Neovim/terminal layout |
| `screenshot-path-copy` | Wraps `dms screenshot` to copy the saved file path to clipboard (instead of image) |
| `wallpaper-hook` | Daemon: picks wallpaper via linux-wallpaperengine, extracts palette via Matugen, reloads Hyprland border and GTK4 colours |
| `wallpaper-selector` | Toggle wallpaper selector UI (`open` can force-open for scripts) |
| `wallpaper-apply` | Internal apply entrypoint used by selector/playlist scripts (`static` or `dynamic`) |
| `wallpaper-engine-sync` | Syncs Wallpaper Engine wallpapers into `~/wallpapers/wallpaper-engine` and updates selector assets |
| `wallpaper-library-sync` | Syncs a wallpapers Git repo rooted at `~/wallpapers` and ensures `wallpaper-engine/` is ignored |
| `hypr-nav` | Hyprland focus movement with workspace wrapping at boundaries |
| `transmission-port-sync` | Updates transmission-daemon listening port |
| `copilot-sessions-sync` | Syncs `~/.copilot/session-state/` between desktop and USB (`to-usb` / `from-usb`) |
| `specify` | Spec Kit CLI wrapper — scaffolds spec-driven development for new projects |
| `setup-persistent-usb` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `update-usb` | Builds the `usb` flake output from a checkout path, installs it onto the USB, then creates a squashfs image of the Nix store |

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
sudo update-usb /path/to/system-manifest/checkouts/main
```

The script performs preflight checks (root, partition labels, mountpoint safety, and required tools), auto-enters `nix-shell` when `mksquashfs` is missing, activates the target Home Manager profile so first boot uses the declarative user config immediately, and accepts an optional flake directory path:

```bash
sudo update-usb /path/to/system-manifest/checkouts/<worktree>
```

After `nixos-install`, it activates the target Home Manager generation and then compresses `/nix/store` into a squashfs image. At boot, the USB mounts this compressed image via overlayfs — reads are sequential and fast (like an ISO), while writes go to a 2 GB tmpfs (volatile, reset on reboot). The encrypted root and home directories remain persistent, so user state such as GNOME Keyring data survives reboots on the same USB.

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
