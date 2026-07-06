# NixOS System Manifest

My personal NixOS configuration — a declarative, reproducible system built around Hyprland with glassmorphism aesthetics, dual Greek/English keyboard support, and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) as the desktop shell.

Managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop`, `usb` (live/portable system), and `laptop` (dual-boot/mobile workstation). `hostType` is intentionally kept to lightweight shared-module branches; host-owned runtime/session behavior stays in dedicated host modules.
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics powered by Hyprland's native blur and app-native transparency. Ghostty uses native `background-opacity` for glass-like terminal surfaces with fully opaque text.
- **USB: Portable Hyprland** — USB host boots through the same DMS greeter path as desktop and keeps the portable Hyprland session lean for lab machines. By default it uses a **hybrid squashfs** Nix store mounted by NixOS fileSystems (compressed read-only image + tmpfs overlay) for near-ISO boot performance on slow USB media; only new `/nix/store` writes use the tmpfs upper layer, while `/home` stays on the persistent encrypted USB root filesystem. Manual `ram-store` and `host-auto-store` boot specialisations use small initrd preparation units before the same native mount path to move store pressure into host RAM or an automatically selected host partition. Host-auto routes the copied store image, writable store overlay, Docker state, local cache, Codex state, Brave profile, and scratch `repositories` directory through encrypted host-local scratch when available.
- **Laptop: Dual-Boot Hyprland** — Laptop host keeps the full desktop muscle-memory workflow with portable display detection, encrypted-root install labels, Caps-to-Escape, Greek/US layouts, Zellij, Neovim, Codex, and browser setup.
- **Gaming Mode:** A dedicated specialisation (`gaming-box`) that boots directly into Steam Big Picture Mode with Gamescope.
- **Media & Productivity:**
  - **Spotify GUI:** Official Spotify client wrapped with Spicetify and the Hazy translucent theme, with local glass polish.
  - **Spotify Player:** Terminal-based Spotify client (`spotify_player`) with streaming support. The wrapper authenticates interactively before bootstrapping the background daemon so the login callback port is not stolen by a headless service on fresh setups, it does one safe re-auth pass when Spotify later rejects a cached refresh token, and it can read a personal Spotify app client ID from `~/.config/spotify-player/client_id` so Web API auth does not depend on a shared client ID when Spotify rate-limits it.
  - **Transmission:** BitTorrent daemon with `tremc` TUI frontend.
  - **Mailspring:** Email client; credentials stored via GNOME Keyring (runs standalone, no GNOME shell required).
  - **Obsidian:** Note-taking application with Home Manager plugin management.
  - **PearPass:** Declarative wrapper for the PearPass P2P password manager AppImage.
  - **Brave + Vimium C:** Declarative browser setup with preseeded extension settings and portable keymaps.
- **Vesktop:** Discord client with declarative Translucence theming and a wallpaper-aware QuickCSS bridge.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, Playwright, and Neovim (via nixvim), plus Clang build essentials. Neovim is also registered as the default text editor via an `nvim-text` desktop entry.
- **AI Integrated:** Built-in configuration for **Codex CLI** with per-repo `AGENTS.md` instructions, global defaults in `~/.codex/AGENTS.md`, custom agents in `~/.codex/agents`, Linear/Context7/Etsy/OpenAI Docs MCP servers, and explicitly enabled curated skills in `~/.agents/skills` for visualization, browser automation, static analysis, frontend design, architecture review, diagnosis, TDD, issue triage, PRDs, prototyping, codebase zoom-out, and concise response modes.
  Linear MCP auth is local per machine; after first enabling a host, run `codex mcp login linear` once if Codex reports that Linear is not logged in. Context7 uses a local API key from `~/.config/context7/api-key` when present.
- **Modular Architecture:** Configuration split across `hosts/` (system-level) and `modules/home/` (user-level) for maintainability.
- **Voiden:** Declarative AppImage wrapper for the Voiden offline-first API client.
- **Binary Caches:** Configured for `hyprland.cachix.org`, `nix-community.cachix.org`, and `ghostty.cachix.org`.

## Flake Inputs

Packages tracked independently of nixpkgs for tighter version control:

| Input | Source | Why |
|-------|--------|-----|
| `hyprland` | `github:hyprwm/Hyprland` | nixpkgs lags behind Hyprland releases; tracked directly for current compositor blur, rules, and Lua-config behavior |
| `ghostty` | `github:ghostty-org/ghostty` | Stays on latest release; uses `ghostty.cachix.org` for fast installs |
| `home-manager` | `github:nix-community/home-manager` | Tracks nixpkgs-unstable |
| `nixvim` | `github:nix-community/nixvim` | Full Neovim config in Nix |
| `spicetify-nix` | `github:Gerg-L/spicetify-nix` | Declarative Spicetify wrapper for the themed Spotify GUI |
| `skwd-wall` | `github:liixini/skwd-wall` | Quickshell wallpaper selector with built-in matugen, Wallhaven, Steam Workshop, and color sorting |
| `pearpass-app-desktop` | `github:tetherto/pearpass-app-desktop` | PearPass AppImage source for NixOS wrapper |
| `visual-explainer` | `github:nicobailon/visual-explainer` | HTML visualization generator for architecture diagrams and code explanations |
| `impeccable` | `github:pbakaus/impeccable` | Frontend design skill bundle for typography, color, layout, and motion |
| `ui-ux-pro-max` | `github:nextlevelbuilder/ui-ux-pro-max-skill` | UI/UX design skill pack with companion skills for design systems, styling, branding, banners, and slides |
| `caveman` | `github:JuliusBrussee/caveman` | Skill suite for concise low-token responses plus terse commit/review helpers |
| `mattpocock-skills` | `github:mattpocock/skills` | Planning and engineering skill collection used here for diagnosis, docs-aware plan grilling, architecture improvement, TDD, issue triage, issue/PRD generation, prototyping, and codebase zoom-out |
| `trailofbits-skills` | `github:trailofbits/skills` | Security and analysis skill marketplace used here as the upstream source for the compact `static-analysis` skill |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **Glassmorphism Aesthetics:** Vesktop is the visual reference for glass surfaces: transparent enough to carry wallpaper context, but dark enough to keep text readable. The shared glass contract lives in `modules/home/glass.nix` and is documented in `DESIGN.md`. Ghostty uses native RGBA transparency with `background-opacity = 0.40`, applies it to colored cells, and keeps compositor opacity at `1.0` so text remains fully opaque. Hyprland uses a restrained native blur profile for Ghostty, Vesktop, DMS layers, and Hazy/Spicetify surfaces instead of heavy global blur.
- **Dynamic Theming:** Wallpaper-driven Matugen theming via [skwd-wall](https://github.com/liixini/skwd-wall) keeps Hyprland, Zathura, Vesktop, and DMS visually in sync. Vesktop consumes the generated palette through `Translucence.theme.css` plus `~/.config/vesktop/settings/quickCss.css`, Spotify uses a Spicetify Hazy theme with local glass polish from `modules/home/glass.nix`, and the current wallpaper cache is reused to keep DMS and the greeter aligned during switches. For Wallpaper Engine scenes with weak workshop previews, `skwd-we-capture-still --current-live` can save a faithful live still into the transition cache.
- **Wallpaper Integration:** `modules/home/wallpaper/` is the shared wallpaper entrypoint. `skwd-wall` owns wallpaper selection plus `~/.cache/skwd-wall/*`; `modules/home/dms/session-state.nix` owns the baseline `~/.local/state/DankMaterialShell/session.json`; and the sync hook in `modules/home/skwd-wall.nix` mirrors the selected wallpaper into DMS runtime state and the greeter cache. Hyprland stays a downstream consumer of that state.
- **skwd-wall State:** `skwd-wall` UI settings write to `~/.config/skwd-wall/config.json`, but each Home Manager activation resets that file back to the declarative defaults from Nix. Local API keys can live outside git in `~/.config/skwd-wall/secrets.env`.
- **Malformed JSON Policy:** Activation-owned JSON (`~/.config/skwd-wall/config.json`, `~/.local/state/DankMaterialShell/session.json`) is healed/reset to declarative defaults during activation. Runtime sync code fails closed before overwriting malformed authoritative targets, but only warns and continues for optional/cache-like inputs.
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions with Zellij's simplified non-powerline UI; `Escape` exits any mode back to Normal and is unbound in Normal mode so it passes through to terminal apps (Vim, Codex CLI, etc.).
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts, and IBus is started with the Hyprland session for Greek dead-key composition.
- **Window Controls:** Super-based Hyprland keybindings cover moving, resizing, monitor focus, and monitor-to-monitor window moves.
- **Hard Quit:** `Super+Shift+X` force-terminates the active app process for clients like Vesktop or ProtonVPN that minimize to tray on normal close.
- **Launcher Shortcuts:** Common launch actions cover Yazi, wallpapers, screenshots, and the DMS notepad.
- **DMS Shell:** Core shell layout, widget placement, and launcher behavior are managed declaratively in Nix.
- **Screenshots:** `dms screenshot` handles region/window/full capture with image-to-clipboard. `screenshot-path-copy` wraps it to copy the file path instead (useful for sharing with AI agents).
- **Screen Recording:** GPU Screen Recorder's GTK UI handles capture setup, backed by GPU Screen Recorder. `gsr-record stop` is kept as an emergency stop helper for finalizing active clips under `~/videos/screencasts`.
- **Codex CLI:** Codex is integrated into the Neovim + terminal workflow with repository-specific instructions, `/goal` enabled, explicit declarative skill enablement, Linear/Context7/Etsy/OpenAI Docs MCP servers, custom reviewer agents, BEL-based terminal urgency, and a dedicated Zellij tab.
- **Browser Automation:** PinchTab is installed declaratively so the browser-automation skill has the CLI it documents.
- **Static Analysis:** CodeQL, Semgrep, and SARIF tooling are installed declaratively to back the compact `static-analysis` skill.
- **DNS:** Quad9 (`9.9.9.9`) for privacy-focused DNS resolution.
- **XDG directories:** Lowercase paths such as `~/downloads`, `~/pictures`, and `~/wallpapers` are canonical. Legacy uppercase XDG folders are migrated into the lowercase layout when it is safe to do so, and Yazi assigns the expected special-folder icons to those lowercase names.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `zellij-sessionizer` | Zellij sessionizer — fuzzy-find a project and attach or create a dev session with Neovim and Codex workflow tabs (`zs` is the short alias) |
| `screenshot-path-copy` | Wraps `dms screenshot` to copy the saved file path to clipboard (instead of image) |
| `hypr-quit-active` | Force-quits the active app process when a client minimizes to tray instead of exiting |
| `gsr-record` | Emergency stop helper for active GPU Screen Recorder captures; `stop` finalizes recordings and clears stale runtime state |
| `skwd-we-capture-still` | Captures a Wallpaper Engine still image into `~/.cache/skwd-wall/wallpaper/we-captures/`, with `--current-live` for a faithful live-screen fallback |
| `transmission-port-sync` | Syncs Transmission's configured peer port (for example after a VPN-forwarded port change) |
| `codex-state-sync` | Syncs resumable Codex state between desktop and USB (`to-usb` / `from-usb`) while leaving auth/config/cache local |
| `nixos-usb-host-scratch-status` | Shows whether encrypted host scratch is active and which user/cache/Docker paths are bound to it |
| `specify` | Spec Kit CLI wrapper — scaffolds spec-driven development for new projects |
| `setup-persistent-usb` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `usb-host-scratch` | Prints the active encrypted host scratch `repositories` path for fast temporary clones |
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

### Rebuild Laptop

```bash
sudo nixos-rebuild switch --flake .#laptop
```

The laptop host is intended for a UEFI dual-boot install with Secure Boot disabled and an encrypted root. Its hardware config expects these install labels: `NIXOS_LAPTOP_BOOT` for the NixOS ESP, `NIXOS_LAPTOP_CRYPT` for the LUKS partition, and `NIXOS_LAPTOP_ROOT` for the ext4 filesystem inside LUKS.

### Flake Check (all host builds)

```bash
nix flake check
```

In this repo, `nix flake check` runs the host and support checks defined by the Check registry in `checks/registry.nix`. GitHub Actions keeps the same registry groups isolated, serializes full Nix builds to avoid upstream fetch throttling, and uses the configured Nix caches plus GitHub's Nix store cache. The default desktop check builds the CUDA-light `desktop-ci` output so routine CI does not compile the full Ollama CUDA closure; run the manual **Validate Full Desktop** workflow when the production CUDA desktop closure needs GitHub validation. Deployment remains manual via `nixos-rebuild switch --flake .#desktop`, `nixos-rebuild switch --flake .#laptop`, or `update-usb`.

For later shared-contract refactors, treat `nix flake check` plus `nixos-rebuild dry-build --flake .#desktop` as the minimum validation floor. Runtime wallpaper/DMS ownership changes still need a manual wallpaper-switch smoke test, and USB-only session changes still require `update-usb` plus a real boot on target hardware.

### Update USB Drive

```bash
sudo update-usb /path/to/system-manifest/main
```

`update-usb` defaults to `--mode prebuild`, which builds locally and syncs the final squashfs image to the USB. Always pass the worktree path that contains `flake.nix`, not the repo container root.

The USB installer workflow is packaged from `modules/home/scripts/usb/`: Nix owns constants and host exposure, while the extracted `update-usb` shell fragments own runtime behavior.

```bash
sudo update-usb --mode prebuild /path/to/system-manifest/<worktree>
```

Use `--in-place` when local disk space is tight:

```bash
sudo update-usb --in-place /path/to/system-manifest/<worktree>
```

The script handles preflight checks, safe cleanup on `Ctrl+C`, first-boot Home Manager activation, and revision verification. After booting the USB, confirm the running image with `nixos-version --json` and `readlink -f /run/current-system`.

`update-usb` and `nix flake check` prove the image builds correctly, but USB-only runtime issues still require a real boot on target hardware to verify rendering, cursor, DMS, and similar session behavior.

### USB RAM Store Mode

Choose the USB **`ram-store` specialisation** from the bootloader when you want the system to copy `nix-store.squashfs` into RAM before NixOS mounts `/nix/store`.

That mode improves steady-state store reads after boot, uses an encrypted USB-root scratch directory for the writable overlay layer, and falls back to the USB-backed lower store if the host does not have enough free memory. After boot, run `nixos-usb-store-status` to confirm whether the lower store came from RAM or the USB image.

### USB Host Auto Store Mode

Choose the USB **`host-auto-store` specialisation** on lab machines where it is acceptable to use a writable host partition as temporary scratch storage. The USB scans non-removable Linux filesystems first (`ext2`, `ext3`, `ext4`, `xfs`, and `btrfs`), then tries `ntfs`/`ntfs3` and `exfat` as lower-priority fallbacks. A per-boot encrypted sparse image is created under `.nixos-usb/session/<boot-id>/` on the selected host filesystem, and only that encrypted image is used for the copied `nix-store.squashfs`, writable store overlay, Docker state, local cache, Codex state, Brave profile, and temporary `repositories` directory.

After boot, check which path was used:

```bash
cat /run/nixos-usb-store-mode
nixos-usb-store-status
nixos-usb-host-scratch-status
```

`writable-encrypted-host-auto-overlay` means store reads and writes are backed by the encrypted host scratch image. If no suitable partition can be mounted or copied to, the specialisation falls back to the USB-backed squashfs and encrypted USB-root scratch writable layer. `nixos-usb-store-status` prints the selected store mode, host candidates, mount diagnostics, and relevant initrd service logs. `nixos-usb-host-scratch-status` shows Docker/cache/Codex/Brave bind mounts and the active repositories path.

For fast temporary clones:

```bash
cd "$(usb-host-scratch)"
git clone https://github.com/OWNER/REPO.git
```

On clean shutdown, the USB syncs `~/.cache`, `~/.codex`, and `~/.config/BraveSoftware` back to the USB root, then removes host-side encrypted session files. If power is cut, the host may retain ciphertext under `.nixos-usb/session/`, but the key only lived in RAM and stale session files are removed on the next successful host-auto boot.

### Initialize / Reformat Persistent USB

```bash
sudo setup-persistent-usb /dev/sdX
```

`setup-persistent-usb` takes an explicit target disk path (for safety). It wipes the disk, creates `NIXOS_BOOT` + `NIXOS_USB_CRYPT` partitions, initializes LUKS, and formats the encrypted root as ext4.

### Switch to Gaming Mode

Select **"NixOS - desktop-gaming-box"** from the bootloader menu (GRUB).

### Sync Codex State (Desktop <-> USB)

```bash
codex-state-sync to-usb    # before leaving for a lab machine
codex-state-sync from-usb  # after returning
```

The script syncs resumable Codex state from `~/.codex/` and escalates with `sudo` only for the USB mount/unlock steps. Auth, declarative config, skills, agents, caches, and logs remain local to each machine.

## License

This repository is licensed under **GNU GPL v3.0**. See [LICENSE](./LICENSE).
