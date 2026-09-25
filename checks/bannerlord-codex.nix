{ctx}: let
  inherit (ctx) pkgs self;
  runtime = pkgs.callPackage ../modules/home/bannerlord-codex/package.nix {};
  codexCli = builtins.head (
    builtins.filter
    (package: (package.name or "") == "codex-cli-wrapped")
    self.nixosConfigurations.desktop.config.home-manager.users.stefan.home.packages
  );
  enabled = self.nixosConfigurations.desktop.config.home-manager.users.stefan.system_manifest.bannerlord.enable;
  service =
    if enabled
    then self.nixosConfigurations.desktop.config.home-manager.users.stefan.systemd.user.services.bannerlord-codex
    else {};
  serviceJson = pkgs.writeText "bannerlord-codex-service.json" (builtins.toJSON service);
in {
  bannerlord-codex =
    pkgs.runCommand "bannerlord-codex-check" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      export PYTHONPATH=${runtime}/lib
      export PYTHONDONTWRITEBYTECODE=1
      export CODEX_TEST_EXECUTABLE=${codexCli}/bin/codex
      mkdir tests
      cp ${../modules/home/bannerlord-codex/test_adapter.py} tests/test_adapter.py
      cp ${../modules/home/bannerlord-codex/test_service.py} tests/test_service.py
      python3 -m unittest discover -s tests -v
      python3 - ${serviceJson} ${runtime} <<'PY'
      import json
      from pathlib import Path
      import sys

      unit = json.loads(Path(sys.argv[1]).read_text())
      installed = {p.name for p in (Path(sys.argv[2]) / "lib").iterdir() if p.is_file()}
      assert installed == {"adapter.py", "codex_runner.py", "model-instructions.txt", "response.schema.json", "preflight.py", "codex-version.txt", "control.py"}
      if not unit:
          print("Bannerlord profile disabled; runtime tests and allowlist passed; service contract is intentionally absent.")
          raise SystemExit(0)
      service = unit["Service"]
      assert not unit.get("Install", {}).get("WantedBy"), "must stay on demand"
      assert unit["Unit"]["StartLimitIntervalSec"] == 60
      assert unit["Unit"]["StartLimitBurst"] == 3
      assert service["KillMode"] == "control-group", "stop must include detached Codex children"
      assert service["StateDirectoryMode"] == "0700"
      assert service["UMask"] == "0077"
      assert service["StateDirectory"] == "bannerlord-codex"
      assert "HOME=/home/stefan" in service["Environment"]
      assert any(x.startswith("PATH=") and "codex-cli-wrapped" in x for x in service["Environment"])
      assert all("--port 11435" in x for x in ([service["ExecStart"]] if isinstance(service["ExecStart"], str) else service["ExecStart"]))
      print("Service contract and runtime allowlist passed; no inference or credentials used.")
      PY
      touch "$out"
    '';
}
