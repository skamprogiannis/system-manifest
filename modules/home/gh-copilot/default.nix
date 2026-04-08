{
  pkgs,
  inputs,
  ...
}: let
  pinchtabVersion = "0.8.6";
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
in {
  home.packages = [pinchtab];

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

  # --- Skills ---

  # Visual Explainer — generates HTML diagrams, diff reviews, plan reviews
  home.file.".copilot/skills/visual-explainer" = {
    source = "${inputs.visual-explainer}/plugins/visual-explainer";
    recursive = true;
  };

  # Technical Debt — codebase health analysis and refactoring roadmaps
  home.file.".copilot/skills/technical-debt/SKILL.md".source = ./skills/technical-debt/SKILL.md;

  # Browser Automation — PinchTab-based browser control for testing and scraping
  home.file.".copilot/skills/browser-automation/SKILL.md".source = ./skills/browser-automation/SKILL.md;

  # Impeccable — frontend design skill with 20 commands (audit, polish, typeset, etc.)
  # Deploys all skill directories from source/skills/ (frontend-design + 20 commands)
  home.file.".copilot/skills/impeccable" = {
    source = "${inputs.impeccable}/source/skills";
    recursive = true;
  };

  # --- Custom Agents ---

  # Plan Reviewer — structured 4-section plan review before implementation
  home.file.".copilot/agents/plan-reviewer.agent.md".source = ./agents/plan-reviewer.agent.md;

  # Security Reviewer — OWASP-focused security analysis for new code
  home.file.".copilot/agents/security-reviewer.agent.md".source = ./agents/security-reviewer.agent.md;

  # MCP servers — Context7 for library docs; GitHub MCP is built-in
  home.file.".copilot/mcp-config.json".text = builtins.toJSON {
    mcpServers = {
      context7 = {
        type = "stdio";
        command = "npx";
        args = ["-y" "@upstash/context7-mcp"];
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
    };
  };
}
