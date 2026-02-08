# Opencode Agents & Workflows

## Useful Commands
- **Dry Run Build:** `nixos-rebuild dry-build --flake .#nixos` (Checks for evaluation errors without applying changes)
- **Check Configuration:** `nixos-rebuild test --flake .#nixos` (Builds and activates, but doesn't add to bootloader - good for temporary testing)
- **List Generations:** `nixos-rebuild list-generations`
- **Garbage Collect:** `nix-collect-garbage -d` (Deletes old generations)

## Opencode Tips
- **Session Info:** `/session` command.
- **Model Variants:** `Ctrl+T` toggles between High (Reasoning) and Low (Speed) models.
- **Git & Gens:** Keep git commits 1:1 with system generations for clean history.
- **Revision Tracking:** Always set `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;` in `configuration.nix` so `nixos-rebuild list-generations` shows the commit hash.
- **Dry Run:** Always use `nixos-rebuild dry-build` before asking the user to build, especially for complex derivations.
- **Code Organization:** Modularize configurations into `modules/` (e.g., `modules/git.nix`, `modules/hyprland.nix`) to keep `home.nix` clean.
- **Comments:** Keep comments focused on "why" or "what" (e.g., "# Wrapper for native messaging"). Do NOT add meta-comments about your actions (e.g., "# I added this because user asked").

## Known Issues / Fixes
- **Attribute Re-definition:** Nix doesn't allow defining the same attribute set key (like `home.file`) multiple times in the same file. You must merge them into a single block.

- **Attribute Re-definition:** Nix doesn't allow defining the same attribute set key (like `home.file`) multiple times in the same file. You must merge them into a single block.
