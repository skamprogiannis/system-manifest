{ctx}: let
  inherit (ctx) pkgs shellcheckScripts;
in {
  shellcheck =
    pkgs.runCommand "shellcheck-scripts" {
      nativeBuildInputs = [pkgs.shellcheck];
    } ''
      set -euo pipefail
      shellcheck -S warning ${pkgs.lib.escapeShellArgs shellcheckScripts}
      touch "$out"
    '';
}
