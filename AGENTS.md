# OpenCode Agents & Workflows

## Useful Commands

- **Dry Run Build:** `nixos-rebuild dry-build --flake .#nixos` (Checks for evaluation errors without applying changes)
- **Check Configuration:** `nixos-rebuild test --flake .#nixos` (Builds and activates, but doesn't add to bootloader - good for temporary testing)
- **List Generations:** `nixos-rebuild list-generations`
- **Garbage Collect:** `nix-collect-garbage -d` (Deletes old generations)

## OpenCode Tips

- **Session Info:** `/session` command.
- **Model Variants:** `Ctrl+T` toggles between High (Reasoning) and Low (Speed) models.
- **Git & Gens:** Keep git commits atomic and descriptive.
- **Commit Format:** Use **Conventional Commits** (`type(scope): message`).
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  - Scopes: `desktop`, `laptop`, `usb`, `common`, `home`, `system`, or specific module names.
  - Example: `feat(desktop): enable steam and gamemode`
  - Example: `fix(usb): correct luks mounting path`
- **System Git:** Ensure `git` is always in `environment.systemPackages` in `configuration.nix` (required for Flakes).
- **Git Push:** Always `git push` (or force push if history was rewritten) immediately after creating a new commit.
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

## USB Update Workflow

- **Purpose:** Updates the bootable USB drive configuration from the `usb` flake output.
- **Command:** `sudo ./update_usb.sh`
- **Steps:**
  1.  Ensures root privileges.
  2.  Unlocks the LUKS container (hardcoded to `/dev/sdc2`).
  3.  Mounts root and boot partitions to `/mnt`.
  4.  Runs `nixos-install --flake .#usb --root /mnt --no-root-passwd`.
  5.  Unmounts and cleans up.
- **Note:** The script currently hardcodes device paths (`/dev/sdc`). Verify device names with `lsblk` before running if devices have changed.

## Known Issues / Fixes

- **Attribute Re-definition:** Nix doesn't allow defining the same attribute set key (like `home.file`) multiple times in the same file. You must merge them into a single block.
