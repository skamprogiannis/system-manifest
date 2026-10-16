{ctx}: let
  inherit (ctx) pkgs;
  codex = ctx.homePackage "desktop" "codex-cli-wrapped";
  auto = ctx.homePackage "desktop" "codex-auto";
  version = pkgs.lib.removeSuffix "\n" (builtins.readFile ../modules/home/codex/version.txt);
  python = pkgs.python3.withPackages (ps: [ps.jsonschema]);
in {
  codex-auto = pkgs.runCommand "codex-auto-check" {nativeBuildInputs = [python pkgs.git pkgs.procps];} ''
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
    # Exercise real activation against retired hooks and preserved private history.
    python3 - <<'PYTEST'
    import json, os
    from pathlib import Path
    old = "/nix/store/" + "a" * 32 + "-codex-clef/libexec/codex-auto-hook"
    hooks = {"hooks": {event: [{"hooks": [{"type": "command", "command": old}]}]
                       for event in ("PostToolUse", "UserPromptSubmit", "PermissionRequest")}}
    hooks["hooks"]["Stop"] = [{"hooks": [{"type": "command", "command": "user-hook"}]}]
    (Path.home() / ".codex/hooks.json").write_text(json.dumps(hooks))
    for base, relative in (("XDG_STATE_HOME", "codex-clef/decisions.jsonl"),
                           ("XDG_CONFIG_HOME", "cloudflare/clef.toml")):
        path = Path(os.environ[base]) / relative
        path.parent.mkdir(parents=True)
        path.write_text("historical fixture\n")
    PYTEST
    ${ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureCodexAutoHooks.data}
    cp "$HOME/.codex/hooks.json" "$TMPDIR/hooks-once.json"
    ${ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.activation.ensureCodexAutoHooks.data}
    cmp "$HOME/.codex/hooks.json" "$TMPDIR/hooks-once.json"
    test "$(cat "$XDG_STATE_HOME/codex-clef/decisions.jsonl")" = "historical fixture"
    test "$(cat "$XDG_CONFIG_HOME/cloudflare/clef.toml")" = "historical fixture"
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
    for retired in ("PermissionRequest", "UserPromptSubmit", "PostToolUse"):
        assert hooks["hooks"][retired] == [], hooks
    config = tomllib.loads((pathlib.Path.home() / ".codex/config.toml").read_text())
    assert config["approvals_reviewer"] == "auto_review"
    assert config["approval_policy"] == "on-request"
    assert config["sandbox_mode"] == "workspace-write"
    assert config["model"] == "gpt-6.1-sol"
    assert config["model_reasoning_effort"] == "medium"
    assert config["plan_mode_reasoning_effort"] == "xhigh"
    assert config["agents"]["default_subagent_model"] == "gpt-6.1-sol"
    assert config["agents"]["default_subagent_reasoning_effort"] == "medium"
    assert hooks["hooks"]["Stop"][0]["hooks"][0]["command"] == "user-hook"
    owned = [h["command"] for groups in hooks["hooks"].values() for g in groups for h in g["hooks"] if "codex-auto-hook" in h.get("command", "")]
    assert len(owned) == 2 and all("-codex-auto/" in command for command in owned), owned
    assert "SubagentStop" not in hooks["hooks"]
    assert "auto_review" not in config
    assert config["projects"]["/unmanaged-project"]["trust_level"] == "trusted"
    PY
    python3 ${./codex-startup-test.py} ${../modules/home/codex}
    python3 ${./codex-auto-test.py} ${../modules/home/codex} ${./fixtures/codex-0.162.0}
    test ! -e ${auto}/bin/codex-clef
    ${auto}/bin/codex-auto status --json > "$TMPDIR/status.json"
    python3 - "$TMPDIR/status.json" <<'PY'
    import json, sys
    status = json.load(open(sys.argv[1]))
    assert status["model_selection"] == "native", status
    assert status["automatic_provider_calls"] is False, status
    assert status["max_delegations_per_turn"] == 4, status
    assert status["approval_and_sandbox_settings"] == "native_configuration", status
    PY
    # Match the real installed package, not only a mocked protocol transport.
    python3 ${./codex-package-smoke.py} ${codex}/bin/codex ${version} "$HOME/.codex/config.toml"
    python3 ${./codex-auto-launch-smoke.py} ${codex}/bin/codex ${auto}/bin/codex-auto
    touch "$out"
  '';
}
