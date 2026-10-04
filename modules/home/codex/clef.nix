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
      approval_mode = cfg.approvalMode;
      completion_mode = cfg.completionMode;
      trusted_roots = cfg.trustedRoots;
      git_binary = "${pkgs.git}/bin/git";
    };
  policyFile = pkgs.writeText "codex-clef-policy.json" (builtins.toJSON policy);
  python = pkgs.python3.withPackages (ps: [ps.pillow]);
  package = pkgs.runCommand "codex-clef" {nativeBuildInputs = [pkgs.makeWrapper];} ''
    mkdir -p "$out/lib/codex-clef" "$out/bin"
    cp -r ${./clef} "$out/lib/codex-clef/clef"
    cp ${./clef-entry.py} "$out/lib/codex-clef/entry.py"
    makeWrapper ${python}/bin/python3 "$out/bin/codex-clef" \
      --add-flags "-I $out/lib/codex-clef/entry.py --policy ${policyFile} --codex ${codexCliPackage}/bin/codex"
    makeWrapper ${python}/bin/python3 "$out/bin/codex-auto" \
      --add-flags "-I $out/lib/codex-clef/entry.py --policy ${policyFile} --codex ${codexCliPackage}/bin/codex launch"
  '';
  handler = matcher: {
    inherit matcher;
    hooks = [
      {
        type = "command";
        command = "${package}/bin/codex-clef hook";
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
      PermissionRequest = [(handler "*")];
      PostToolUse = [(handler "*")];
      Stop = [(handler "*")];
      SubagentStop = [(handler "*")];
    };
  });
in {
  options.system_manifest.codex.clef = {
    enable = lib.mkEnableOption "opt-in native Clef decision support" // {default = true;};
    approvalMode = lib.mkOption {
      type = lib.types.enum ["shadow" "enforce"];
      default = "shadow";
      description = "Record advisory permission triage, or additionally enforce explicit installed denials. Native requests are never automatically approved.";
    };
    completionMode = lib.mkOption {
      type = lib.types.enum ["advisory" "enforce"];
      default = "advisory";
      description = "Display completion advice, or permit at most one verification continuation per turn.";
    };
    trustedRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/home/stefan/system-manifest"];
      description = "Session roots eligible for advisory Git-command triage. These roots do not establish the execution directory or authorize approvals.";
    };
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
