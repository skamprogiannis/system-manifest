{
  config,
  lib,
  pkgs,
  codexCliPackage,
  ...
}: let
  runtime = pkgs.callPackage ./package.nix {};
  control = pkgs.writeShellApplication {
    name = "bannerlord-codex";
    runtimeInputs = [pkgs.systemd pkgs.python3];
    text = ''
      exec python3 ${runtime}/lib/control.py "$@"
    '';
  };
in {
  config = lib.mkIf config.system_manifest.bannerlord.enable {
    home.packages = [control];

    # Started explicitly by the game launcher; no login-time model requests.
    systemd.user.services.bannerlord-codex = {
    Unit = {
      Description = "Experimental AI Influence text adapter for Codex";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.python3}/bin/python3 ${runtime}/lib/preflight.py";
      ExecStart = "${pkgs.python3}/bin/python3 ${runtime}/lib/adapter.py --port 11435 --model gpt-5.6-sol --timeout 85 --metrics %S/bannerlord-codex/metrics.jsonl";
      Environment = [
        "HOME=${config.home.homeDirectory}"
        "PATH=${lib.makeBinPath [codexCliPackage pkgs.python3 pkgs.bubblewrap pkgs.coreutils pkgs.bash]}"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "PYTHONDONTWRITEBYTECODE=1"
        "PYTHONUNBUFFERED=1"
      ];
      UnsetEnvironment = ["OPENAI_API_KEY" "CODEX_API_KEY" "OPENAI_BASE_URL" "CODEX_HOME"];
      StateDirectory = "bannerlord-codex";
      StateDirectoryMode = "0700";
      WorkingDirectory = "%S/bannerlord-codex";
      UMask = "0077";
      KillMode = "control-group";
      TimeoutStartSec = 30;
      TimeoutStopSec = 8;
      SendSIGKILL = true;
      Restart = "on-failure";
      RestartSec = 3;
      };
    };
  };
}
