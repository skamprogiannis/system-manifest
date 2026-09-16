{
  config,
  pkgs,
  ...
}: let
  runtime = pkgs.callPackage ./package.nix {};
in {
  home.packages = [runtime];

  # The game launcher owns the service lifecycle; login never opens the microphone.
  systemd.user.services.bannerlord-speech = {
    Unit = {
      Description = "Local English speech for Bannerlord AI dialogue";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "simple";
      ExecStart = "${runtime}/bin/bannerlord-speech-service --port 11436 --runtime-dir %t/bannerlord-speech --cache-dir %S/bannerlord-speech/audio-cache";
      Environment = ["HOME=${config.home.homeDirectory}"];
      RuntimeDirectory = "bannerlord-speech";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "bannerlord-speech";
      StateDirectoryMode = "0700";
      WorkingDirectory = "%S/bannerlord-speech";
      UMask = "0077";
      MemoryHigh = "2G";
      MemoryMax = "3G";
      CPUWeight = 25;
      Nice = 5;
      KillMode = "control-group";
      TimeoutStartSec = 30;
      TimeoutStopSec = 8;
      Restart = "on-failure";
      RestartSec = 3;
      NoNewPrivileges = true;
    };
  };
}
