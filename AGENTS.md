# OpenCode Agents & Workflows

## Useful Commands

- **Dry Run Build:** `nixos-rebuild dry-build --flake .#nixos` (Checks for evaluation errors without applying changes)
- **Check Configuration:** `nixos-rebuild test --flake .#nixos` (Builds and activates, but doesn't add to bootloader - good for temporary testing)
- **List Generations:** `nixos-rebuild list-generations`
- **Garbage Collect:** `nix-collect-garbage -d` (Deletes old generations)

## OpenCode Tips

- **Session Info:** `/session` command.
- **Model Variants:** `Ctrl+T` toggles between High (Reasoning) and Low (Speed) models.
- **Git & Gens:** Keep git commits 1:1 with system generations for clean history.
- **Commit Format:** Use `gen(N): message` format for all commit messages.
- **System Git:** Ensure `git` is always in `environment.systemPackages` in `configuration.nix` (required for Flakes).
- **Git Push:** Always `git push` (or force push if history was rewritten) immediately after creating a new commit.
- **Autonomy:** You are authorized to run `sudo nixos-rebuild switch --flake` autonomously when requested or implied by the workflow (e.g., "rebuild").
- **Revision Tracking:** Always set `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;` in `configuration.nix` so `nixos-rebuild list-generations` shows the commit hash.
- **Dry Run:** Always use `nixos-rebuild dry-build` before asking the user to build, especially for complex derivations.
- **AppImages:** When wrapping AppImages with `appimageTools`, ensure common libraries like `webkitgtk`, `gtk4`, `libadwaita`, `graphene`, and `libsoup_3` are included in `extraPkgs` if the app has a GUI. Also include `gnome-themes-extra` and `gtk3` if theme errors occur.
- **Pear Runtime:** Apps like PearPass may take several minutes to load on the first run due to P2P network discovery.
- **Code Organization:** Modularize configurations into `modules/` (e.g., `modules/git.nix`, `modules/hyprland.nix`) to keep `home.nix` clean.
- **Comments:** Keep comments focused on "why" or "what" (e.g., "# Wrapper for native messaging"). Do NOT add meta-comments about your actions (e.g., "# I added this because user asked").

- **Subagent Rebuilds:** Use a subagent (task tool) to handle `nixos-rebuild` commands (dry-run and switch) to keep the main context clean and handle potential long output.
- **Bug Reporting:** When a bug is reported, prioritize writing a reproduction test before attempting a fix. Use subagents to implement the fix and verify it with the passing test.

## Known Issues / Fixes

- **Attribute Re-definition:** Nix doesn't allow defining the same attribute set key (like `home.file`) multiple times in the same file. You must merge them into a single block.
