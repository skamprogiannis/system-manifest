# Codex Global Instructions

## Context & System Architecture

This machine normally uses:

- **OS**: NixOS
- **WM**: Hyprland
- **Terminal**: Ghostty + Zellij
- **Editor**: Neovim
- **Shell**: Bash
- **Keyboard layouts**: Greek + US

Always check the local repository for `AGENTS.md` first. Local repository instructions take precedence over this file.

## Global Scope

- Keep this file useful across repositories.
- Put repository-specific workflows, architecture notes, build commands, troubleshooting, and deployment rules in the repository's own instruction files, not here.
- When suggesting commands, prefer Linux-friendly, Bash-compatible examples.
- Use relevant installed skills when they clearly match the task.
- Use custom agents when the user explicitly asks for subagents, agent delegation, or specialized agent review.
- Do not add Copilot co-author trailers or other AI co-author trailers to commit messages.

## Caveman Persona Rule

- When responding in caveman mode, use the name **Grug**.
- When not in caveman mode, do not use the name Grug.

## Commit Hygiene

- Use atomic commits: each commit should contain one self-contained, logical change so it stays easy to review, revert, and bisect.
- When generating commit messages, prefer the `caveman-commit` skill for terse Conventional Commit phrasing.

## Available Skills

| Skill | What it does | Trigger |
|-------|-------------|---------|
| `visual-explainer` | Generate HTML diagrams, diff reviews, plan reviews, architecture overviews | Ask for any diagram, visualization, or complex table |
| `technical-debt` | Analyze codebase health, quantify debt, generate refactoring roadmaps | Ask for debt audit, code health check, or refactoring plan |
| `browser-automation` | Control Chrome via PinchTab for testing, scraping, form filling | Ask to test a web UI, extract page content, or automate browser tasks |
| `static-analysis` | Run CodeQL, Semgrep, and SARIF workflows | Ask for scanner-backed security audit, CodeQL/Semgrep scan, or SARIF interpretation |
| `impeccable` | Frontend design skill covering typography, color, layout, motion, and anti-patterns | Any frontend/UI work |
| `ui-ux-pro-max` | UI/UX design skill pack for design systems, styling, branding, banners, and slides | Broader UI/UX direction, design systems, branding, or polished interface work |
| `caveman` | Token-compressed response style plus terse commit/review helpers | Ask for concise, low-token output or compressed review/commit phrasing |

## Available Custom Agents

| Agent | What it does | When to use |
|-------|-------------|-------------|
| `plan-reviewer` | Structured four-section plan review: architecture, code quality, tests, performance | When the user asks for a plan review or custom agent review before implementation |
| `security-reviewer` | OWASP-focused security analysis with severity ratings | When the user asks for a security review of auth, API, input handling, or sensitive-data code |

## Greenfield Project Workflow

When building new projects from scratch, use Spec Kit:

1. Scaffold with `specify init <PROJECT_NAME> --integration codex`.
2. Define principles with `$speckit-constitution`.
3. Specify features with `$speckit-specify`.
4. Plan with `$speckit-plan` or `/plan`.
5. Track a long-running objective with `/goal <objective>` when useful.
6. Review significant plans with the `plan-reviewer` custom agent when the user asks for agent delegation.
7. Implement interactively.
8. Run the `security-reviewer` custom agent on new security-sensitive code when the user asks for agent delegation.
9. Use `visual-explainer` for architecture diagrams or visual summaries.

## Multi-Agent Patterns

- **Plan -> Review -> Implement**: Create plan, run `plan-reviewer` when delegated, then implement.
- **Implement -> Security -> Ship**: Write code, run `security-reviewer` when delegated, then commit.
- **Audit -> Roadmap**: Run `technical-debt`, then plan refactoring work.
- **Test -> Visualize**: Run tests, then use `visual-explainer` for coverage or architecture reports.
- **Design -> Polish -> Ship**: Use `impeccable` for design audit and polish, then commit.

## Skill Output Paths

- Visual Explainer: store generated HTML artifacts under `~/.codex/diagrams/`. Prefer `~/.codex/diagrams/<name>.html` as the canonical output path.
