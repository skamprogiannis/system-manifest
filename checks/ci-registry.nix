{ctx}: let
  inherit (ctx) pkgs registry;
  registryJson = builtins.toFile "check-registry.json" (builtins.toJSON registry);
in {
  ci-registry =
    pkgs.runCommand "ci-registry-check" {
      nativeBuildInputs = [pkgs.python3 pkgs.git pkgs.actionlint pkgs.shellcheck];
    } ''
      set -euo pipefail
      export PYTHONDONTWRITEBYTECODE=1
      python3 ${../.github/scripts}/test_ci.py ${registryJson}
      actionlint ${../.github/workflows/validate.yml} ${../.github/workflows/validate-full-desktop.yml}
      touch "$out"
    '';
}
