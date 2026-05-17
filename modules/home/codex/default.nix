{
  lib,
  pkgs,
  inputs,
  ...
}: let
  codexVersion = "0.130.0";
  codexUpstream = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex-cli";
    version = codexVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-Fneee3hXUIp2ijbX1OCE7sM27COUbtcKmwlIm4+GEZA=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out/bin"
      tar -xzf "$src" -C "$out/bin"
      mv "$out/bin/codex-x86_64-unknown-linux-musl" "$out/bin/upstream-codex"
      chmod 755 "$out/bin/upstream-codex"
    '';
    meta = with lib; {
      description = "OpenAI Codex CLI";
      homepage = "https://github.com/openai/codex";
      license = licenses.asl20;
      mainProgram = "codex";
      platforms = ["x86_64-linux"];
      sourceProvenance = with sourceTypes; [binaryNativeCode];
    };
  };
  codexCli = pkgs.symlinkJoin {
    name = "codex-cli-wrapped";
    paths = [codexUpstream];
    postBuild = ''
      rm -f "$out/bin/codex"
      cat > "$out/bin/codex" <<'EOF'
      #!${pkgs.bash}/bin/bash
      if [[ -z "$GH_TOKEN" && -f "$HOME/.config/github-pat" ]]; then
        export GH_TOKEN="$(<"$HOME/.config/github-pat")"
      fi

      # Start Codex from a clean shell instead of inheriting repo dev-shell state.
      if [[ -n "''${DIRENV_DIFF:-}" || -n "''${DIRENV_DIR:-}" ]]; then
        original_pwd="$PWD"
        if ! cd "$HOME"; then
          echo "failed to switch to \$HOME while unloading direnv state" >&2
          exit 1
        fi
        if ! direnv_exports="$(${pkgs.direnv}/bin/direnv export bash 2>/dev/null)"; then
          echo "failed to unload inherited direnv state before starting codex" >&2
          exit 1
        fi
        eval "$direnv_exports"
        if ! cd "$original_pwd"; then
          echo "failed to restore working directory after unloading direnv state" >&2
          exit 1
        fi
      fi

      exec "$(dirname "$0")/upstream-codex" "$@"
      EOF
      chmod +x "$out/bin/codex"
    '';
  };
  pinchtabVersion = "0.8.6";
  skillDir = source: {
    inherit source;
    force = true;
  };
  sanitizeSkillName = skillName: source:
    pkgs.runCommand "codex-skill-${skillName}" {} ''
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
  uiUxSkill = skillName: source: skillDir (sanitizeSkillName skillName source);
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
  staticAnalysisSkill = pkgs.runCommand "codex-static-analysis-skill" {} ''
    mkdir -p "$out/references"
    cp ${./skills/static-analysis/SKILL.md} "$out/SKILL.md"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/README.md "$out/references/README.md"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/skills/codeql "$out/references/codeql"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/skills/semgrep "$out/references/semgrep"
    ln -s ${inputs.trailofbits-skills}/plugins/static-analysis/skills/sarif-parsing "$out/references/sarif-parsing"
  '';
  visualExplainerSkill = pkgs.runCommand "codex-visual-explainer-skill" {} ''
        workdir="$(mktemp -d)"
        cp -r ${inputs.visual-explainer}/plugins/visual-explainer/. "$workdir/"
        chmod -R u+w "$workdir"
        ${pkgs.python3}/bin/python3 - <<'PY' "$workdir"
    from pathlib import Path
    import sys

    root = Path(sys.argv[1])
    replacements = {
        "~/.agent/diagrams": "~/.codex/diagrams",
        "~/.copilot/diagrams": "~/.codex/diagrams",
    }

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        for old, new in replacements.items():
            text = text.replace(old, new)
        path.write_text(text)
    PY
        mkdir -p "$out"
        cp -r "$workdir"/. "$out/"
  '';
in {
  home.packages = [
    pkgs.bubblewrap
    codexCli
    pkgs.codeql
    pinchtab
    pkgs.python3Packages."sarif-tools"
    pkgs.semgrep
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    GH_EDITOR = "nvim";
    NIXOS_OZONE_WL = "1";
  };

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

  home.file.".codex/AGENTS.md".text = builtins.readFile ./instructions.md;
  home.file.".codex/diagrams/.keep".text = "";
  home.file.".codex/config.toml".text = ''
    model = "gpt-5.5"
    model_reasoning_effort = "high"
    plan_mode_reasoning_effort = "xhigh"
    approval_policy = "on-request"
    sandbox_mode = "workspace-write"
    cli_auth_credentials_store = "file"
    suppress_unstable_features_warning = true

    [tui]
    vim_mode_default = true

    [projects."/home/stefan/system-manifest"]
    trust_level = "trusted"

    [features]
    goals = true
    multi_agent = true
    plugins = true

    [mcp_servers.context7]
    command = "npx"
    args = ["-y", "@upstash/context7-mcp"]

    [mcp_servers.etsy]
    url = "https://mcp.api.etsycloud.com/mcp"

    [mcp_servers.openaiDeveloperDocs]
    url = "https://developers.openai.com/mcp"
  '';

  # --- Skills ---

  home.file.".agents/skills/visual-explainer" = skillDir visualExplainerSkill;
  home.file.".agents/skills/technical-debt/SKILL.md".source = ./skills/technical-debt/SKILL.md;
  home.file.".agents/skills/browser-automation/SKILL.md".source = ./skills/browser-automation/SKILL.md;
  home.file.".agents/skills/static-analysis" = skillDir staticAnalysisSkill;
  home.file.".agents/skills/impeccable" = skillDir "${inputs.impeccable}/skill";

  home.file.".agents/skills/banner-design" = uiUxSkill "banner-design" "${inputs.ui-ux-pro-max}/.claude/skills/banner-design";
  home.file.".agents/skills/brand" = uiUxSkill "brand" "${inputs.ui-ux-pro-max}/.claude/skills/brand";
  home.file.".agents/skills/design" = uiUxSkill "design" "${inputs.ui-ux-pro-max}/.claude/skills/design";
  home.file.".agents/skills/design-system" = uiUxSkill "design-system" "${inputs.ui-ux-pro-max}/.claude/skills/design-system";
  home.file.".agents/skills/slides" = uiUxSkill "slides" "${inputs.ui-ux-pro-max}/.claude/skills/slides";
  home.file.".agents/skills/ui-styling" = uiUxSkill "ui-styling" "${inputs.ui-ux-pro-max}/.claude/skills/ui-styling";
  home.file.".agents/skills/ui-ux-pro-max" = uiUxSkill "ui-ux-pro-max" "${inputs.ui-ux-pro-max}/.claude/skills/ui-ux-pro-max";

  home.file.".agents/skills/caveman/SKILL.md".source = "${inputs.caveman}/skills/caveman/SKILL.md";
  home.file.".agents/skills/caveman-commit/SKILL.md".source = "${inputs.caveman}/skills/caveman-commit/SKILL.md";
  home.file.".agents/skills/caveman-review/SKILL.md".source = "${inputs.caveman}/skills/caveman-review/SKILL.md";
  home.file.".agents/skills/caveman-compress/SKILL.md".source = "${inputs.caveman}/caveman-compress/SKILL.md";

  home.file.".agents/skills/design-an-interface" = skillDir "${inputs.mattpocock-skills}/design-an-interface";
  home.file.".agents/skills/improve-codebase-architecture" = skillDir "${inputs.mattpocock-skills}/improve-codebase-architecture";
  home.file.".agents/skills/tdd" = skillDir "${inputs.mattpocock-skills}/tdd";
  home.file.".agents/skills/triage-issue" = skillDir "${inputs.mattpocock-skills}/triage-issue";
  home.file.".agents/skills/zoom-out" = skillDir "${inputs.mattpocock-skills}/zoom-out";

  # --- Custom Agents ---

  home.file.".codex/agents/plan-reviewer.toml".text = builtins.readFile ./agents/plan-reviewer.toml;
  home.file.".codex/agents/security-reviewer.toml".text = builtins.readFile ./agents/security-reviewer.toml;
}
