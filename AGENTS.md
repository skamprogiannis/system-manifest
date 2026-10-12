# Agents and Workflows

This file contains the default repository-wide rules. Read the relevant reference before changing a subsystem: [maintainer notes](docs/maintainers.md), [desktop/system](docs/system.md), [USB](docs/usb.md), [CI](docs/ci.md), or [Codex/Clef](modules/home/codex/CLEF.md).

## Git and code changes

- Worktree-first repository: `~/system-manifest/main` is the main worktree; the bare git directory is `~/system-manifest/.bare`. Never edit `.bare`. Run commands from the intended worktree.
- Use atomic **Conventional Commits** (`type(scope): summary`). Squash local fix-on-fix iterations before pushing. Commit before deploying so generation revisions remain traceable.
- Keep system Git in `hosts/common/default.nix` so flakes work. Prefer Home Manager for non-bootstrap applications and put larger modules under `modules/`.
- Keep comments about behavior and intent; remove dead/commented-out code. Update the README for durable user-facing changes, and keep implementation detail in the relevant guide.
- Repository-wide Codex instructions live in `modules/home/codex/instructions.md` and are synchronized by Home Manager; `AGENTS.md` here is for repository contributors.
- Preserve `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;` in `hosts/common/default.nix`.

## Validation and deployment

- Run `nix flake check` and the appropriate `nixos-rebuild dry-build --flake .#<host>` for configuration changes. Reproduce bugs where practical before fixing them.
- Before reporting a desktop configuration change complete, run `nixos-rebuild dry-build --flake .#desktop`; resolve failures. For docs-only changes, review source accuracy and links.
- Deployment remains manual: `sudo nixos-rebuild switch --flake .#desktop` / `.#laptop`, or `sudo update-usb ~/system-manifest/main`. Run from the correct worktree.
- CI uses `checks/registry.nix`; keep check coverage and ownership aligned. Register shell entrypoints in `checks/context.nix`. CI success does not establish GPU, display, or USB hardware behavior.
- For changes to USB storage, staging, recovery, or synchronization, **read [docs/usb.md](docs/usb.md)** and test on a real USB boot before declaring runtime correctness.
- For wallpapers, greeter, blur, or keybindings, **read [docs/system.md](docs/system.md#desktop-maintenance)** and [DESIGN.md](DESIGN.md) before editing. Preserve their ownership boundaries.
- For Codex packages/agents, follow [docs/maintainers.md](docs/maintainers.md) and the [Clef guide](modules/home/codex/CLEF.md). Keep shared version pins and adapter checks in sync.

## Commands

```bash
cd ~/system-manifest/main
nix flake check
nixos-rebuild dry-build --flake .#desktop
nixos-rebuild test --flake .#desktop
nixos-rebuild list-generations
```

See [docs/maintainers.md](docs/maintainers.md) for detailed worktree commands, model/package checks, troubleshooting, and coding conventions.
