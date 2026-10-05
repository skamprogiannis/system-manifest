# NixOS System Manifest

My personal NixOS configuration — a declarative, reproducible system built around Hyprland with glassmorphism aesthetics, dual Greek/English keyboard support, and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) as the desktop shell.

Managed via **Nix Flakes** and **Home Manager**.

## Features

- **Multi-Host Configuration:** Shared common configuration with host-specific overrides for `desktop`, `usb` (live/portable system), and `laptop` (dual-boot/mobile workstation). `hostType` is intentionally kept to lightweight shared-module branches; host-owned runtime/session behavior stays in dedicated host modules.
- **Hyprland Desktop:** Wayland tiling compositor with glassmorphism aesthetics powered by Hyprland's native blur and app-native transparency. Ghostty uses native `background-opacity` for glass-like terminal surfaces with fully opaque text.
- **USB: Portable Hyprland** — USB host boots through the same DMS greeter path as desktop and keeps the portable Hyprland session lean for lab machines. It includes declarative Steam, Gamemode, and portable Mesa graphics support. By default it uses a **hybrid squashfs** Nix store mounted by NixOS fileSystems (compressed read-only image + tmpfs overlay) for near-ISO boot performance on slow USB media; only new `/nix/store` writes use the tmpfs upper layer, while `/home` stays on the persistent encrypted USB root filesystem. Manual `ram-store` and `host-auto-store` boot specialisations use small initrd preparation units before the same native mount path to move store pressure into host RAM or an automatically selected host partition. Host-auto routes the copied store image, writable store overlay, Docker state, local cache, Codex state, Brave profile, the Steam library, and scratch `repositories` directory through encrypted host-local scratch when available.
- **Laptop: Dual-Boot Hyprland** — Laptop host keeps the full desktop muscle-memory workflow with portable display detection, encrypted-root install labels, Caps-to-Escape, Greek/US layouts, Zellij, Neovim, Codex, and browser setup.
- **Gaming Tools:** Steam and GameMode are available in the normal desktop, with Gamescope installed for opt-in per-game scaling, frame limiting, and compatibility workarounds.
- **Desktop local dictation:** Hold `Super+T` to record English speech and release to copy its local Whisper transcription to the clipboard. Notes uses `Super+N`; alerts use `Super+A`. The desktop-only service runs on demand and removes its transient recording state when it stops.
- **Media & Productivity:**
  - **Spotify GUI:** The current Nixpkgs Spotify client is styled with Spicetify and the Hazy translucent theme.
  - **Spotify Player:** Terminal-based Spotify client (`spotify_player`) with streaming support. The wrapper authenticates interactively before bootstrapping the background daemon so the login callback port is not stolen by a headless service on fresh setups, it does one safe re-auth pass when Spotify later rejects a cached refresh token, and it can read a personal Spotify app client ID from `~/.config/spotify-player/client_id` so Web API auth does not depend on a shared client ID when Spotify rate-limits it.
  - **Transmission:** Local BitTorrent daemon with a browser-app Web UI and a keyboard-friendly `torrent` helper.
  - **Mailspring:** Email client; credentials stored via GNOME Keyring (runs standalone, no GNOME shell required).
  - **Obsidian:** Note-taking application with Home Manager plugin management.
  - **PearPass:** Declarative wrapper for the PearPass P2P password manager AppImage.
  - **Brave + Vimium C:** Declarative browser setup with preseeded extension settings and portable keymaps.
- **Vesktop:** Discord client with declarative Translucence theming and QuickCSS customization.
- **Dev Ready:** Pre-configured environment for Node.js, Python, Go, Playwright, and Neovim (via nixvim), plus Clang build essentials. Neovim is also registered as the default text editor via an `nvim-text` desktop entry. Its LSP hover uses [md-render.nvim](https://github.com/delphinus/md-render.nvim) for compact Markdown and navigable links.
- **AI Integrated:** Built-in configuration for **Codex CLI** with per-repo `AGENTS.md` instructions, global defaults in `~/.codex/AGENTS.md`, custom agents in `~/.codex/agents`, Linear/Context7/Etsy/OpenAI Docs MCP servers, and curated skills for visualization, browser automation, security analysis, frontend work, review, diagnosis, TDD, design, prototyping, and concise response modes. Opt-in direct Cloudflare Clef integration adds dynamic model/effort selection, bounded native hooks, conservative approval triage, and metadata-only evaluation logs.
  Linear MCP auth is local per machine; after first enabling a host, run `codex mcp login linear` once if Codex reports that Linear is not logged in. Context7 uses a local API key from `~/.config/context7/api-key` when present.
- **Modular Architecture:** Configuration split across `hosts/` (system-level) and `modules/home/` (user-level) for maintainability.
- **Voiden:** Declarative AppImage wrapper for the Voiden offline-first API client.
- **Binary Caches:** Configured for `hyprland.cachix.org`, `nix-community.cachix.org`, and `ghostty.cachix.org`.

## Flake Inputs

Hyprland and its portal use Nixpkgs packages. Treesitter uses the editor Nixpkgs package and its matching grammars. These inputs remain independently tracked for configuration modules, upstream features, or release-matched resources:

| Input | Source | Why |
|-------|--------|-----|
| `catppuccin` | `github:catppuccin/nix` | Shared static Mocha palette for supported Home Manager applications |
| `ghostty` | `github:ghostty-org/ghostty` | Tracks upstream development for terminal features; keeps its own Nixpkgs revision for `ghostty.cachix.org` cache compatibility |
| `home-manager` | `github:nix-community/home-manager` | Tracks nixpkgs-unstable |
| `neovim-nixpkgs` | `github:nixos/nixpkgs/nixos-unstable` | Editor and plugin packages can be refreshed independently of desktop packages |
| `nixvim` | `github:nix-community/nixvim` | Full Neovim config in Nix |
| `spicetify-nix` | `github:Gerg-L/spicetify-nix` | Declarative Spicetify wrapper for the themed Spotify GUI |
| `skwd-wall` | `github:liixini/skwd-wall/nix` | skwd-wall v2 wallpaper selector/engine, daemon, and semantic model suite |
| `visual-explainer` | `github:nicobailon/visual-explainer` | HTML visualization generator for architecture diagrams and code explanations |
| `impeccable` | `github:pbakaus/impeccable` | Frontend design skill bundle with its matching engine packaged for offline typography, color, layout, and motion tools |
| `caveman` | `github:JuliusBrussee/caveman` | Skill suite for concise low-token responses plus terse commit/review helpers |
| `mattpocock-skills` | `github:mattpocock/skills` | Engineering skills used here for diagnosis, grilling, domain and module design, review, TDD, and prototyping |
| `trailofbits-skills` | `github:trailofbits/skills` | Security and analysis skill marketplace used here as the upstream source for the compact `static-analysis` skill |
| `pinchtab-src` | `github:pinchtab/pinchtab` | Release-matched PinchTab skill and safety references for browser automation |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **Glassmorphism Aesthetics:** Vesktop is the visual reference for glass surfaces: transparent enough to carry wallpaper context, but dark enough to keep text readable. The shared glass contract lives in `modules/home/glass.nix` and is documented in `DESIGN.md`. Ghostty uses native RGBA transparency with `background-opacity = 0.40`, applies it to colored cells, and keeps compositor opacity at `1.0` so text remains fully opaque. Hyprland uses a restrained native blur profile for Ghostty, Vesktop, DMS layers, and Hazy/Spicetify surfaces instead of heavy global blur.
- **Theming:** `modules/home/catppuccin.nix` centralizes the static Mocha palette for Brave, Bat, Ghostty, Zellij, Nixvim, and GTK 3. skwd-wall v2 owns wallpaper-derived colours. DMS consumes its palette and application templates render from those supplied colours. Vesktop regenerates Translucence/QuickCSS from DMS `dms-colors.json`, and Hyprland updates window/group borders through a targeted Lua `hl.config(...)` evaluation.
- **Wallpaper Integration:** `Super+W` opens skwd-wall v2, backed by the `skwd-walld` user service. The `wallpaper-sync` service follows successful applications, synchronizes DMS session state, and saves a matching wallpaper/palette snapshot for the greeter. Temporary picker previews affect desktop colours; the greeter follows the last applied snapshot. With different wallpapers across monitors, the latest applied wallpaper determines shared colours and the greeter image. Use `wallpaper-sync status --json` to inspect synchronization and pending errors.
- **Zellij Navigation:** `Alt`-based keybindings for all multiplexer actions with Zellij's simplified non-powerline UI; `Escape` exits any mode back to Normal and is unbound in Normal mode so it passes through to terminal apps (Vim, Codex CLI, etc.).
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts, and IBus is started with the Hyprland session for Greek dead-key composition.
- **Window Controls:** Super-based Hyprland keybindings cover moving, resizing, grouped-window tabs, monitor focus, and monitor-to-monitor window moves.
- **Hard Quit:** `Super+Shift+X` force-terminates the active app process for clients like Vesktop or ProtonVPN that minimize to tray on normal close.
- **Launcher Shortcuts:** Common launch actions cover Yazi, wallpapers, screenshots, and the DMS notepad.
- **DMS Shell:** Core shell layout, widget placement, and launcher behavior are managed declaratively in Nix.
- **Screenshots:** Region/window/full keybinds use `dms screenshot` to save under `~/pictures/screenshots` and copy the image to the clipboard. `screenshot-path-copy` copies the file path instead (useful for sharing with AI agents).
- **Screen Recording:** GPU Screen Recorder's GTK UI handles capture setup, backed by GPU Screen Recorder. `gsr-record stop` is kept as an emergency stop helper for finalizing active clips under `~/videos/screencasts`.
- **Codex CLI:** Codex is integrated into the Neovim + terminal workflow with repository-specific instructions, `/goal` enabled, declarative skills, Linear/Context7/Etsy/OpenAI Docs MCP servers, custom agents, BEL-based terminal urgency, and a dedicated Zellij tab. Codex and the optional Bannerlord adapter share one version pin; upgrade checks cover daemon startup and adapter preflight. `codex-auto` enables direct Clef decision support without changing ordinary `codex` sessions; scoped runtime credentials remain outside Nix and repositories.
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
| `torrent` | Manages the local Transmission daemon with readable `gui`, `list`, `add`, `start`, `stop`, `remove`, and guarded `delete --yes` commands |
| `transmission-port-sync` | Syncs Transmission's configured peer port (for example after a VPN-forwarded port change) |
| `codex-auto` | Opt-in Clef launch-time model and effort routing with native decision-support hooks |
| `codex-clef` | Status, model catalog, metadata outcomes, and explicit typed/image evaluation |
| `codex-state-sync` | Safely merges active Codex sessions between desktop and USB (`to-usb` / `from-usb`) while leaving machine-local state alone |
| `nixos-usb-host-scratch-status` | Shows encrypted host-scratch mounts plus the last checkpoint/shutdown sync result |
| `specify` | Spec Kit CLI wrapper — scaffolds spec-driven development for new projects |
| `setup-persistent-usb` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `steam-host-scratch` | Reports host-auto Steam paths and checkpoints account/config/userdata state |
| `usb-host-scratch` | Opens the temporary repositories path, checkpoints persistent app state, or shows host-scratch status |
| `update-usb` | Updates the USB image using prebuild mode by default, with `--in-place` as a lower-disk-space fallback |

## Clef-assisted Codex

`codex-auto -- "task"` opts into direct Cloudflare Clef support. Clef selects a
model **and** reasoning effort from the authenticated Codex model catalog; explicit
model/profile/effort overrides win. Initial routing sets both ordinary and planning
effort, while subsequent main-thread TUI messages retain Codex's own settings.
Native hooks can independently route named subagents, recommend skills and checks,
flag repeated failure signals, and suggest one bounded completion review.

Bare startup and resume preserve their model/effort settings; main routing needs
a task prompt or explicitly approved brief. Assisted interactive sessions run
independently of the shared daemon, so plain `codex` keeps its hooks inactive.
Approval recommendations start in **shadow mode** and never automatically approve
native requests; optional enforcement applies only explicit installed denials.
Completion suggestions are advisory. Unknown, sensitive, privileged or destructive
requests remain with the user. Required tests and independent code review are not
replaced by model confidence.

Install a scoped Workers AI token locally, review the hooks through Codex's `/hooks`,
and use `codex-clef status` to check credentials, model-catalog state and log paths.
Automatic decisions upload only coarse task metadata. Raw task briefs, source,
verification evidence and screenshots require explicit upload consent.

Setup, command examples, privacy boundaries, evaluation and rollback are documented
in [the Clef module guide](modules/home/codex/CLEF.md). Runtime logs are not committed
or deleted during migration; the retired Jev pilot's absence of logs does not imply
that a routing evaluation has taken place.

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

`update-usb` builds the desired system in the host Nix store, then prepares an independent USB store on the desktop SSD. The previous USB squashfs stays compressed and read-only; a private OverlayFS directory holds added packages and deletions. Host store files are never hard-linked into staging. The final USB image remains one complete squashfs with the current and previous generations.

Staging defaults to `/var/tmp/update-usb-stage`. To use another Linux drive with OverlayFS support:

```bash
sudo update-usb --stage-dir /mnt/ssd/update-usb-stage /path/to/system-manifest/main
```

The staging directory must be empty or marked as owned by this updater. `--in-place` instead expands and stages on the USB, saving host space at the cost of slower USB I/O. `--force` rewrites an otherwise current installation. Always pass a worktree containing `flake.nix`, not the repository container.

Output identifies the active phase, shows copied bytes and transfer rate, and gives elapsed-time heartbeats while flushing or verifying. Add `-v` for full command output. The latest ten JSON reports in `/var/log/update-usb/` record timings, image sizes, available USB space, and tool versions.

Installation uses private Nix metadata and defers activation and bootloader changes. The updater verifies both retained package closures, copies and checksums the complete replacement image, then publishes the image, Nix metadata, and boot configuration in that order. The USB needs temporary space for the previous image, replacement image, and pending metadata. A persistent transaction record lets the next invocation resume interrupted publication before checking whether an update is needed. Cancellation removes disposable staging but preserves a prepared transaction and completed boot data.

A lock serializes updates, and the updater recovers its own mounts under `/run/update-usb`. Image replacement and metadata exchange are atomic individually; publication across the USB root and EFI partition is not one atomic operation. Keep the USB connected until cleanup completes. These changes reduce staging space and improve recovery and diagnosis; they do not guarantee faster physical USB writes.

The workflow lives in `modules/home/scripts/usb/`. The `usb-update-integration` check uses small real Nix stores and EFI boots to exercise staging, garbage collection, interrupted publication, and rollback. Validation still requires a real update and boot on target hardware before claiming USB runtime behavior is working. After boot, inspect `nixos-version --json` and `readlink -f /run/current-system`.

### USB RAM Store Mode

Choose the USB **`ram-store` specialisation** from the bootloader when you want the system to copy `nix-store.squashfs` into RAM before NixOS mounts `/nix/store`.

That mode improves steady-state store reads after boot, uses an encrypted USB-root scratch directory for the writable overlay layer, and falls back to the USB-backed lower store if the host does not have enough free memory. After boot, run `nixos-usb-store-status` to confirm whether the lower store came from RAM or the USB image.

### USB Host Auto Store Mode

Choose the USB **`host-auto-store` specialisation** on lab machines where it is acceptable to use a writable host partition as temporary scratch storage. The USB scans non-removable Linux filesystems first (`ext2`, `ext3`, `ext4`, `xfs`, and `btrfs`), then tries `ntfs`/`ntfs3` and `exfat` as lower-priority fallbacks. A per-boot encrypted sparse image is created under `.nixos-usb/session/<boot-id>/` on the selected host filesystem, and only that encrypted image is used for the copied `nix-store.squashfs`, writable store overlay, Docker state, local cache, Codex state, Brave profile, Steam library, and temporary `repositories` directory.

After boot, check which path was used:

```bash
cat /run/nixos-usb-store-mode
nixos-usb-store-status
nixos-usb-host-scratch-status
```

`writable-encrypted-host-auto-overlay` means store reads and writes are backed by the encrypted host scratch image. If no suitable partition can be mounted or copied to, the specialisation falls back to the USB-backed squashfs and encrypted USB-root scratch writable layer. `nixos-usb-store-status` prints the selected store mode, host candidates, mount diagnostics, and relevant initrd service logs. `nixos-usb-host-scratch-status` shows Docker/cache/Codex/Brave/Steam bind mounts and the active repositories path.

To make essential Codex and Brave changes durable before shutdown:

```bash
usb-host-scratch checkpoint
usb-host-scratch checkpoint --include-cache
usb-host-scratch status
```

Checkpoints are serialized and update phase, scope, and result diagnostics shown by `status`. The default checkpoint persists essential Codex session state and Brave profile state while excluding volatile caches and USB-local Codex authentication/configuration. Add `--include-cache` for an explicit, potentially slow full `~/.cache` copy. Docker state, everything under the host-scratch `repositories` directory, and games installed in `~/games/SteamLibrary` remain intentionally temporary. Steam Cloud is the durability path for supported game saves; commit or push repository work before powering off.

Keep the USB connected until the computer has powered off. The console message `Reached target System Power Off` can appear before final filesystem and encrypted scratch cleanup finishes. If shutdown stops there, leave the USB attached while diagnosing it.

For fast temporary clones:

```bash
cd "$(usb-host-scratch)"
git clone https://github.com/OWNER/REPO.git
```

Steam is included with the USB's portable 32-bit graphics runtime and GameMode. When encrypted host scratch is active, launching Steam in `host-auto-store` automatically bootstraps its mutable client and default `steamapps` library on the host SSD. The existing `~/games/SteamLibrary` location remains available too. Inspect the client path with:

```bash
steam-host-scratch status
```

Both locations are temporary and erased at shutdown. Account configuration, Steam Guard sentry files, and userdata are imported from persistent USB home on first launch. After exiting Steam, save changes explicitly with:

```bash
steam-host-scratch checkpoint
```

Games and compatibility prefixes are not checkpointed. Wait for Steam Cloud to finish syncing supported saves before powering off; saves outside Steam userdata need their own backup. Normal USB boots and host-auto fallback retain Steam's persistent data-home behavior.

On clean shutdown, the USB first detaches live Docker and user-state bind mounts, then gives the essential Codex/Brave sync 50 seconds plus at most five seconds to terminate, leaving cleanup time inside systemd's hard 60-second stop budget. The two initrd-created host mounts bypass systemd's generic `umount.target`; the shutdown-ramfs hook owns their dependency-sensitive teardown so it can unmount scratch, close the mapper, and only then unmount the host backing filesystem without misleading failed-unmount messages. Cleanup still removes host-side encrypted session files after a sync failure or timeout. A forced power-off cannot guarantee the final sync; use `usb-host-scratch checkpoint` first when recent state matters. If power is cut, the host may retain ciphertext under `.nixos-usb/session/`, but the key only lived in RAM and stale session files are removed on the next successful host-auto boot.

### Initialize / Reformat Persistent USB

```bash
sudo setup-persistent-usb /dev/sdX
```

`setup-persistent-usb` takes an explicit target disk path (for safety). It wipes the disk, creates `NIXOS_BOOT` + `NIXOS_USB_CRYPT` partitions, initializes LUKS, and formats the encrypted root as ext4.

### Sync Codex State (Desktop <-> USB)

```bash
codex-state-sync to-usb    # before leaving for a lab machine
codex-state-sync from-usb  # after returning
```

The script merges only active rollout files under `~/.codex/sessions/`; it never deletes destination-only sessions, and it preserves a newer destination copy. Before replacing an older same-path rollout, it saves the old file under `~/.local/state/codex-state-sync/backups/`. When files change, it also backs up the destination state database and requests a rollout reindex for the next Codex launch.

Close Codex before running `from-usb`; the command refuses to import while a local Codex process is active. Auth, declarative config, databases, archived sessions, goals, memories, skills, agents, caches, and logs remain local to each machine.

## License

This repository is licensed under **GNU GPL v3.0**. See [LICENSE](./LICENSE).
