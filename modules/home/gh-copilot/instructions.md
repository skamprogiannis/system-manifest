# GH Copilot Global Instructions

## Context & System Architecture

This is a NixOS system with declarative, reproducible configuration management. GH Copilot should understand:

- **OS**: NixOS (immutable, reproducible, Nix-based)
- **WM**: Hyprland (Wayland compositor with glassmorphism)
- **Terminal**: Ghostty + Zellij (multiplexer)
- **Editor**: Neovim (primary), Vim (GH CLI default)
- **Shell**: Bash (vi mode enabled)
- **Language**: Greek + US keyboard layouts (Super+Space to toggle)

**CRITICAL**: Always check `/home/stefan/system_manifest/AGENTS.md` for project-specific rules and best practices. Those take precedence over general guidance.

## Workflow for NixOS Configuration

1. **Edit** `.nix` files in `modules/home/` or `hosts/`
2. **Dry-build** FIRST: `nixos-rebuild dry-build --flake .#desktop`
3. **Fix errors** if any (Nix is strict)
4. **Commit**: `git commit -m "type(scope): message"` with Conventional Commits format
5. **Push**: `git push` immediately
6. **Apply**: `sudo nixos-rebuild switch --flake .#desktop`

**Always commit before rebuilding** - this ensures clean generation tracking and rollback capability.

## Keybinds & Keyboard Configuration

- **Use keycodes**: `code:36` (not key names like `Return`) for cross-layout support
- **Greek layout**: Simple variant only (basic accents via apostrophe, no polytonic)
- **Toggle**: Super+Space switches between US and Greek
- **Test both layouts**: After any keybind change, verify it works in both US and Greek

## Code Organization Rules

- **Modular**: One feature per file (e.g., `modules/home/hyprland.nix`)
- **Always import**: Add imports to `home.nix` when creating new modules
- **Comments**: Focus on "why" and "what", not meta-commentary
- **No dead code**: Use git history; don't leave commented-out blocks

## Common Pitfalls & Solutions

| Issue | Solution |
|-------|----------|
| "InvalidFormat" keybind error | Use keycodes (code:36) not key names (Return) |
| Window rules not applying | Windows must be opened AFTER the rule is added |
| Keyboard switching broken | Ensure kb_variant is compatible with xkb option (simple vs ext) |
| Zellij config parse error | Validate key names (no "Escape"; use specific keys) |
| Attribute re-definition error | Can't define same key twice in Nix; merge blocks |
| Build fails silently | Always run `dry-build` first to catch errors early |

## Testing & Validation

- **After keybind changes**: Test in both US and Greek layouts
- **After window rule changes**: Close/reopen windows to see effect
- **After config changes**: `hyprctl reload` or full restart as needed
- **Before marking done**: Run `nixos-rebuild dry-build` to ensure no regressions

## Git Commit Guidelines

```
type(scope): short description <72 chars

Optional body explaining the why.

Examples:
- feat(hyprland): add Super+Space keyboard layout switching
- fix(keyboard): revert to simple Greek variant for xkb compatibility
- docs(AGENTS): update keybind documentation
```

**Types**: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert  
**Scopes**: desktop, laptop, usb, common, home, system, or module names

## When Things Break

1. **Check error output carefully** - Nix syntax is strict
2. **Run dry-build in isolation** - reproduces config errors
3. **Verify window state** - rules only apply to NEW windows
4. **Check git history** - `git log --oneline -10` to see recent changes
5. **Ask: Did the user rebuild?** - Configuration changes require rebuild to apply

## Greenfield Project Workflow

When building new projects from scratch, use the following workflow and tools:

### Available Skills

| Skill | What it does | Trigger |
|-------|-------------|---------|
| `visual-explainer` | Generate HTML diagrams, diff reviews, plan reviews, architecture overviews | Ask for any diagram, visualization, or when presenting complex tables |
| `technical-debt` | Analyze codebase health, quantify debt, generate refactoring roadmaps | Ask for debt audit, code health check, or refactoring plan |
| `browser-automation` | Control Chrome via PinchTab for testing, scraping, form filling | Ask to test a web UI, extract page content, or automate browser tasks |

### Available Agents

| Agent | What it does | When to use |
|-------|-------------|-------------|
| `plan-reviewer` | Structured 4-section plan review (Architecture → Code Quality → Tests → Performance) | Before implementing any significant plan |
| `security-reviewer` | OWASP-focused security analysis with severity ratings | When writing auth, API, input handling, or any security-sensitive code |

### Project Bootstrap Sequence

1. **Scaffold** with Spec Kit: `specify init <PROJECT_NAME> --ai copilot`
2. **Define constitution**: `/speckit.constitution` — guiding principles
3. **Specify features**: `/speckit.specify` — describe what to build
4. **Plan**: `/speckit.plan` or `/plan` — generate implementation plan
5. **Review plan**: Use `@plan-reviewer` agent before coding
6. **Implement**: `/speckit.implement` or work interactively
7. **Security check**: Use `@security-reviewer` agent on new code
8. **Visualize**: Use `visual-explainer` skill for architecture diagrams

### Multi-Agent Patterns

- **Plan → Review → Implement**: Create plan, run plan-reviewer agent, then implement
- **Implement → Security → Ship**: Write code, run security-reviewer agent, then commit
- **Audit → Roadmap**: Run technical-debt skill, then plan refactoring sprints
- **Test → Visualize**: Run tests, then use visual-explainer for coverage reports
