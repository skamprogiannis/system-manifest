# Maintainer Notes

Detailed development and troubleshooting rules for `system-manifest`. Agents should start with [AGENTS.md](../AGENTS.md); consult this guide when touching relevant code.

## Agent Tips

- **Session Info:** `/session` command.
- **Git & Gens:** Keep git commits atomic and descriptive.
- **Commit Format:** Use **Conventional Commits** (`type(scope): message`).
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  - Scopes: `desktop`, `usb`, `laptop`, `common`, `home`, `system`, or specific module names.
  - Example: `feat(desktop): enable steam and gamemode`
  - Example: `fix(usb): correct luks mounting path`
- **Worktree-First Git:** `/home/stefan/system-manifest` is the repo container; the bare Git dir lives at `/home/stefan/system-manifest/.bare`. Do not edit anything inside `.bare`.
  - Main worktree: `/home/stefan/system-manifest/main`
  - Create a feature worktree: `git --git-dir=/home/stefan/system-manifest/.bare worktree add /home/stefan/system-manifest/<dir> -b <branch> main`
  - Keep worktree directories as sanitized direct children (for example `usb-fix`), even when the branch name contains slashes such as `feature/usb-fix`
  - List active worktrees: `git --git-dir=/home/stefan/system-manifest/.bare worktree list`
  - Remove merged worktree: `git --git-dir=/home/stefan/system-manifest/.bare worktree remove /home/stefan/system-manifest/<dir>` and then `git --git-dir=/home/stefan/system-manifest/.bare branch -d <branch>`
  - Run all editing/build/git commands from the intended worktree path.
- **System Git:** Ensure `git` stays in `hosts/common/default.nix` under `environment.systemPackages` (required for Flakes).
- **Codex Instruction Source:** Repository-wide Codex defaults are edited in `modules/home/codex/instructions.md`, which is synced to `~/.codex/AGENTS.md` via Home Manager when you run `nixos-rebuild switch`.
- **Codex Upgrades:** Update the shared version in `modules/home/codex/version.txt` and the release hash in `modules/home/codex/default.nix`. The Bannerlord adapter must use that same version: keep its packaged preflight expectation, tests, and README consistent on every Codex upgrade. Run the `bannerlord-codex` and `script-smoke` checks before deployment; do not leave a separate stale version pin in the adapter.
- **Codex Package Layout:** Preserve the upstream release package, including `codex-package.json`, `bin/codex`, `bin/codex-code-mode-host`, `codex-path/rg`, and `codex-resources/bwrap`. Keep the direnv wrapper outside that package and execute its absolute `bin/codex` path. Verify actual daemon start, managed-package copy, version, and stop in isolated test state; `--version` and `exec` alone do not test interactive daemon startup.
- **Codex GUI Validation:** Test a private profile on the real desktop display with GPU rendering enabled. Headless Xvfb tests must isolate their socket directory and lock files from the desktop; auto-selecting a display in shared `/tmp` can remove live XWayland sockets when the test cannot see compositor PIDs.
- **Desktop Workspace Helper:** ChatGPT 26.1023.51421 bundles Node 24.22.1 for local task preparation. Patchelf 0.19.2 produces a crashing executable; the package restores only this binary after automatic fixups and applies the discovered interpreter/RPATH with 0.15.2. Keep its startup, child-execution and crypto install checks unconditional when changing either version. A healthy executor connection does not prove workspace preparation works.
- **Squash Fix Chains:** If you need multiple attempts to fix something, squash them into a single commit before pushing (`git rebase -i` or `git commit --amend`). Avoid pushing fix→fix→fix chains that clutter history.

- **Git Hygiene:** Always commit before `nixos-rebuild switch` so `nixos-rebuild list-generations` records a clean configuration revision for rollback and history tracking.
- **README Updates:** Update `README.md` with significant durable changes. Keep it high-level: document capabilities, workflows, and entrypoints, not transient UI behavior or implementation trivia.
- **Autonomy:** You are authorized to run `sudo nixos-rebuild switch --flake` autonomously when requested or implied by the workflow (e.g., "rebuild").
- **Revision Tracking:** Keep `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;` in `hosts/common/default.nix` so `nixos-rebuild list-generations` shows the commit hash.
- **Dry Run:** Always use `nixos-rebuild dry-build` before asking the user to build, especially for complex derivations.
- **Build Memory:** On constrained machines, run Nix commands sequentially with `--max-jobs 1 --cores 1` and monitor available RAM as well as disk space. Core limits reduce concurrency; they do not impose a memory ceiling.
- **Ghostty Package:** Use the stable package from system Nixpkgs so the terminal and graphics libraries share a package set. Its NixOS binary cache avoids development builds that can exceed local RAM even with one compiler worker.
- **Semgrep Compatibility:** Semgrep 1.180.0 retains MCP 1 because its frontend imports FastMCP. On x86_64 Linux, its core build uses patchelf 0.15.2 while stock patchelf is 0.19.2; newer patchers abort on that wheel's ELF layout. The ELF override preserves upstream strip/RPATH safeguards and expires when either version changes. The script smoke check scans local positive and clean fixtures through the installed frontend.
- **Codex Sandbox Nix:** If a Nix command fails inside Codex with `fetcher-cache-v*.sqlite` / `eval-cache-v*.sqlite` access errors or `cannot connect to socket at '/nix/var/nix/daemon-socket/socket': Operation not permitted`, treat it as sandboxing and rerun the same command with escalation instead of changing Nix config.
- **AppImages:** When wrapping AppImages with `appimageTools`, ensure common libraries like `webkitgtk`, `gtk4`, `libadwaita`, `graphene`, and `libsoup_3` are included in `extraPkgs` if the app has a GUI. Also include `gnome-themes-extra` and `gtk3` if theme errors occur.
- **Pear Runtime**: Apps like PearPass may take several minutes to load on the first run due to P2P network discovery.
- **Program Organization**: Organize `home.packages` in `home.nix` using clear comments for categories:
  - `GUI`: Desktop applications (Discord, Obsidian, etc.)
  - `CLI / Tools`: Command-line utilities and development tools.
  - `Disk Utilities`: Partitioning and file system tools.
  - `Fonts`: Icons and system fonts.
  - Keep each list alphabetical within its category for readability.
- **System Packages**: Only put essential bootstrap tools (like `git` if required by flakes for non-home-manager operations) in `hosts/common/default.nix`. Prefer `home.packages` for most user software.
- **Code Organization**: Modularize configurations into `modules/` (e.g., `modules/git.nix`, `modules/hyprland.nix`) to keep `home.nix` clean.
- **Comments**: Keep comments focused on "why" or "what" (e.g., "# Wrapper for native messaging"). Do NOT add meta-comments about your actions (e.g., "# I added this because user asked").
- **No Commented-Out Code**: Do not leave commented-out code blocks. Use git history if you need to revert or reference old code.

- **Rebuild Delegation:** When delegation is explicitly authorized or the session uses `codex-auto`, a bounded subagent may handle long rebuild validation. Plain `codex` handles it in the main session unless the user asks for delegation.
- **Bug Reporting:** Prioritize a reproduction test before attempting a fix, then verify it passes. Delegate bounded implementation or validation work only when delegation is authorized.
- **Pre-Completion Dry Build:** After any config/code change and before reporting "done," complete `nixos-rebuild dry-build --flake .#desktop` and fix any failures. Documentation-only changes need source and link review, without a system build.
- **CI Shape:** `checks/registry.nix` owns exported checks and CI lane/ownership metadata. GitHub Actions evaluates all hosts, selects checks conservatively from changed paths, shares one store for lightweight support checks, and serializes affected host builds with their installed-environment integrations. Weekly/manual runs validate the complete registry. Main selection includes changes since the last successful ancestor run; unknown paths or missing baselines select everything. Keep selector/result regression fixtures and check coverage in sync. Lightweight checks must consume exact packages/configuration artifacts rather than complete Home Manager environments; preserve assembled activation and final installation assertions in host integration checks.
- **ShellCheck Scope:** ShellCheck lints generated Home Manager shell entrypoints, host variants, extracted USB updater fragments, and standalone script fixtures registered in `checks/context.nix`. Register new shell sources there.
- **Deadnix Hygiene:** Run `deadnix` after significant Nix refactors, package sweeps, or module rewiring before committing. Treat it as an occasional cleanup check, not a required gate for tiny config edits.
- **Validation vs Deployment:** CI and `nix flake check` only validate buildability and scripted checks. Deployment is still manual: `nixos-rebuild switch --flake .#desktop` for desktop, `nixos-rebuild switch --flake .#laptop` for laptop, and `update-usb` for the USB image.

## Greenfield Projects: Spec Kit Workflow

Use **Spec Kit** (`specify` CLI) to scaffold spec-driven development for new projects. The Codex integration installs skills in `.agents/skills` and invokes them as `$speckit-*`.

- **Initialize a project:** `specify init <PROJECT_NAME> --integration codex` (run in the project directory)
- **Skills available after init:**
  - `$speckit-constitution` — Define guiding principles
  - `$speckit-specify` — Describe what to build
  - `$speckit-plan` — Generate an implementation plan
  - `$speckit-tasks` — Break down work into tasks
  - `$speckit-implement` — Trigger implementation workflow
- The `specify` binary is installed declaratively via a `uvx` wrapper — no manual installation needed.

## Known Issues / Fixes

- **Attribute Re-definition:** Nix doesn't allow defining the same attribute set key (like `home.file`) multiple times in the same file. You must merge them into a single block.

- **USB Tool Environments:** `setup-persistent-usb` and `update-usb` bootstrap their required Nix tool environments; use those commands directly. For manual disk operations, provide the required utilities, for example `sudo nix-shell -p gptfdisk parted cryptsetup dosfstools e2fsprogs util-linux --run '<command>'`.
- **Neovim Swap Files:** If Neovim throws an `E325: ATTENTION` error or fails to open a file from `neo-tree`, it is blocked by a `.swp` file. Do not try to debug the plugin. The solution is to delete `~/.local/state/nvim/swap/*`. (Swap files are globally disabled in `opts.swapfile = false`, but old ones may linger).
- **Zellij Stacking Action Name:** On Zellij `0.43.1`, `TogglePaneEmbedOrEject` is invalid and causes config parse failure. Use `TogglePaneEmbedOrFloating` instead.

For subsystem-specific requirements, also read [desktop maintenance](system.md#desktop-maintenance), [USB maintainer constraints](usb.md#maintainer-constraints), and [CI maintainer rules](ci.md#maintainer-rules).
