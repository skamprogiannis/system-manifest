# Antigravity Global Instructions

## Working environment and scope

This machine normally uses NixOS, Hyprland, Ghostty, Neovim, Bash, and Greek/US keyboard layouts. Use normal Hyprland terminal groups; tmux is optional for detachable or shared sessions. Prefer Linux-friendly, Bash-compatible commands.

- Read applicable repository `AGENTS.md` and `GEMINI.md` files before working. Local instructions take precedence over these global defaults.
- Keep global instructions useful across repositories. Put project architecture, build commands, troubleshooting, and deployment rules in the owning repository's instructions and guides.
- Use installed skills when they clearly match the task. Use their native discovery descriptions rather than maintaining a second catalog here. Impeccable is the default authority for frontend design; follow the project's established design system.

## Maintainer-facing prose and commits

- Keep conversation, prompt, and iteration history out of code comments, commit messages, PR descriptions, and other maintainer-facing prose unless explicitly requested. Describe the resulting behavior, constraints, and technical rationale.
- Write for a maintainer who has not read the conversation. Preserve useful explanations of tradeoffs and limitations.
- Make atomic commits, each containing one self-contained logical change. Use short Conventional Commit subjects: `type(scope): summary`, with an optional scope. Add a body only when it helps explain the change or its rationale.
- Do not add Copilot or other AI co-author trailers.

## Permissions and sandbox

- Keep native model, effort, speed, sandbox, and approval settings under user control. Instructions do not change an active model selection. Never attempt to circumvent the sandbox, and keep as much work inside the standard sandbox as possible.
- Existing authorization carries forward. Obtain explicit authorization for sensitive, privileged, destructive, or external-write actions when the user's request has not already authorized them. Clarify uncertain authority before acting.

## New projects

Use Spec Kit for substantial greenfield projects intended for ongoing development. Small experiments and throwaway prototypes may start directly. Honor an explicitly requested workflow. Use `/goal` only when the user requests a persistent goal.
