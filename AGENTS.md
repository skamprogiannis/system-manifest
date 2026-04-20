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

Wallpaper selection and theming are handled by [skwd-wall](https://github.com/liixini/skwd-wall), a Quickshell-based selector with a Rust daemon backend.

### Key components

| Component | Purpose |
|-----------|---------|
| `skwd-wall` | GUI selector (Quickshell) with slice/grid/hex display modes |
| `skwd-daemon` | Systemd user service — wallpaper lifecycle, boot restore, matugen |
| `skwd` | CLI interface to the daemon |
| `awww` | Static wallpaper renderer (wlr-layer-shell) |
| `mpvpaper` | Video wallpaper renderer |
| `linux-wallpaperengine` | Wallpaper Engine scene renderer |

### Config

Declared in `modules/home/skwd-wall.nix`. Config is generated at `~/.config/skwd-wall/config.json` via Home Manager. Custom matugen templates are merged with bundled ones into a Nix store path.

### Matugen integrations

| Integration | Template | Output |
|-------------|----------|--------|
| `skwd-wall` | `quickshell-colors.json` | Shell UI colors |
| `hyprland-dms` | `hyprland-dms-colors.conf` | `~/.config/hypr/dms/colors.conf` (DMS + Hyprland borders) |
| `zathura` | `zathura-colors` | `~/.config/zathura/skwd-colors` (included from zathurarc) |
| `vesktop` | `vesktop.css` | `~/.config/vesktop/themes/skwd-matugen.css` |

### DMS interaction

- `awww` renders wallpapers via wlr-layer-shell at Background level, painting on top of DMS's PanelWindow
- Matugen generates `colors.conf` → DMS sources it for Hyprland color variables
- `Super+Shift+W` (`dms ipc call dash toggle wallpaper`) still toggles the DMS wallpaper dashboard widget

### DMS IPC reference

```bash
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
