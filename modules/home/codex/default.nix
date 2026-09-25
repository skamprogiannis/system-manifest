{
  lib,
  pkgs,
  inputs,
  ...
}: let
  codexVersion = lib.removeSuffix "\n" (builtins.readFile ./version.txt);
  codexUpstream = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex-cli";
    version = codexVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-BC+FHqP8EIPEUVdSBSCUT8eQYytT68WA/JjqylWGKiU=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out"
      tar -xzf "$src" -C "$out"
      test -f "$out/codex-package.json"
      test -x "$out/bin/codex"
      test -x "$out/bin/codex-code-mode-host"
      test -x "$out/codex-path/rg"
      test -x "$out/codex-resources/bwrap"
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

      exec ${codexUpstream}/bin/codex "$@"
      EOF
      chmod +x "$out/bin/codex"
    '';
  };
  pinchtabVersion = "0.15.2";
  skillDir = source: {
    inherit source;
    force = true;
  };
  explicitSkill = skillName: source:
    pkgs.runCommand "codex-explicit-skill-${skillName}" {} ''
      cp -r ${source} "$out"
      chmod -R u+w "$out"
      mkdir -p "$out/agents"
      cat > "$out/agents/openai.yaml" <<'EOF'
      policy:
        allow_implicit_invocation: false
      EOF
    '';
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
      if skill_name == "code-review":
          body = body.replace(
              "The issue tracker should have been provided to you. If `docs/agents/issue-tracker.md` is missing, tell the user to run `/setup-matt-pocock-skills`.",
              "Issue-tracker configuration is optional. Discover specs from the user, commits, and repository files; if none is available, continue with the Standards axis and report that the Spec axis was unavailable.",
          )
          body = body.replace(
              "fetched via the workflow in `docs/agents/issue-tracker.md`.",
              "when a configured tracker integration is available.",
          )
      if skill_name == "tdd":
          body = body.replace(
              'call the Skill tool with "codebase-design" for the vocabulary.',
              'read the installed `codebase-design` skill for the vocabulary.',
          )
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
    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [pkgs.glibc];
    src = pkgs.fetchurl {
      url = "https://github.com/pinchtab/pinchtab/releases/download/v${pinchtabVersion}/pinchtab-linux-amd64";
      hash = "sha256-C7T5ehyS+UvNut/8OdxphaR1fIineHa7y0IUIZHoIC0=";
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
  jevMcpPackage = pkgs.buildNpmPackage {
    pname = "jev-mcp";
    version = "0.1.0";
    src = inputs.jev-mcp;
    npmDepsHash = "sha256-jOeluW+VO2AFtbqLBW8NJIWfGDSv3ozFSzMaPsTqnHA=";
    npmBuildScript = "build";
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      writable_npm_cache="$TMPDIR/jev-mcp-npm-cache"
      cp -a "$npm_config_cache" "$writable_npm_cache"
      chmod -R u+w "$writable_npm_cache"
      export npm_config_cache="$writable_npm_cache"
      npm test
      npm run typecheck
      npm run test:package
      runHook postCheck
    '';
  };
  jevMcp = pkgs.writeShellScriptBin "jev-mcp" ''
    api_key="''${TYPESAFE_API_KEY:-}"
    if [ -z "$api_key" ] && [ -r "$HOME/.config/typesafe/api-key" ]; then
      api_key="$(${pkgs.coreutils}/bin/head -n 1 "$HOME/.config/typesafe/api-key")"
    fi

    if [ -n "$api_key" ]; then
      export TYPESAFE_API_KEY="$api_key"
    fi
    export JEV_MCP_MODEL="jev-1.13"
    exec ${jevMcpPackage}/bin/jev-mcp "$@"
  '';
  jevShadowRoute = pkgs.writeShellScriptBin "jev-shadow-route" ''
    exec ${pkgs.python3}/bin/python3 ${./jev-shadow-route.py} "$@"
  '';
  jevMcpSkill = pkgs.runCommand "codex-jev-mcp-skill" {} ''
    cp -r ${inputs.jev-mcp}/skills/jev-mcp "$out"
    chmod -R u+w "$out"
    mkdir -p "$out/references"
    cp ${inputs.jev-mcp}/docs/tools.md "$out/references/tools.md"
    substituteInPlace "$out/SKILL.md" --replace-fail "../../docs/tools.md" "references/tools.md"
    cat ${./jev-shadow-routing.md} >> "$out/SKILL.md"
  '';
  pinchtabConfigSeed = pkgs.writeText "pinchtab-config.json" (builtins.toJSON {
    configVersion = "0.8.0";
    server = {
      port = "";
      bind = "";
      token = "";
      stateDir = "/home/stefan/.pinchtab";
    };
    browsers.default = "chrome";
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
      allowEvaluate = false;
      allowMacro = false;
      allowScreencast = false;
      allowDownload = false;
      downloadAllowedDomains = [];
      downloadMaxBytes = null;
      allowUpload = false;
      allowClipboard = false;
      allowCookies = false;
      allowStateExport = false;
      allowNetworkIntercept = false;
      allowFileScheme = false;
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
        enabled = true;
        allowedDomains = [];
        strictMode = false;
        scanContent = true;
        wrapContent = true;
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
    (mkSkill "browser-automation" "${inputs.pinchtab-src}/plugins/grok/skills/pinchtab" "Control Chrome with PinchTab for web UI testing, scraping, form filling, and browser workflows.")
    (mkSkill "static-analysis" staticAnalysisSkill "Run scanner-backed security analysis with CodeQL, Semgrep, and SARIF interpretation.")
    (mkSkill "impeccable" "${inputs.impeccable}/.agents/skills/impeccable" "Design, audit, and polish frontend interfaces, layouts, typography, motion, and UX details.")
    (mkSkill "caveman" "${inputs.caveman}/skills/caveman" "Use terse caveman-mode responses with technical accuracy and minimal filler.")
    (mkSkill "caveman-commit" "${inputs.caveman}/skills/caveman-commit" "Generate terse Conventional Commit messages in caveman style.")
    (mkSkill "caveman-review" "${inputs.caveman}/skills/caveman-review" "Produce compact code review findings in caveman style.")
    (mkSkill "diagnose" "${inputs.mattpocock-skills}/skills/engineering/diagnosing-bugs" "Use a disciplined reproduce-minimize-hypothesize-instrument-fix loop for bugs and regressions.")
    (mkSkill "grilling" "${inputs.mattpocock-skills}/skills/productivity/grilling" "Grill users one decision at a time to stress-test plans and designs.")
    (mkSkill "domain-modeling" "${inputs.mattpocock-skills}/skills/engineering/domain-modeling" "Build and sharpen a project's domain vocabulary and architectural decisions.")
    (mkSkill "codebase-design" "${inputs.mattpocock-skills}/skills/engineering/codebase-design" "Design deep modules with small interfaces, clean seams, and testable implementations.")
    (mkSkill "code-review" "${inputs.mattpocock-skills}/skills/engineering/code-review" "Review changes against repository standards and the originating specification.")
    (mkSkill "tdd" "${inputs.mattpocock-skills}/skills/engineering/tdd" "Use red-green-refactor test-driven development for features and bug fixes.")
    (mkSkill "prototype" "${inputs.mattpocock-skills}/skills/engineering/prototype" "Build a throwaway prototype to validate data, state, or UI design choices.")
    (mkSkill "typesafe-ai" "${inputs.typesafe-skills}/skills/typesafe-ai" "Design AI features with TypeSafe System One models, including typed Jev judgments and calibrated decisions.")
    (mkSkill "jev-mcp" (explicitSkill "jev-mcp" jevMcpSkill) "Use the local Jev MCP pilot for explicit typed decision, review, verification, screening, ranking, and shadow-routing tasks.")
  ];
  skillDependencies = {
    tdd = ["code-review"];
  };
  skillNames = map (skill: skill.name) declarativeSkills;
  unresolvedSkillDependencies = lib.concatLists (
    lib.mapAttrsToList (
      skillName: dependencies:
        lib.optional (!(builtins.elem skillName skillNames)) "${skillName} (declaring skill)"
        ++ map (dependency: "${skillName} -> ${dependency}") (
          builtins.filter (dependency: !(builtins.elem dependency skillNames)) dependencies
        )
    )
    skillDependencies
  );
  checkedDeclarativeSkills =
    if unresolvedSkillDependencies == []
    then declarativeSkills
    else throw "Codex skill catalog has unresolved workflow dependencies: ${builtins.concatStringsSep ", " unresolvedSkillDependencies}";
  skillHomeFiles = builtins.listToAttrs (map skillHomeFile checkedDeclarativeSkills);
  skillConfigToml = lib.concatMapStringsSep "\n" skillConfig checkedDeclarativeSkills;
  codexConfigPython = pkgs.python3.withPackages (ps: [ps.tomli-w]);
  context7Mcp = pkgs.writeShellScriptBin "context7-mcp" ''
    api_key="''${CONTEXT7_API_KEY:-}"
    if [ -z "$api_key" ] && [ -r "$HOME/.config/context7/api-key" ]; then
      api_key="$(${pkgs.coreutils}/bin/head -n 1 "$HOME/.config/context7/api-key")"
    fi

    if [ -n "$api_key" ]; then
      export CONTEXT7_API_KEY="$api_key"
    fi

    exec ${pkgs.nodejs}/bin/npx -y @upstash/context7-mcp
  '';
  codexConfigText = ''
    model = "gpt-6-sol"
    model_reasoning_effort = "medium"
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
    multi_agent = true
    plugins = true
    remote_plugin = false

    ${skillConfigToml}

    [mcp_servers.context7]
    command = "${context7Mcp}/bin/context7-mcp"

    [mcp_servers.jev]
    command = "${jevMcp}/bin/jev-mcp"

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
  _module.args = {
    codexCliPackage = codexCli;
    pinchtabConfigSeed = pinchtabConfigSeed;
  };

  home.packages = [
    pkgs.bubblewrap
    codexCli
    jevMcp
    jevShadowRoute
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
    existing_profiles="null"
    if [ -f "$pinchtab_config" ]; then
      existing_token="$(${pkgs.jq}/bin/jq -r '.server.token // ""' "$pinchtab_config" 2>/dev/null || true)"
      existing_profiles="$(${pkgs.jq}/bin/jq -c '.profiles // null' "$pinchtab_config" 2>/dev/null || printf 'null')"
    fi

    tmp_file="$(mktemp)"
    cp ${pinchtabConfigSeed} "$tmp_file"
    if [ -n "$existing_token" ]; then
      tmp_patch="$(mktemp)"
      ${pkgs.jq}/bin/jq --arg token "$existing_token" '.server.token = $token' "$tmp_file" > "$tmp_patch"
      mv "$tmp_patch" "$tmp_file"
    fi
    if [ "$existing_profiles" != "null" ]; then
      tmp_patch="$(mktemp)"
      ${pkgs.jq}/bin/jq --argjson profiles "$existing_profiles" '.profiles = $profiles' "$tmp_file" > "$tmp_patch"
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
