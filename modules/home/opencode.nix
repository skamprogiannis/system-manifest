{
  config,
  pkgs,
  ...
}: {
  # OpenCode Configuration
  home.file = {
    ".config/opencode/opencode.json".text = ''
      {
        "$schema": "https://opencode.ai/config.json",
        "theme": "system",
        "plugin": ["opencode-antigravity-auth@latest"],
        "mcp": {
          "context7": {
            "type": "local",
            "command": ["npx", "-y", "@upstash/context7-mcp"]
          }
        },
        "formatter": {
          "prettier": {
            "command": ["npx", "prettier", "--write", "$FILE"],
            "extensions": [".js", ".ts", ".jsx", ".tsx", ".json", ".css", ".md"]
          },
          "ruff": {
            "command": ["ruff", "format", "$FILE"],
            "extensions": [".py", ".pyi"]
          },
          "gofmt": {
            "command": ["gofmt", "-w", "$FILE"],
            "extensions": [".go"]
          }
        },
        "lsp": {
          "gopls": {
            "command": ["gopls"],
            "extensions": [".go"]
          },
          "typescript-language-server": {
            "command": ["npx", "typescript-language-server", "--stdio"],
            "extensions": [".ts", ".tsx", ".js", ".jsx"]
          }
        }
      }
    '';

    ".config/opencode/AGENTS.md".text = ''
      # OpenCode Global Agents Guidelines

      ## IMPORTANT GLOBAL RULES
      BEFORE replying, ALWAYS ask yourself: should I use a skill for this? And use the most appropriate skills to be helpful and use the best tools available to you.

      ## Context & Awareness
      1. **Bootstrap:** At the start of a task, **ALWAYS** check the root directory for `AGENTS.md`, `GEMINI.md`, or `README.md`. These contain project-specific architecture, patterns, and overrides.
      2. **Precedence:** **Repo-specific rules (in local `AGENTS.md`) ALWAYS take precedence over these global rules.**
      3. **Holistic Thinking:** Think holistically. Ask: "If I change this file, what imports, tests, or documentation will break?"

      ## Workflow & Quality
      - **Clarification:** ALWAYS ask clarifying questions BEFORE committing to a plan. Surface edge cases the user may not have considered.
      - **Formatters & Linters:** After editing code, **ALWAYS run the configured formatters/linters** (e.g., `prettier`, `ruff`, `gofmt` or `nixfmt`) to ensure standards.
      - **Subagents:** Use subagents for research and long-running tasks (like builds/test runs) to keep the main context clean.
      - **Style:** Do NOT use emojis in documentation or commit messages unless explicitly requested.

      ## Verification Before Done
      - **Proof of Work:** Never mark a task complete without proving it works (tests pass, build succeeds, feature demonstrable).
      - **Diff Behavior:** Compare behavior between main and your changes when relevant.
      - **Staff Engineer Test:** Ask yourself, "Would a staff engineer approve this?"
      - **Test Baseline:** Run tests before and after changes to establish baseline and catch regressions.

      ## Autonomous Bug Fixing
      - **Self-Sufficiency:** When given a bug report, analyze, fix, and verify. Don't ask for hand-holding.
      - **Root Cause:** Point at logs, errors, and failing tests—then resolve them.
      - **Zero Context Switching:** User requires no follow-up or hand-holding.

      ## Self-Improvement Loop
      - **Capture Corrections:** After ANY correction from the user, update `tasks/lessons.md` with the pattern that was wrong and the correct approach.
      - **Iterate Ruthlessly:** Iterate on lessons until mistake rate drops.
      - **Session Start Review:** Review lessons at session start for relevant project context.

      ## Git & Commits
      - **Gists:** Always create **private/secret** gists. Never use `--public`.
      - **Atomic Commits:** Keep commits focused on a single logical change.
      - **Format:** Use **Conventional Commits** (`type(scope): message`).
        - Subject: Imperative mood, aim for <72 chars.
        - Body: Optional, explain the "why".
      - **Push:** `git push` immediately after committing.

      ## Security
      - **No Secrets:** Never commit secrets, `.env` files, API keys, or credentials.
      - **Explicit Warnings:** Warn the user explicitly if they request to commit sensitive files.
      - **Gitignore Check:** Review `.gitignore` to ensure sensitive patterns are excluded.

      ## Dependencies & Testing
      - **Avoid Duplication:** Before adding new packages/libraries, check if existing code already covers functionality.
      - **Test Baseline:** If tests exist in the project, run them before and after changes to establish baseline and catch regressions.

      ## Error Handling
      - **File Edit Conflicts:** If you encounter "File has been modified since read", retry with exponential backoff (immediately, wait 10s, wait 30s, wait 60s).
    '';
  };
}
