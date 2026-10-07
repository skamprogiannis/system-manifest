{
  config,
  lib,
  pkgs,
  codexCliPackage,
  ...
}: let
  cfg = config.system_manifest.codex.clef;
  policy =
    (builtins.fromJSON (builtins.readFile ./clef/policy.json))
    // {
      codex_version = lib.removeSuffix "\n" (builtins.readFile ./version.txt);
    };
  policyFile = pkgs.writeText "codex-clef-policy.json" (builtins.toJSON policy);
  python = pkgs.python3.withPackages (ps: [ps.pillow]);
  package = pkgs.runCommand "codex-clef" {nativeBuildInputs = [pkgs.makeWrapper];} ''
    mkdir -p "$out/lib/codex-clef" "$out/libexec" "$out/bin"
    cp -r ${./clef} "$out/lib/codex-clef/clef"
    cp ${./clef-entry.py} "$out/lib/codex-clef/entry.py"
    makeWrapper ${python}/bin/python3 "$out/libexec/codex-auto-hook" \
      --add-flags "-I $out/lib/codex-clef/entry.py --policy ${policyFile} --codex ${codexCliPackage}/bin/codex hook"
    makeWrapper ${python}/bin/python3 "$out/bin/codex-auto" \
      --add-flags "-I $out/lib/codex-clef/entry.py auto --policy ${policyFile} --codex ${codexCliPackage}/bin/codex --"
  '';
  handler = matcher: {
    inherit matcher;
    hooks = [
      {
        type = "command";
        command = "${package}/libexec/codex-auto-hook";
        timeout = 8;
        statusMessage = "Clef decision support";
      }
    ];
  };
  hooksSeed = pkgs.writeText "codex-clef-hooks.json" (builtins.toJSON {
    hooks = {
      SessionStart = [(handler "startup|resume|clear|compact")];
      UserPromptSubmit = [(handler "*")];
      PreToolUse = [(handler "^(spawn_agent|Agent|collaborationspawn_agent)$")];
      PostToolUse = [(handler "*")];
    };
  });
in {
  options.system_manifest.codex.clef = {
    enable = lib.mkEnableOption "opt-in native Clef decision support" // {default = true;};
  };
  config = {
    home.packages = lib.mkIf cfg.enable [package];
    home.activation.ensureCodexClefHooks = lib.hm.dag.entryAfter ["ensureWritableCodexConfig"] ''
      run ${pkgs.python3}/bin/python3 ${./merge-hooks.py} ${
        if cfg.enable
        then hooksSeed
        else pkgs.writeText "codex-clef-hooks-disabled.json" (builtins.toJSON {hooks = {};})
      } "$HOME/.codex/hooks.json"
    '';
  };
}
