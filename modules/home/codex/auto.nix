{
  config,
  lib,
  pkgs,
  codexCliPackage,
  ...
}: let
  cfg = config.system_manifest.codex.auto;
  package = pkgs.runCommand "codex-auto" {nativeBuildInputs = [pkgs.makeWrapper];} ''
    mkdir -p "$out/lib/codex-auto" "$out/libexec" "$out/bin"
    cp ${./auto.py} "$out/lib/codex-auto/auto.py"
    cp ${./workflow.py} "$out/lib/codex-auto/workflow.py"
    cp ${./startup.py} "$out/lib/codex-auto/startup.py"
    makeWrapper ${pkgs.python3}/bin/python3 "$out/libexec/codex-auto-hook" \
      --add-flags "-I $out/lib/codex-auto/auto.py hook"
    makeWrapper ${pkgs.python3}/bin/python3 "$out/bin/codex-auto" \
      --add-flags "-I $out/lib/codex-auto/auto.py launch ${codexCliPackage}/bin/codex"
  '';
  handler = matcher: {
    inherit matcher;
    hooks = [
      {
        type = "command";
        command = "${package}/libexec/codex-auto-hook";
        timeout = 5;
        statusMessage = "Native delegation guard";
      }
    ];
  };
  hooksSeed = pkgs.writeText "codex-auto-hooks.json" (builtins.toJSON {
    hooks = lib.optionalAttrs cfg.enable {
      SessionStart = [(handler "startup|resume|clear|compact")];
      PreToolUse = [(handler "^(spawn_agent|Agent|collaborationspawn_agent)$")];
    };
  });
in {
  options.system_manifest.codex.auto.enable = lib.mkEnableOption "opt-in native Codex delegation" // {default = true;};
  config = {
    home.packages = lib.mkIf cfg.enable [package];
    home.activation.ensureCodexAutoHooks = lib.hm.dag.entryAfter ["ensureWritableCodexConfig"] ''
      run ${pkgs.python3}/bin/python3 ${./merge-hooks.py} ${hooksSeed} "$HOME/.codex/hooks.json"
    '';
  };
}
