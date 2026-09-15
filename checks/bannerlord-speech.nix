{ctx}: let
  inherit (ctx) pkgs self;
  runtime = pkgs.callPackage ../modules/home/bannerlord-speech/package.nix {};
  service = self.nixosConfigurations.desktop.config.home-manager.users.stefan.systemd.user.services.bannerlord-speech;
  serviceJson = pkgs.writeText "bannerlord-speech-service.json" (builtins.toJSON service);
  environmentJson = pkgs.writeText "bannerlord-speech-environment.json" (builtins.toJSON runtime.engineEnvironment);
in {
  bannerlord-speech =
    pkgs.runCommand "bannerlord-speech-check" {
      nativeBuildInputs = [runtime.python];
    } ''
      export PYTHONPATH=${runtime}/lib
      export PYTHONDONTWRITEBYTECODE=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
      export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2
      mkdir tests
      cp ${../modules/home/bannerlord-speech/test_service.py} tests/test_service.py
      python3 -m unittest discover -s tests -v
      python3 - ${serviceJson} ${environmentJson} ${runtime} <<'PY'
      import json
      from pathlib import Path
      import sys
      import torch
      from misaki import en, espeak

      unit = json.loads(Path(sys.argv[1]).read_text())
      environment = json.loads(Path(sys.argv[2]).read_text())
      service = unit["Service"]
      assert not unit.get("Install", {}).get("WantedBy"), "must stay on demand"
      assert service["MemoryHigh"] == "2G" and service["MemoryMax"] == "3G"
      assert service["RuntimeDirectoryMode"] == service["StateDirectoryMode"] == "0700"
      assert service["UMask"] == "0077"
      assert service["KillMode"] == "control-group"
      commands = service["ExecStart"] if isinstance(service["ExecStart"], list) else [service["ExecStart"]]
      assert len(commands) == 1
      assert "--port 11436" in commands[0]
      assert "--runtime-dir %t/bannerlord-speech" in commands[0]
      assert environment["HF_HUB_OFFLINE"] == environment["TRANSFORMERS_OFFLINE"] == "1"
      assert all(environment[k] == "2" for k in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"))
      assert torch.version.cuda is None, "speech Python closure must use CPU Torch"
      for key in ("WHISPER_BIN", "WHISPER_MODEL", "KOKORO_MODEL", "KOKORO_CONFIG", "KOKORO_VOICES", "PW_RECORD_BIN"):
          assert Path(environment[key]).exists(), key
      voices = sorted(p.stem for p in Path(environment["KOKORO_VOICES"]).glob("*.pt"))
      assert voices == ["bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis"]
      assert {p.name for p in (Path(sys.argv[3]) / "lib").iterdir()} == {"service.py", "engine.py", "control.py"}
      g2p = en.G2P(trf=False, british=True, fallback=espeak.EspeakFallback(british=True), unk="")
      assert g2p("What service would earn your trust?")[0]
      print("Speech service, CPU closure and offline English front-end checks passed; no recording or model generation.")
      PY
      touch "$out"
    '';
}
