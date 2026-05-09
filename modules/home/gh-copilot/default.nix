{
  lib,
  pkgs,
  inputs,
  ...
}: let
  pinchtabVersion = "0.8.6";
  copilotSkillDir = source: {
    inherit source;
    force = true;
  };
  sanitizeSkillName = skillName: source:
    pkgs.runCommand "copilot-skill-${skillName}" {} ''
      cp -r ${source} "$out"
      chmod -R u+w "$out"
      ${pkgs.python3}/bin/python3 - <<'PY' "$out/SKILL.md" "${skillName}"
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
skill_name = sys.argv[2]
text = path.read_text()
text = re.sub(r"^name:\s*.*$", f"name: {skill_name}", text, count=1, flags=re.MULTILINE)
path.write_text(text)
PY
    '';
  uiUxSkill = skillName: source: copilotSkillDir (sanitizeSkillName skillName source);
  pinchtab = pkgs.stdenvNoCC.mkDerivation {
    pname = "pinchtab";
    version = pinchtabVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/pinchtab/pinchtab/releases/download/v${pinchtabVersion}/pinchtab-linux-amd64";
      sha256 = "1pmp2j8k0vzq8ml3bq0z7gfhcxx68qys5sb98d692xbn72r2c5sm";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/pinchtab"
    '';
    meta = {
      description = "Browser automation CLI for AI agents";
      homepage = "https://github.com/pinchtab/pinchtab";
      license = pkgs.lib.licenses.mit;
      mainProgram = "pinchtab";
      platforms = ["x86_64-linux"];
    };
  };
  staticAnalysisSkill = pkgs.runCommand "copilot-static-analysis-skill" {} ''
    mkdir -p "$out/references"
    cp ${./skills/static-analysis/SKILL.md} "$out/SKILL.md"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/README.md "$out/references/README.md"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/skills/codeql "$out/references/codeql"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/skills/semgrep "$out/references/semgrep"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/skills/sarif-parsing "$out/references/sarif-parsing"
  '';
  visualExplainerSkill = pkgs.runCommand "copilot-visual-explainer-skill" {} ''
    workdir="$(mktemp -d)"
    cp -r ${inputs.visual-explainer}/plugins/visual-explainer/. "$workdir/"
    chmod -R u+w "$workdir"
    ${pkgs.python3}/bin/python3 - <<'PY' "$workdir"
from pathlib import Path
import sys

root = Path(sys.argv[1])
old = "~/.agent/diagrams"
new = "~/.copilot/diagrams"

for path in root.rglob("*"):
    if not path.is_file():
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    if old not in text:
        continue
    path.write_text(text.replace(old, new))
PY
    mkdir -p "$out"
    cp -r "$workdir"/. "$out/"
  '';
in {
  home.packages = [
    pkgs.codeql
    pinchtab
    pkgs.python3Packages."sarif-tools"
    pkgs.semgrep
  ];

  # Ensure Copilot and gh open Neovim from any launcher context (shell, zellij, etc.)
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    GH_EDITOR = "nvim";
    NIXOS_OZONE_WL = "1";
  };

  # Source GH_TOKEN from file if present — enables auth on machines where gnome-keyring
  # may not auto-unlock (e.g., booting USB on a computer lab machine).
  # Create the file once: echo "ghp_..." > ~/.config/github-pat && chmod 600 ~/.config/github-pat
  programs.bash.initExtra = ''
    export EDITOR=nvim
    export VISUAL=nvim
    if [ -z "$GH_TOKEN" ] && [ -f "$HOME/.config/github-pat" ]; then
      export GH_TOKEN="$(cat "$HOME/.config/github-pat")"
    fi
  '';

  programs.gh = {
    settings = {
      editor = "nvim";
    };
  };

  # Global instructions — deployed to the path the Copilot CLI reads automatically
  home.file.".copilot/copilot-instructions.md".text = builtins.readFile ./instructions.md;
  home.file.".copilot/diagrams/.keep".text = "";

  # --- Skills ---

  # Visual Explainer — generates HTML diagrams, diff reviews, plan reviews
  home.file.".copilot/skills/visual-explainer" = copilotSkillDir visualExplainerSkill;

  # Technical Debt — codebase health analysis and refactoring roadmaps
  home.file.".copilot/skills/technical-debt/SKILL.md".source = ./skills/technical-debt/SKILL.md;

  # Browser Automation — PinchTab-based browser control for testing and scraping
  home.file.".copilot/skills/browser-automation/SKILL.md".source = ./skills/browser-automation/SKILL.md;

  # Static Analysis — compact wrapper around Trail of Bits CodeQL, Semgrep, and SARIF guidance
  home.file.".copilot/skills/static-analysis" = copilotSkillDir staticAnalysisSkill;

  # Impeccable — upstream now exposes a single GitHub Copilot skill bundle under `skill/`.
  home.file.".copilot/skills/impeccable" = copilotSkillDir "${inputs.impeccable}/skill";

  # UI/UX Pro Max — expose the upstream design skill pack and companion skills.
  home.file.".copilot/skills/banner-design" = uiUxSkill "banner-design" "${inputs.ui-ux-pro-max}/.claude/skills/banner-design";
  home.file.".copilot/skills/brand" = uiUxSkill "brand" "${inputs.ui-ux-pro-max}/.claude/skills/brand";
  home.file.".copilot/skills/design" = uiUxSkill "design" "${inputs.ui-ux-pro-max}/.claude/skills/design";
  home.file.".copilot/skills/design-system" = uiUxSkill "design-system" "${inputs.ui-ux-pro-max}/.claude/skills/design-system";
  home.file.".copilot/skills/slides" = uiUxSkill "slides" "${inputs.ui-ux-pro-max}/.claude/skills/slides";
  home.file.".copilot/skills/ui-styling" = uiUxSkill "ui-styling" "${inputs.ui-ux-pro-max}/.claude/skills/ui-styling";
  home.file.".copilot/skills/ui-ux-pro-max" = uiUxSkill "ui-ux-pro-max" "${inputs.ui-ux-pro-max}/.claude/skills/ui-ux-pro-max";

  # Caveman — terse response mode plus focused commit/review helper skills
  home.file.".copilot/skills/caveman/SKILL.md".source = "${inputs.caveman}/skills/caveman/SKILL.md";
  home.file.".copilot/skills/caveman-commit/SKILL.md".source = "${inputs.caveman}/skills/caveman-commit/SKILL.md";
  home.file.".copilot/skills/caveman-review/SKILL.md".source = "${inputs.caveman}/skills/caveman-review/SKILL.md";
  home.file.".copilot/skills/caveman-compress/SKILL.md".source = "${inputs.caveman}/caveman-compress/SKILL.md";

  # Matt Pocock skills — architecture, TDD, triage, and design helpers
  home.file.".copilot/skills/design-an-interface" = copilotSkillDir "${inputs.mattpocock-skills}/design-an-interface";
  home.file.".copilot/skills/improve-codebase-architecture" = copilotSkillDir "${inputs.mattpocock-skills}/improve-codebase-architecture";
  home.file.".copilot/skills/tdd" = copilotSkillDir "${inputs.mattpocock-skills}/tdd";
  home.file.".copilot/skills/triage-issue" = copilotSkillDir "${inputs.mattpocock-skills}/triage-issue";
  home.file.".copilot/skills/zoom-out" = copilotSkillDir "${inputs.mattpocock-skills}/zoom-out";

  # --- Custom Agents ---

  # Plan Reviewer — structured 4-section plan review before implementation
  home.file.".copilot/agents/plan-reviewer.agent.md".source = ./agents/plan-reviewer.agent.md;

  # Security Reviewer — OWASP-focused security analysis for new code
  home.file.".copilot/agents/security-reviewer.agent.md".source = ./agents/security-reviewer.agent.md;

  home.activation.cleanupCopilotSkillBackups = lib.hm.dag.entryAfter ["writeBoundary"] ''
    skills_dir="$HOME/.copilot/skills"
    if [ -d "$skills_dir" ]; then
      while IFS= read -r -d $'\0' backup_path; do
        echo "Removing stale Copilot skill backup $backup_path"
        ${pkgs.coreutils}/bin/chmod -R u+w "$backup_path"
        ${pkgs.coreutils}/bin/rm -rf "$backup_path"
      done < <(${pkgs.findutils}/bin/find "$skills_dir" -mindepth 1 -maxdepth 1 -name '*.backup' -print0)
    fi
  '';

  # MCP servers — Context7 for library docs; GitHub MCP is built-in
  home.file.".copilot/mcp-config.json".text = builtins.toJSON {
    mcpServers = {
      context7 = {
        type = "stdio";
        command = "npx";
        args = ["-y" "@upstash/context7-mcp"];
      };
      etsy = {
        type = "http";
        url = "https://mcp.api.etsycloud.com/mcp";
      };
    };
  };

  # LSP servers — binaries must be installed separately (see home.nix packages)
  home.file.".copilot/lsp-config.json".text = builtins.toJSON {
    lspServers = {
      gopls = {
        command = "gopls";
        fileExtensions = {".go" = "go";};
      };
      typescript-language-server = {
        command = "typescript-language-server";
        args = ["--stdio"];
        fileExtensions = {
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
        };
      };
      pylsp = {
        command = "pylsp";
        fileExtensions = {".py" = "python";};
      };
      rust-analyzer = {
        command = "rust-analyzer";
        fileExtensions = {".rs" = "rust";};
      };
      omnisharp = {
        command = "OmniSharp";
        args = ["--languageserver"];
        fileExtensions = {".cs" = "csharp";};
      };
      nil = {
        command = "nil";
        fileExtensions = {".nix" = "nix";};
      };
    };
  };
}
