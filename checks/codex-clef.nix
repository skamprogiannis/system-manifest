{ctx}: let
  inherit (ctx) pkgs;
  packages = ctx.self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.packages;
  codex = builtins.head (builtins.filter (p: pkgs.lib.getName p == "codex-cli-wrapped") packages);
  clef = builtins.head (builtins.filter (p: pkgs.lib.getName p == "codex-clef") packages);
  version = pkgs.lib.removeSuffix "\n" (builtins.readFile ../modules/home/codex/version.txt);
  python = pkgs.python3.withPackages (ps: [ps.jsonschema ps.pillow ps.tomli-w]);
in {
  codex-clef = pkgs.runCommand "codex-clef-check" {nativeBuildInputs = [python];} ''
    export HOME="$TMPDIR/home"
    export XDG_STATE_HOME="$TMPDIR/state"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export PYTHONDONTWRITEBYTECODE=1
    mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
    python3 ${./codex-clef-test.py} ${../modules/home/codex} ${./fixtures/codex-0.160.0}
    ${clef}/bin/codex-clef status > "$TMPDIR/status.json"
    python3 - "$TMPDIR/status.json" <<'PY'
    import json, sys
    status = json.load(open(sys.argv[1]))
    assert status["log_status"] == "no_decisions_recorded", status
    assert status["approval_mode"] == "shadow", status
    PY
    # Match the real installed package, not only a mocked protocol transport.
    python3 ${./codex-package-smoke.py} ${codex}/bin/codex ${version}
    touch "$out"
  '';
}
