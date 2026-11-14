# Agents and Workflows

This file contains the default repository-wide rules. Read the relevant reference before changing a subsystem: [maintainer notes](docs/maintainers.md), [desktop/system](docs/system.md), [USB](docs/usb.md), [CI](docs/ci.md), or [Codex workflow](modules/home/codex/WORKFLOW.md).

## Git and code changes

- Standard repository layout: the repository root is `~/system-manifest`. Isolated workspaces for agents or subtasks are created in `/tmp/` via standard git worktrees or branches.
- Uphold code stewardship: build cleanly, modularly, and with proper separation of concerns. Do not bolt on ad-hoc configurations or duplicate modules; propose a refactor if an addition does not fit naturally.
- Use atomic **Conventional Commits** (`type(scope): summary`). Squash local fix-on-fix iterations before pushing. Commit before deploying so generation revisions remain traceable.
- Keep system Git in `hosts/common/default.nix` so flakes work. Prefer Home Manager for non-bootstrap applications and put larger modules under `modules/`.
- Keep comments about behavior and intent; remove dead/commented-out code. Update the README for durable user-facing changes, and keep implementation detail in the relevant guide.
- Global agent instructions live in `modules/home/codex/instructions.md` (synced to `~/.codex/AGENTS.md`) and `modules/home/antigravity/instructions.md` (synced to `~/.gemini/config/AGENTS.md`); `AGENTS.md` here is for repository contributors.
- Preserve `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;` in `hosts/common/default.nix`.

## Validation and deployment

- Choose checks proportional to the affected behavior and risk. Run relevant package and contract checks; evaluate or build affected host configurations when integration warrants it. Use `nix flake check` for broad shared changes, uncertain impact, or comprehensive validation, rather than every small change. Reproduce bugs where practical.
- Build or dry-build the affected desktop configuration before desktop deployment or when desktop integration changes; an actual system build satisfies this check. For docs-only changes, review source accuracy and links. Report unrun checks and hardware limitations.
- Checks do not deploy. Activate only when requested or already authorized, using `sudo nixos-rebuild switch --flake .#desktop` / `.#laptop`, or `sudo update-usb ~/system-manifest`. Commit first before deploying.
- CI uses `checks/registry.nix`; keep check coverage and ownership aligned. Register shell entrypoints in `checks/context.nix`. CI success does not establish GPU, display, or USB hardware behavior.
- For changes to USB storage, staging, recovery, or synchronization, **read [docs/usb.md](docs/usb.md)** and test on a real USB boot before declaring runtime correctness.
- For wallpapers, greeter, blur, or keybindings, **read [docs/system.md](docs/system.md#desktop-maintenance)** and [DESIGN.md](DESIGN.md) before editing. Preserve their ownership boundaries.
- For Codex packages/agents, follow [docs/maintainers.md](docs/maintainers.md) and the [Codex workflow guide](modules/home/codex/WORKFLOW.md). Keep shared version pins and adapter checks in sync.

## Commands

Examples; select the checks appropriate to the change:

```bash
cd ~/system-manifest
nix flake check
nixos-rebuild dry-build --flake .#desktop
nixos-rebuild test --flake .#desktop
nixos-rebuild list-generations
```

See [docs/maintainers.md](docs/maintainers.md) for detailed commands, model/package checks, troubleshooting, and coding conventions.
