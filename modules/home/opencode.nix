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
        "plugin": ["opencode-gemini-auth@latest"],
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
      - **Documentation:** Always create/update a local `.md` plan file (e.g., `PLAN.md` or `todo.md`) and link to it, so the user can see/edit your thought process.
      - **Verification:** After editing code, **ALWAYS run the configured formatters/linters** (e.g., `prettier`, `ruff`, `gofmt` or `nixfmt`) to ensure standards.
      - **Subagents:** Use subagents for research and long-running tasks (like builds/test runs) to keep the main context clean.
      - **Style:** Do NOT use emojis in documentation or commit messages unless explicitly requested.

      ## Git & Commits
      - **Gists:** Always create **private/secret** gists. Never use `--public`.
      - **Atomic Commits:** Keep commits focused on a single logical change.
      - **Format:** Use **Conventional Commits** (`type(scope): message`).
        - Subject: Imperative mood, aim for <72 chars.
        - Body: Optional, explain the "why".
      - **Push:** `git push` immediately after committing.

      ## Specific Error Handling
      **File Edit Conflicts:**
      If you encounter "File has been modified since read", retry with exponential backoff:
      1. **Immediately** re-read and retry.
      2. **Wait 10s** -> re-read -> retry.
      3. **Wait 30s** -> re-read -> retry.
      4. **Wait 60s** -> re-read -> retry.
    '';
  };
}
