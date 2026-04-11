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

  # Impeccable — expose sub-skills at top-level so /skills can discover them.
  home.file.".copilot/skills/adapt" = {
    source = "${inputs.impeccable}/source/skills/adapt";
    recursive = true;
  };
  home.file.".copilot/skills/animate" = {
    source = "${inputs.impeccable}/source/skills/animate";
    recursive = true;
  };
  home.file.".copilot/skills/arrange" = {
    source = "${inputs.impeccable}/source/skills/arrange";
    recursive = true;
  };
  home.file.".copilot/skills/audit" = {
    source = "${inputs.impeccable}/source/skills/audit";
    recursive = true;
  };
  home.file.".copilot/skills/bolder" = {
    source = "${inputs.impeccable}/source/skills/bolder";
    recursive = true;
  };
  home.file.".copilot/skills/clarify" = {
    source = "${inputs.impeccable}/source/skills/clarify";
    recursive = true;
  };
  home.file.".copilot/skills/colorize" = {
    source = "${inputs.impeccable}/source/skills/colorize";
    recursive = true;
  };
  home.file.".copilot/skills/critique" = {
    source = "${inputs.impeccable}/source/skills/critique";
    recursive = true;
  };
  home.file.".copilot/skills/delight" = {
    source = "${inputs.impeccable}/source/skills/delight";
    recursive = true;
  };
  home.file.".copilot/skills/distill" = {
    source = "${inputs.impeccable}/source/skills/distill";
    recursive = true;
  };
  home.file.".copilot/skills/extract" = {
    source = "${inputs.impeccable}/source/skills/extract";
    recursive = true;
  };
  home.file.".copilot/skills/frontend-design" = {
    source = "${inputs.impeccable}/source/skills/frontend-design";
    recursive = true;
  };
  home.file.".copilot/skills/harden" = {
    source = "${inputs.impeccable}/source/skills/harden";
    recursive = true;
  };
  home.file.".copilot/skills/impeccable" = {
    source = "${inputs.impeccable}/source/skills/impeccable";
    recursive = true;
  };
  home.file.".copilot/skills/normalize" = {
    source = "${inputs.impeccable}/source/skills/normalize";
    recursive = true;
  };
  home.file.".copilot/skills/onboard" = {
    source = "${inputs.impeccable}/source/skills/onboard";
    recursive = true;
  };
  home.file.".copilot/skills/optimize" = {
    source = "${inputs.impeccable}/source/skills/optimize";
    recursive = true;
  };
  home.file.".copilot/skills/overdrive" = {
    source = "${inputs.impeccable}/source/skills/overdrive";
    recursive = true;
  };
  home.file.".copilot/skills/polish" = {
    source = "${inputs.impeccable}/source/skills/polish";
    recursive = true;
  };
  home.file.".copilot/skills/quieter" = {
    source = "${inputs.impeccable}/source/skills/quieter";
    recursive = true;
  };
  home.file.".copilot/skills/shape" = {
    source = "${inputs.impeccable}/source/skills/shape";
    recursive = true;
  };
  home.file.".copilot/skills/teach-impeccable" = {
    source = "${inputs.impeccable}/source/skills/teach-impeccable";
    recursive = true;
  };
  home.file.".copilot/skills/typeset" = {
    source = "${inputs.impeccable}/source/skills/typeset";
    recursive = true;
  };

  # Caveman — terse response mode plus focused commit/review helper skills
  home.file.".copilot/skills/caveman/SKILL.md".source = "${inputs.caveman}/skills/caveman/SKILL.md";
  home.file.".copilot/skills/caveman-commit/SKILL.md".source = "${inputs.caveman}/skills/caveman-commit/SKILL.md";
  home.file.".copilot/skills/caveman-review/SKILL.md".source = "${inputs.caveman}/skills/caveman-review/SKILL.md";
  home.file.".copilot/skills/caveman-compress/SKILL.md".source = "${inputs.caveman}/caveman-compress/SKILL.md";

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
