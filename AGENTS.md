# Agents & Workflows

## Useful Commands

- **Dry Run Build:** `nixos-rebuild dry-build --flake .#nixos` (Checks for evaluation errors without applying changes)
- **Check Configuration:** `nixos-rebuild test --flake .#nixos` (Builds and activates, but doesn't add to bootloader - good for temporary testing)
- **Flake Check:** `nix flake check` (This is the standard Nix flake command. In this repo it runs the checks defined in `flake.nix`: `desktop`, `usb`, `script-smoke`, and `shellcheck`.)
- **List Generations:** `nixos-rebuild list-generations`
- **Garbage Collect:** `nix-collect-garbage -d` (Deletes old generations)

## Agent Tips

- **Session Info:** `/session` command.
- **Git & Gens:** Keep git commits atomic and descriptive.
- **Commit Format:** Use **Conventional Commits** (`type(scope): message`).
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  - Scopes: `desktop`, `laptop`, `usb`, `common`, `home`, `system`, or specific module names.
  - Example: `feat(desktop): enable steam and gamemode`
  - Example: `fix(usb): correct luks mounting path`
- **Worktree-First Git:** `/home/stefan/system-manifest` is the repo container; the bare Git dir lives at `/home/stefan/system-manifest/.bare`. Do not edit anything inside `.bare`.
  - Main worktree: `/home/stefan/system-manifest/main`
  - Create a feature worktree: `git --git-dir=/home/stefan/system-manifest/.bare worktree add /home/stefan/system-manifest/<dir> -b <branch> main`
  - Keep worktree directories as sanitized direct children (for example `usb-fix`), even when the branch name contains slashes such as `feature/usb-fix`
  - List active worktrees: `git --git-dir=/home/stefan/system-manifest/.bare worktree list`
  - Remove merged worktree: `git --git-dir=/home/stefan/system-manifest/.bare worktree remove /home/stefan/system-manifest/<dir>` and then `git --git-dir=/home/stefan/system-manifest/.bare branch -d <branch>`
  - Run all editing/build/git commands from the intended worktree path.
- **System Git:** Ensure `git` is always in `environment.systemPackages` in `configuration.nix` (required for Flakes).
- **Git Push:** Always `git push` (or force push if history was rewritten) immediately after creating a new commit.
- **Copilot Instruction Source:** Repository-wide Copilot defaults are edited in `modules/home/gh-copilot/instructions.md`, which is synced to `~/.copilot/copilot-instructions.md` via Home Manager when you run `nixos-rebuild switch`.
- **Squash Fix Chains:** If you need multiple attempts to fix something, squash them into a single commit before pushing (`git rebase -i` or `git commit --amend`). Avoid pushing fix→fix→fix chains that clutter history.

- **Git Hygiene:** Always commit before `nixos-rebuild switch` so `nixos-rebuild list-generations` records a clean configuration revision for rollback and history tracking.
- **README Updates:** Update `README.md` with significant durable changes. Keep it high-level: document capabilities, workflows, and entrypoints, not transient UI behavior or implementation trivia.
- **Autonomy:** You are authorized to run `sudo nixos-rebuild switch --flake` autonomously when requested or implied by the workflow (e.g., "rebuild").
- **Revision Tracking:** Always set `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;` in `configuration.nix` so `nixos-rebuild list-generations` shows the commit hash.
- **Dry Run:** Always use `nixos-rebuild dry-build` before asking the user to build, especially for complex derivations.
- **AppImages:** When wrapping AppImages with `appimageTools`, ensure common libraries like `webkitgtk`, `gtk4`, `libadwaita`, `graphene`, and `libsoup_3` are included in `extraPkgs` if the app has a GUI. Also include `gnome-themes-extra` and `gtk3` if theme errors occur.
- **Pear Runtime**: Apps like PearPass may take several minutes to load on the first run due to P2P network discovery.
- **Program Organization**: Organize `home.packages` in `home.nix` using clear comments for categories:
  - `GUI`: Desktop applications (Discord, Obsidian, etc.)
  - `CLI / Tools`: Command-line utilities and development tools.
  - `Disk Utilities`: Partitioning and file system tools.
  - `Fonts`: Icons and system fonts.
  - Keep each list alphabetical within its category for readability.
- **System Packages**: Only put essential bootstrap tools (like `git` if required by flakes for non-home-manager operations) in `hosts/common/default.nix`. Prefer `home.packages` for most user software.
- **Code Organization**: Modularize configurations into `modules/` (e.g., `modules/git.nix`, `modules/hyprland.nix`) to keep `home.nix` clean.
- **Comments**: Keep comments focused on "why" or "what" (e.g., "# Wrapper for native messaging"). Do NOT add meta-comments about your actions (e.g., "# I added this because user asked").
- **No Commented-Out Code**: Do not leave commented-out code blocks. Use git history if you need to revert or reference old code.

- **Subagent Rebuilds:** Use a subagent (task tool) to handle `nixos-rebuild` commands (dry-run and switch) to keep the main context clean and handle potential long output.
- **Bug Reporting:** When a bug is reported, prioritize writing a reproduction test before attempting a fix. Use subagents to implement the fix and verify it with the passing test.
- **Pre-Completion Dry Build:** After any config/code change and before reporting "done," run `nixos-rebuild dry-build --flake .#desktop` yourself and fix any failures before handing back to the user.
- **CI Shape:** GitHub Actions mirrors the flake checks with separate host (`desktop`, `usb`) and script-quality (`script-smoke`, `shellcheck`) jobs so failures stay isolated.
- **ShellCheck Scope:** ShellCheck currently lints the generated custom shell entrypoints from the Home Manager profiles, including host-variant wrappers where desktop and USB differ. If more shell logic moves into standalone `.sh` files later, extend linting to those sources too.
- **Validation vs Deployment:** CI and `nix flake check` only validate buildability and scripted checks. Deployment is still manual: `nixos-rebuild switch --flake .#desktop` for desktop and `update-usb` for the USB image.

## Hyprland Keybind Guidance

- **Prefer readable key names**: use bindings like `x` or `Return` by default; only fall back to `code:<n>` when Hyprland rejects the named key or layout-independent behavior is truly required.
- **Keyboard layouts**: This repo uses `us altgr-intl` and `gr simple`; `Super+Space` toggles between them.
- **Validation**: After keybind changes, test in both US and Greek layouts.
- **InvalidFormat troubleshooting**: Try a valid Hyprland key name first; use `code:<n>` only if the named key is rejected.

## Greenfield Projects: Spec Kit Workflow

Use **Spec Kit** (`specify` CLI) to scaffold spec-driven development for new projects. This unlocks `/speckit.*` slash commands in Copilot CLI.

- **Initialize a project:** `specify init <PROJECT_NAME> --ai copilot` (run in the project directory)
- **Slash commands available after init:**
  - `/speckit.constitution` — Define guiding principles
  - `/speckit.specify` — Describe what to build
  - `/speckit.plan` — Generate an implementation plan
  - `/speckit.tasks` — Break down work into tasks
  - `/speckit.implement` — Trigger implementation workflow
- The `specify` binary is installed declaratively via a `uvx` wrapper — no manual installation needed.



- **Vibrancy Physics:** High-end glassmorphism requires `xray = true` in Hyprland to prevent muddy artifacts from overlapping shadows. Optimal settings: `brightness > 1.1`, `vibrancy > 0.8`, and `contrast > 1.1`.
- **Systemd buffers:** When managing video surfaces (like `mpvpaper`) on Nvidia/Wayland, use systemd with `RestartSec=2.5` to prevent GPU buffer race conditions that crash the compositor.
- **Cursor Baking:** Always manually symlink modern cursor names (`left_ptr`, `pointer`, `default`, `progress`, `alias`) in custom theme derivations to prevent Adwaita fallbacks in browsers and system bars.
- **Hyprland Syntax:** `windowrulev2` is deprecated; use `windowrule` with `match:class` or `match:title` for all new configuration.
- **Hyprglass Transparency:** Hyprglass draws at `DECORATION_LAYER_BOTTOM` (behind window content). Glass only shows through transparent pixels. Native RGBA transparency (Ghostty's `background-opacity`, Vesktop's `transparent: true`) = proper liquid glass with opaque text. Compositor opacity (`opacity X override`) = uniform fade (text also becomes transparent). For compositor-opacity apps, use the `compositor_glass` preset (higher blur, lower refraction) to mask text fade. Default preset `high_contrast` (blur 1.2, contrast 1.14) is less milky than `default` (blur 2.0).
- **Hyprglass API Drift Fixes:** After Hyprland input updates, hyprglass may fail due to renderer/pass API changes. Patch the plugin derivation in `modules/home/hyprland.nix` (remove `GlassPassElement.cpp` usage and map old projection calls to `getBoxProjection` / `projectBoxToTarget`) before rebuilding.
- **Hyprglass Build Validation:** If `switch` fails in hyprglass, run both `nixos-rebuild dry-build --flake .#desktop` and `nixos-rebuild switch --flake .#desktop` after patching; dry-build alone may pass while activation build still reveals renderer ABI mismatches.
- **NIXOS_OZONE_WL Placement:** Must be in `home.sessionVariables` (e.g., in `modules/home/gh-copilot/default.nix`), NOT in Hyprland's `env =` block. Hyprland env= only propagates to keybind-launched apps, not DMS/QuickShell spotlight launchers. Session variables propagate to all user processes (D-Bus, systemd) and require log-out/log-in to take effect.
- **Desktop Entry Exec Lines:** Cannot contain complex shell syntax, pipes, redirects, or unquoted special characters. Use `pkgs.writeShellScript` to create a wrapper script and reference it in `exec`. Example: Vesktop needs a wrapper to patch `settings.json` before launch because Vesktop overwrites settings on exit.

## USB Update Workflow

- **Purpose:** Updates the bootable USB drive configuration from the `usb` flake output.
- **Command:** `sudo update-usb /path/to/system-manifest/main`
- **Flow:** Validates the labeled partitions, unlocks the LUKS root, mounts root and boot, runs `nixos-install` in prebuild mode by default, verifies Home Manager activation, syncs the final `nix-store.squashfs`, then unmounts and cleans up.
- **Note:** Script preflight checks mountpoint safety and can auto-enter `nix-shell` when `mksquashfs` is missing. Always pass a worktree path containing `flake.nix` (for example `.../main`), not the repo container root.
- **Runtime Validation:** `nix flake check` and `dry-build` do not prove USB-only runtime behavior. For cursor/rendering/DMS issues, update the stick and boot it on real target hardware before declaring the fix done.
- **GH auth on foreign machines:** When booting the USB on a computer lab machine, gnome-keyring may not auto-unlock. Store a fine-grained PAT (with "Copilot Requests" permission) in `~/.config/github-pat` on the encrypted USB partition: `echo "ghp_..." > ~/.config/github-pat && chmod 600 ~/.config/github-pat`. The shell will auto-export it as `GH_TOKEN`. This file is protected by LUKS and never committed to git.

## Copilot Session Sync (Desktop ↔ USB)

Copilot sessions live in `~/.copilot/session-state/`. To share them between desktop and USB, plug in the USB and use `copilot-sessions-sync`:

- `copilot-sessions-sync to-usb` — push desktop sessions to USB (run before leaving for a lab)
- `copilot-sessions-sync from-usb` — pull USB sessions back to desktop (run when back home)

The script finds the USB automatically via the `NIXOS_USB_CRYPT` disk label, unlocks LUKS, mounts, rsyncs, and unmounts. Requires `sudo`.

At the lab: `copilot --resume` to pick up synced sessions.

**Zellij sessions** are process-based (in-RAM) and cannot be shared across machines — this is fundamental. Config is declarative and identical on both systems.

## Known Issues / Fixes

- **Attribute Re-definition:** Nix doesn't allow defining the same attribute set key (like `home.file`) multiple times in the same file. You must merge them into a single block.

- **USB Formatting:** When formatting raw disks or running `update-usb`, scripts often fail because NixOS root environments lack standard utilities (like `sgdisk`, `parted`, `mkfs.ext4`). **Always** run disk manipulation scripts inside a shell with the required tools: `sudo nix-shell -p gptfdisk parted cryptsetup dosfstools e2fsprogs util-linux --run '<command>'`.
- **Neovim Swap Files:** If Neovim throws an `E325: ATTENTION` error or fails to open a file from `neo-tree`, it is blocked by a `.swp` file. Do not try to debug the plugin. The solution is to delete `~/.local/state/nvim/swap/*`. (Swap files are globally disabled in `opts.swapfile = false`, but old ones may linger).
- **Zellij Stacking Action Name:** On Zellij `0.43.1`, `TogglePaneEmbedOrEject` is invalid and causes config parse failure. Use `TogglePaneEmbedOrFloating` instead.

## Wallpaper System Architecture

The wallpaper stack has two independent renderers layered via `wlr-layer-shell`:

1. **linux-wallpaperengine (WE)** — renders live/animated wallpapers as a Wayland layer-shell surface at `Background` level. Managed by `linux-wallpaperengine.service`. Configured via environment variables `WE_WALLPAPER_DIR` and `WE_ASSETS_DIR`.
2. **DMS wallpaper** — renders static images as a Quickshell `PanelWindow` at `WlrLayer.Background`. Also triggers **matugen** color generation when set via `dms ipc wallpaper set`.

**Z-order:** WE's layer surface is created *after* DMS, so WE paints ON TOP of DMS. When WE is running, the DMS wallpaper is invisible behind it.

### Key files

| File | What it contains |
|------|-----------------|
| `modules/home/wallpaper-selector.nix` | `wallpaper-apply` unified script (static/dynamic/audio subcommands), wallpaper-selector launcher, QML Theme.qml |
| `modules/home/wallpaper/default.nix` | Entry point wiring the split wallpaper stack into Home Manager |
| `modules/home/wallpaper/common.nix` | Shared path constants (`MAP_FILE`, `WE_ASSETS`, `WE_WORKSHOP`, `WE_DEFAULTS_ROOT`, `WALL_DIR`) and `normalize_dir()` |
| `modules/home/wallpaper/services.nix` / `hook.nix` / `engine-sync.nix` | WE services, wallpaper-hook daemon, and thumbnail generation logic |
| `modules/home/dms/default.nix` / `usb.nix` | Shared DMS configuration plus USB-specific overrides and patching |
| Fork: `github.com/skamprogiannis/wallpaper-selector` | QML UI (`Selector.qml`), playlist daemon script |

### Scripts in PATH (4 total)

| Script | Purpose |
|--------|---------|
| `wallpaper-apply` | Unified entry point: `wallpaper-apply static <image>`, `wallpaper-apply dynamic <dir>`, `wallpaper-apply audio mute\|unmute` |
| `wallpaper-selector` | Launches the Quickshell wallpaper picker UI |
| `wallpaper-playlist` | Background daemon for timed wallpaper rotation |
| `wallpaper-engine-sync` | Generates thumbnails from WE workshop folders (multi-strategy: offscreen GL → middle-frame extraction → author preview.jpg) |

### Transition ordering (critical)

When switching wallpapers, always **set DMS before restarting/stopping WE**:

- **Dynamic→Dynamic:** Set new DMS thumbnail first (invisible behind running WE), then `systemctl restart` WE. The brief restart gap shows the correct new thumbnail.
- **Dynamic→Static:** Set new static wallpaper in DMS first (invisible behind WE), then stop WE. DMS reveals the correct wallpaper.
- **Static→Dynamic:** Set DMS thumbnail, then start WE. WE eventually paints over DMS.

The DMS thumbnail MUST always be set because that's the only way to trigger **matugen** color generation.

### wallpaper-hook daemon

Runs as a systemd user service, polls `dms ipc wallpaper get` every 2s. Responsibilities:
- Boot restore: detects last wallpaper from DMS, starts WE if dynamic
- Wallpaper change detection: restarts WE when DMS wallpaper changes (skip if WE already running with same dir)
- Theme sync: monitors `~/.config/hypr/dms/colors.conf` and regenerates Zathura, Vesktop, and other app themes

### Thumbnail generation (`wallpaper-engine-sync`)

Multi-strategy fallback for each workshop wallpaper:
1. **Video type:** Extract middle frame via `ffmpegthumbnailer` → author `preview.jpg` → offscreen GL render
2. **Scene type:** Offscreen GL render (5s delay, retry at 8s) → author `preview.jpg`

`normalize_thumb()` scales to 1920×1080. For small sources (<640px wide) or non-16:9 aspect ratios, it letterboxes on a blurred background instead of aggressive crop+zoom.

Thumbnails are stored in `~/wallpapers/.wallpaper-engine/` with a JSON map at `~/.cache/we-wallpaper-map.json`.

### DMS IPC reference

```bash
dms ipc wallpaper set <path>      # Set wallpaper + trigger matugen
dms ipc wallpaper get              # Get current wallpaper path
dms ipc call dash toggle <tab>     # Toggle dash widget (wallpaper|overview|media|weather)
dms ipc call spotlight toggle      # App launcher
dms ipc call clipboard toggle      # Clipboard manager
dms ipc call notifications toggle  # Notification center
dms ipc call settings toggle       # Settings panel
dms ipc call powermenu toggle      # Power menu
dms ipc call lock lock             # Lock screen
dms ipc call hypr toggleOverview   # Workspace overview
dms ipc call mpris playPause       # Media control
dms ipc call notifications clearAll  # Clear all notifications
```

### Wallpaper-selector QML (fork)

Custom features on top of upstream (`Aino-Chan/wallpaper-selector`):
- Vim keybinds (hjkl navigation)
- Monitor scoping (multi-monitor via Hyprland.focusedMonitor)
- DMS theme tracking (reads `colors.conf` instead of pywal `colors.json`)
- Content filtering (mature content toggle)
- Configurable card dimensions (`:width`, `:height`, `:spacing`, `:scale` commands)
- Hover tracking with `hoveredIndex` state management

The QML calls `wallpaper-apply` directly with mode argument (no `.sh` shim wrappers).
