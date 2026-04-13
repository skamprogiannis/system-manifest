# GH Copilot Global Instructions

## Context & System Architecture

This machine normally uses:

- **OS**: NixOS
- **WM**: Hyprland
- **Terminal**: Ghostty + Zellij
- **Editor**: Neovim
- **Shell**: Bash
- **Keyboard layouts**: Greek + US

**CRITICAL**: Always check the local repository for `AGENTS.md` or `copilot-instructions.md` first. Local repository instructions take precedence over this file.

## Global Scope

- Keep this file useful across repositories.
- Put repository-specific workflows, architecture notes, build commands, troubleshooting, and deployment rules in the repository's own instruction files, not here.
- When suggesting commands, prefer Linux-friendly, Bash-compatible examples.
- Use relevant installed skills or custom agents when they clearly match the task.
- Do **not** add `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` (or any Copilot co-author trailer) to commit messages.

## Caveman Persona Rule

- When responding in caveman mode, use the name **Grug**.
- When not in caveman mode, do not use the name Grug.

## Commit Hygiene

- Use atomic commits: each commit should contain one self-contained, logical change so it stays easy to review, revert, and bisect.
- When generating commit messages, prefer the `caveman-commit` skill for terse Conventional Commit phrasing.

## Greenfield Project Workflow

When building new projects from scratch, use the following workflow and tools:

### Available Skills

| Skill | What it does | Trigger |
|-------|-------------|---------|
| `visual-explainer` | Generate HTML diagrams, diff reviews, plan reviews, architecture overviews | Ask for any diagram, visualization, or when presenting complex tables |
| `technical-debt` | Analyze codebase health, quantify debt, generate refactoring roadmaps | Ask for debt audit, code health check, or refactoring plan |
| `browser-automation` | Control Chrome via PinchTab for testing, scraping, form filling | Ask to test a web UI, extract page content, or automate browser tasks |
| `static-analysis` | Run security-focused static analysis workflows around CodeQL, Semgrep, and SARIF parsing | Ask for a scanner-backed security audit, CodeQL/Semgrep scan, or help interpreting SARIF findings |
| `impeccable` | Frontend design skill with 20 commands (`/audit`, `/polish`, `/typeset`, `/arrange`, etc.) covering typography, color, layout, motion, and anti-patterns | Any frontend/UI work — building web components, pages, or applications |
| `caveman` | Token-compressed response style plus helpers for terse commits/reviews (`caveman-commit`, `caveman-review`) | Ask for concise, low-token output or compressed review/commit phrasing |

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
- **Design → Polish → Ship**: Use impeccable `/audit` to find design issues, `/polish` to fix them, then commit

### Skill Output Paths

- **Visual Explainer:** Store generated HTML artifacts under `~/.copilot/diagrams/`, not `~/.agent/diagrams/`. When invoking the skill or following its prompts, prefer `~/.copilot/diagrams/<name>.html` as the canonical output path.
