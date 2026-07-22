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
| `caveman` | Terse response style with technical accuracy and minimal filler | Ask for concise, low-token output |
| `caveman-commit` | Terse Conventional Commit messages in caveman style | Ask for a commit message |
| `caveman-review` | Compact code-review findings in caveman style | Ask for a terse review |
| `diagnose` | Disciplined reproduce/minimize/hypothesize/instrument/fix loop | Hard bugs, broken behavior, or performance regressions |
| `grilling` | Stress-test a plan or design one decision at a time | Ask to be grilled about a plan or design |
| `domain-modeling` | Sharpen domain terminology and record durable decisions | Ask to define domain language or an architectural decision |
| `grill-with-docs` | Stress-test plans while maintaining domain docs | Ask to be grilled against project docs and language |
| `codebase-design` | Design deep modules, small interfaces, and clean seams | Ask to design or deepen a module interface |
| `code-review` | Review changes against repository standards and their originating spec | Ask to review a branch, PR, or work-in-progress diff |
| `triage` | Issue workflow and triage role state machine | Ask to create, review, or prepare issues |
| `improve-codebase-architecture` | Find architectural refactoring opportunities | Ask to improve architecture, testability, or codebase navigation |
| `setup-matt-pocock-skills` | Configure issue-tracker and domain context for engineering workflows | Ask to set up project context for these skills |
| `tdd` | Red-green-refactor feature and bug-fix workflow | Ask for TDD, test-first work, or integration-test-driven changes |
| `implement` | Implement a specification or ticket through testing and review | Ask to implement planned work |
| `zoom-out` | Explain a code area from a higher level | Ask for broader context or unfamiliar module maps |
| `prototype` | Build throwaway prototypes for design validation | Ask to prototype UI, state, or data-model choices |
| `to-issues` | Convert plans/specs into implementation issues | Ask to break plans into issues |
| `to-prd` | Convert current context into a PRD | Ask to write a PRD |

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
