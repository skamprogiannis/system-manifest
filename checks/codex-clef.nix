{ctx}: let
  inherit (ctx) pkgs;
  codex = ctx.homePackage "desktop" "codex-cli-wrapped";
  clef = ctx.homePackage "desktop" "codex-clef";
  version = pkgs.lib.removeSuffix "\n" (builtins.readFile ../modules/home/codex/version.txt);
  python = pkgs.python3.withPackages (ps: [ps.jsonschema ps.pillow ps.tomli-w]);
in {
  codex-clef = pkgs.runCommand "codex-clef-check" {nativeBuildInputs = [python pkgs.git pkgs.procps];} ''
    export HOME="$TMPDIR/home"
    export XDG_STATE_HOME="$TMPDIR/state"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export PYTHONDONTWRITEBYTECODE=1
    mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
    run() { "$@"; }
    # Check both a fresh home and migration from Home Manager's previous links.
    ${ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureCodexAgents.data}
    for role in architect explorer plan-reviewer researcher security-reviewer worker; do
      rm "$HOME/.codex/agents/$role.toml"
      ln -s ${../modules/home/codex/agents}/"$role.toml" "$HOME/.codex/agents/$role.toml"
    done
    printf 'unmanaged role\n' > "$HOME/.codex/agents/custom.keep"
    ${ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureCodexAgents.data}
    test "$(cat "$HOME/.codex/agents/custom.keep")" = "unmanaged role"
    cat > "$HOME/.codex/config.toml" <<'TOML'
    approvals_reviewer = "user"
    [projects."/unmanaged-project"]
    trust_level = "trusted"
    TOML
    ${ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureWritableCodexConfig.data}
    ${ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureCodexClefHooks.data}
    python3 - <<'PY'
    import json, os, pathlib, re, tomllib
    paths = list((pathlib.Path.home() / ".codex/agents").glob("*.toml"))
    assert len(paths) == 6
    for path in paths:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd) as handle:
            role = tomllib.loads(handle.read())
        assert role["name"] == path.stem
    hooks = json.loads((pathlib.Path.home() / ".codex/hooks.json").read_text())
    matcher = hooks["hooks"]["PreToolUse"][0]["matcher"]
    for tool in ("spawn_agent", "Agent", "collaborationspawn_agent"):
        assert re.search(matcher, tool), tool
    assert not re.search(matcher, "collaborationsend_message")
    assert "PermissionRequest" not in hooks["hooks"]
    config = tomllib.loads((pathlib.Path.home() / ".codex/config.toml").read_text())
    assert config["approvals_reviewer"] == "auto_review"
    assert config["approval_policy"] == "on-request"
    assert config["sandbox_mode"] == "workspace-write"
    assert config["model"] == "gpt-6.1-sol"
    assert config["model_reasoning_effort"] == "medium"
    assert config["plan_mode_reasoning_effort"] == "xhigh"
    assert config["agents"]["default_subagent_model"] == "gpt-6.1-sol"
    assert config["agents"]["default_subagent_reasoning_effort"] == "medium"
    assert "Stop" not in hooks["hooks"]
    assert "SubagentStop" not in hooks["hooks"]
    assert "auto_review" not in config
    assert config["projects"]["/unmanaged-project"]["trust_level"] == "trusted"
    PY
    # Read the native resolver's values, without credentials or a model turn.
    python3 - <<'PY'
    import sys
    sys.path.insert(0, "${../modules/home/codex}")
    from clef.catalog import RPC
    with RPC("${codex}/bin/codex") as rpc:
        config = rpc.request("config/read", {"includeLayers": False})["config"]
    assert config["agents"]["default_subagent_model"] == "gpt-6.1-sol", config["agents"]
    assert config["agents"]["default_subagent_reasoning_effort"] == "medium", config["agents"]
    assert config["plan_mode_reasoning_effort"] == "xhigh"
    PY
    python3 ${./codex-startup-test.py} ${../modules/home/codex}
    python3 ${./codex-clef-test.py} ${../modules/home/codex} ${./fixtures/codex-0.161.0}
    test ! -e ${clef}/bin/codex-clef
    ${clef}/bin/codex-auto status --json > "$TMPDIR/status.json"
    python3 - "$TMPDIR/status.json" <<'PY'
    import json, sys
    status = json.load(open(sys.argv[1]))
    assert status["log_status"] == "no_decisions_recorded", status
    assert status["approval_mode"] == "native", status
    assert status["automatic_approval_supported"] is False, status
    PY
    # Match the real installed package, not only a mocked protocol transport.
    python3 ${./codex-package-smoke.py} ${codex}/bin/codex ${version}
    python3 ${./codex-clef-launch-smoke.py} ${codex}/bin/codex ${clef}/bin/codex-auto
    touch "$out"
  '';
}
