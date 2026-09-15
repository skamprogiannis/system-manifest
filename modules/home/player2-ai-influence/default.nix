{config, lib, pkgs, ...}: let
  stateDir = "${config.xdg.stateHome}/player2-ai-influence";
  credentials = "${stateDir}/credentials.json";
  runtime = pkgs.runCommand "player2-ai-influence-0.1" {
    nativeBuildInputs = [pkgs.python3];
  } ''
    mkdir -p "$out/lib"
    cp ${./bridge.py} "$out/lib/bridge.py"
    cp ${./auth.py} "$out/lib/auth.py"
    python -m py_compile "$out/lib/bridge.py" "$out/lib/auth.py"
  '';
  control = pkgs.writeShellApplication {
    name = "player2-bannerlord";
    runtimeInputs = [pkgs.systemd pkgs.python3 pkgs.xdg-utils];
    text = ''
      case "''${1:-status}" in
        start)
          if [[ ! -r ${lib.escapeShellArg credentials} ]]; then
            echo 'Authorize AI Influence first: player2-bannerlord login' >&2
            exit 1
          fi
          systemctl --user start player2-ai-influence.service
          ;;
        stop) systemctl --user stop player2-ai-influence.service ;;
        status) systemctl --user --no-pager status player2-ai-influence.service ;;
        login)
          exec python3 ${runtime}/lib/auth.py --credentials ${lib.escapeShellArg credentials}
          ;;
        *) echo 'Usage: player2-bannerlord start|stop|status|login' >&2; exit 2 ;;
      esac
    '';
  };
in {
  home.packages = [control];

  # Start on demand from Bannerlord. No desktop app or idle game heartbeat.
  systemd.user.services.player2-ai-influence = {
    Unit = {
      Description = "AI Influence connection to the Player2 Web API";
      ConditionPathExists = credentials;
    };
    Service = {
      ExecStart = "${pkgs.python3}/bin/python3 ${runtime}/lib/bridge.py --credentials ${lib.escapeShellArg credentials}";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      MemoryMax = "256M";
    };
  };
}
