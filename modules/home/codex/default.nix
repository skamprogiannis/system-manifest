{
  lib,
  pkgs,
  inputs,
  ...
}: let
  codexVersion = "0.144.1";
  codexUpstream = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex-cli";
    version = codexVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-hAka4gxl/MfUEg25fRvVfX/435x2Cft4HHjC671PWig=";
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
  pinchtabVersion = "0.14.1";
  skillDir = source: {
    inherit source;
    force = true;
  };
  sanitizeSkill = skillName: description: source:
    pkgs.runCommand "codex-skill-${skillName}" {} ''
            cp -r ${source} "$out"
            chmod -R u+w "$out"
            if [ ! -f "$out/SKILL.md" ] && [ -f "$out/SKILL.src.md" ]; then
              cp "$out/SKILL.src.md" "$out/SKILL.md"
            fi
            ${pkgs.python3}/bin/python3 - "$out/SKILL.md" ${lib.escapeShellArg skillName} ${lib.escapeShellArg description} <<'PY'
      from pathlib import Path
      import json
      import re
      import sys

      path = Path(sys.argv[1])
      skill_name = sys.argv[2]
      description = sys.argv[3]
      text = path.read_text()
      if not text.startswith("---"):
          path.write_text(text)
          raise SystemExit

      end = text.find("\n---", 3)
      if end == -1:
          path.write_text(text)
          raise SystemExit

      frontmatter = text[4:end].splitlines()
      body = text[end + 4:]
      out = []
      skip_description_continuation = False
      wrote_description = False

      for line in frontmatter:
          is_key = re.match(r"^[A-Za-z0-9_-]+:", line) is not None
          if skip_description_continuation and not is_key:
              continue
          skip_description_continuation = False

          if line.startswith("name:"):
              out.append(f"name: {skill_name}")
          elif line.startswith("description:"):
              out.append(f"description: {json.dumps(description)}")
              wrote_description = True
              skip_description_continuation = True
          else:
              out.append(line)

      if not wrote_description:
          insert_at = 1 if out and out[0].startswith("name:") else 0
          out.insert(insert_at, f"description: {json.dumps(description)}")

      path.write_text("---\n" + "\n".join(out) + "\n---" + body)
      PY
    '';
  mkSkill = name: source: description: {
    inherit name source description;
  };
  skillHomeFile = skill: {
    name = ".agents/skills/${skill.name}";
    value = skillDir (sanitizeSkill skill.name skill.description skill.source);
  };
  skillConfig = skill: ''
    [[skills.config]]
    path = "/home/stefan/.agents/skills/${skill.name}"
    enabled = true
  '';
  pinchtab = pkgs.stdenvNoCC.mkDerivation {
    pname = "pinchtab";
    version = pinchtabVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/pinchtab/pinchtab/releases/download/v${pinchtabVersion}/pinchtab-linux-amd64";
      hash = "sha256-+UM7p4ZGdX7zkLpywY4mNgM3BQY1wd26Rx+xGnLFcSI=";
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
  pinchtabConfigSeed = pkgs.writeText "pinchtab-config.json" (builtins.toJSON {
    configVersion = "0.8.0";
    server = {
      port = "";
      bind = "";
      token = "";
      stateDir = "/home/stefan/.pinchtab";
      engine = "full";
    };
    browser = {
      version = "";
      binary = "${pkgs.brave}/bin/brave";
      extraFlags = "";
      extensionPaths = [];
    };
    instanceDefaults = {
      mode = "headless";
      noRestore = false;
      timezone = "";
      blockImages = null;
      blockMedia = null;
      blockAds = null;
      maxTabs = 20;
      maxParallelTabs = null;
      userAgent = "";
      noAnimations = null;
      stealthLevel = "light";
      tabEvictionPolicy = "close_lru";
    };
    security = {
      allowEvaluate = true;
      allowMacro = null;
      allowScreencast = null;
      allowDownload = null;
      downloadAllowedDomains = [];
      downloadMaxBytes = null;
      allowUpload = true;
      allowClipboard = null;
      uploadMaxRequestBytes = null;
      uploadMaxFiles = null;
      uploadMaxFileBytes = null;
      uploadMaxTotalBytes = null;
      maxRedirects = null;
      trustedProxyCIDRs = [];
      attach = {
        enabled = null;
        allowHosts = [];
        allowSchemes = [];
      };
      idpi = {
        enabled = false;
        allowedDomains = [];
        strictMode = false;
        scanContent = false;
        wrapContent = false;
        customPatterns = [];
        scanTimeoutSec = 0;
        shieldThreshold = 0;
      };
    };
    profiles = {
      baseDir = "/home/stefan/.pinchtab/profiles";
      defaultProfile = "default";
    };
    multiInstance = {
      strategy = "always-on";
      allocationPolicy = "fcfs";
      instancePortStart = null;
      instancePortEnd = null;
      restart = {
        maxRestarts = null;
        initBackoffSec = null;
        maxBackoffSec = null;
        stableAfterSec = null;
      };
    };
    timeouts = {
      actionSec = 0;
      navigateSec = 0;
      shutdownSec = 0;
      waitNavMs = 0;
    };
    scheduler = {
      enabled = null;
      strategy = "";
      maxQueueSize = null;
      maxPerAgent = null;
      maxInflight = null;
      maxPerAgentInflight = null;
      resultTTLSec = null;
      workerCount = null;
    };
    observability = {
      activity = {
        enabled = null;
        sessionIdleSec = null;
        retentionDays = null;
      };
    };
  });
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
  declarativeSkills = [
    (mkSkill "visual-explainer" visualExplainerSkill "Generate visual diagrams and HTML explainers for architecture, plans, diffs, and complex tables.")
    (mkSkill "technical-debt" ./skills/technical-debt "Audit code health, quantify technical debt, and produce focused refactoring roadmaps.")
    (mkSkill "browser-automation" ./skills/browser-automation "Control Chrome with PinchTab for web UI testing, scraping, form filling, and browser workflows.")
    (mkSkill "static-analysis" staticAnalysisSkill "Run scanner-backed security analysis with CodeQL, Semgrep, and SARIF interpretation.")
    (mkSkill "impeccable" "${inputs.impeccable}/skill" "Design, audit, and polish frontend interfaces, layouts, typography, motion, and UX details.")
    (mkSkill "banner-design" "${inputs.ui-ux-pro-max}/.claude/skills/banner-design" "Design polished banners for social, ads, website heroes, and print.")
    (mkSkill "brand" "${inputs.ui-ux-pro-max}/.claude/skills/brand" "Work on brand voice, identity, messaging, style guides, and brand consistency.")
    (mkSkill "design" "${inputs.ui-ux-pro-max}/.claude/skills/design" "Create brand, UI, logo, icon, banner, slide, and social design assets.")
    (mkSkill "design-system" "${inputs.ui-ux-pro-max}/.claude/skills/design-system" "Define design tokens, component specs, and systematic UI foundations.")
    (mkSkill "slides" "${inputs.ui-ux-pro-max}/.claude/skills/slides" "Create strategic HTML presentations with charts, design tokens, and responsive layouts.")
    (mkSkill "ui-styling" "${inputs.ui-ux-pro-max}/.claude/skills/ui-styling" "Build accessible Tailwind and shadcn-style UI components and visual systems.")
    (mkSkill "ui-ux-pro-max" "${inputs.ui-ux-pro-max}/.claude/skills/ui-ux-pro-max" "Plan, build, review, and polish UI/UX across web and mobile product surfaces.")
    (mkSkill "caveman" "${inputs.caveman}/skills/caveman" "Use terse caveman-mode responses with technical accuracy and minimal filler.")
    (mkSkill "caveman-commit" "${inputs.caveman}/skills/caveman-commit" "Generate terse Conventional Commit messages in caveman style.")
    (mkSkill "caveman-review" "${inputs.caveman}/skills/caveman-review" "Produce compact code review findings in caveman style.")
    (mkSkill "caveman-compress" "${inputs.caveman}/skills/caveman-compress" "Compress text aggressively while preserving technical meaning.")
    (mkSkill "diagnose" "${inputs.mattpocock-skills}/skills/engineering/diagnosing-bugs" "Use a disciplined reproduce-minimize-hypothesize-instrument-fix loop for bugs and regressions.")
    (mkSkill "grill-with-docs" "${inputs.mattpocock-skills}/skills/engineering/grill-with-docs" "Stress-test a plan against project docs, domain language, and recorded decisions.")
    (mkSkill "triage" "${inputs.mattpocock-skills}/skills/engineering/triage" "Triage issues through the configured issue tracker and triage role workflow.")
    (mkSkill "improve-codebase-architecture" "${inputs.mattpocock-skills}/skills/engineering/improve-codebase-architecture" "Find architectural refactoring opportunities that improve testability and navigation.")
    (mkSkill "setup-matt-pocock-skills" "${inputs.mattpocock-skills}/skills/engineering/setup-matt-pocock-skills" "Set up project context for Matt Pocock engineering skills.")
    (mkSkill "tdd" "${inputs.mattpocock-skills}/skills/engineering/tdd" "Use red-green-refactor test-driven development for features and bug fixes.")
    (mkSkill "to-issues" "${inputs.mattpocock-skills}/skills/engineering/to-tickets" "Break plans, specs, or PRDs into independently grabbable implementation issues.")
    (mkSkill "to-prd" "${inputs.mattpocock-skills}/skills/engineering/to-spec" "Turn current context into a PRD for the project issue tracker.")
    (mkSkill "zoom-out" "${inputs.mattpocock-skills}/skills/engineering/wayfinder" "Step up a level and map unfamiliar code areas, modules, and callers.")
    (mkSkill "prototype" "${inputs.mattpocock-skills}/skills/engineering/prototype" "Build a throwaway prototype to validate data, state, or UI design choices.")
  ];
  skillHomeFiles = builtins.listToAttrs (map skillHomeFile declarativeSkills);
  skillConfigToml = lib.concatMapStringsSep "\n" skillConfig declarativeSkills;
  codexConfigPython = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  context7Mcp = pkgs.writeShellScriptBin "context7-mcp" ''
    api_key="''${CONTEXT7_API_KEY:-}"
    if [ -z "$api_key" ] && [ -r "$HOME/.config/context7/api-key" ]; then
      api_key="$(${pkgs.coreutils}/bin/head -n 1 "$HOME/.config/context7/api-key")"
    fi

    if [ -n "$api_key" ]; then
      exec ${pkgs.nodejs}/bin/npx -y @upstash/context7-mcp --api-key "$api_key"
    fi

    exec ${pkgs.nodejs}/bin/npx -y @upstash/context7-mcp
  '';
  codexConfigText = ''
    model = "gpt-5.6-terra"
    model_reasoning_effort = "high"
    plan_mode_reasoning_effort = "xhigh"
    approval_policy = "on-request"
    sandbox_mode = "workspace-write"
    cli_auth_credentials_store = "file"
    suppress_unstable_features_warning = true

    [tui]
    notifications = ["agent-turn-complete", "approval-requested"]
    notification_method = "bel"
    notification_condition = "always"
    vim_mode_default = true

    [projects."/home/stefan/system-manifest"]
    trust_level = "trusted"

    [features]
    goals = true
    experimental_use_rmcp_client = true
    multi_agent = true
    plugins = true

    ${skillConfigToml}

    [mcp_servers.context7]
    command = "${context7Mcp}/bin/context7-mcp"

    [mcp_servers.etsy]
    url = "https://mcp.api.etsycloud.com/mcp"

    [mcp_servers.linear]
    url = "https://mcp.linear.app/mcp"

    [mcp_servers.openaiDeveloperDocs]
    url = "https://developers.openai.com/mcp"
  '';
  codexConfigSeed = pkgs.writeText "codex-config.toml" codexConfigText;
  codexConfigMerger = pkgs.writeTextFile {
    name = "merge-codex-config";
    destination = "/bin/merge-codex-config";
    executable = true;
    text = ''
      #!${codexConfigPython}/bin/python3
      ${builtins.readFile ./merge-config.py}
    '';
  };
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
  '';

  programs.gh = {
    settings = {
      editor = "nvim";
    };
  };

  home.file =
    skillHomeFiles
    // {
      ".codex/AGENTS.md".text = builtins.readFile ./instructions.md;
      ".codex/diagrams/.keep".text = "";

      ".codex/agents/plan-reviewer.toml".text = builtins.readFile ./agents/plan-reviewer.toml;
      ".codex/agents/security-reviewer.toml".text = builtins.readFile ./agents/security-reviewer.toml;
    };

  home.activation.ensureWritableCodexDirectory = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    codex_dir="$HOME/.codex"
    if [ -L "$codex_dir" ]; then
      codex_target="$(readlink -f "$codex_dir" 2>/dev/null || true)"
      case "$codex_target" in
        "" | /nix/store/*)
          run rm -f "$codex_dir"
          ;;
      esac
    fi
    run mkdir -p "$codex_dir"
  '';

  home.activation.ensureWritableCodexConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
    run mkdir -p "$HOME/.codex"
    run ${codexConfigMerger}/bin/merge-codex-config ${codexConfigSeed} "$HOME/.codex/config.toml"
  '';

  home.activation.ensurePinchTabConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
    pinchtab_dir="$HOME/.pinchtab"
    pinchtab_config="$pinchtab_dir/config.json"
    legacy_current_tab="$HOME/.local/state/pinchtab/current-tab"

    run mkdir -p "$pinchtab_dir"

    existing_token=""
    if [ -f "$pinchtab_config" ]; then
      existing_token="$(${pkgs.jq}/bin/jq -r '.server.token // ""' "$pinchtab_config" 2>/dev/null || true)"
    fi

    tmp_file="$(mktemp)"
    cp ${pinchtabConfigSeed} "$tmp_file"
    if [ -n "$existing_token" ]; then
      tmp_patch="$(mktemp)"
      ${pkgs.jq}/bin/jq --arg token "$existing_token" '.server.token = $token' "$tmp_file" > "$tmp_patch"
      mv "$tmp_patch" "$tmp_file"
    fi
    run install -m 600 "$tmp_file" "$pinchtab_config"
    rm -f "$tmp_file"

    if [ -f "$legacy_current_tab" ]; then
      current_tab="$(sed -n '1p' "$legacy_current_tab" 2>/dev/null || true)"
      case "$current_tab" in
        lite-*) run rm -f "$legacy_current_tab" ;;
      esac
    fi
  '';
}
