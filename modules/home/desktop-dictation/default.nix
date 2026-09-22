{pkgs, lib, ...}: let
  runtime = pkgs.callPackage ../bannerlord-speech/package.nix {dictationOnly = true;};
  desktopDictation = pkgs.writeShellApplication {
    name = "desktop-dictation";
    runtimeInputs = [pkgs.libnotify pkgs.procps pkgs.systemd pkgs.wl-clipboard];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./client.py} "$@"
    '';
  };
  lua = lib.generators.mkLuaInline;
  command = value: lua "hl.dsp.exec_cmd(${builtins.toJSON value})";
  bind = key: dispatcher: options: {
    _args = [key dispatcher options];
  };
  shortcut = lua ''mod .. " + t"'';
in {
  home.packages = [desktopDictation];

  systemd.user.services.desktop-dictation = {
    Unit = {
      Description = "Private on-demand desktop dictation";
    };
    Service = {
      Type = "simple";
      ExecStart = "${runtime}/bin/bannerlord-speech-service --dictation-only --port 11437 --runtime-dir %t/desktop-dictation";
      RuntimeDirectory = "desktop-dictation";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      MemoryHigh = "700M";
      MemoryMax = "1G";
      CPUWeight = 15;
      Nice = 5;
      KillMode = "control-group";
      TimeoutStartSec = 8;
      TimeoutStopSec = 8;
      NoNewPrivileges = true;
    };
  };

  wayland.windowManager.hyprland.settings.bind = [
    (bind shortcut (command "desktop-dictation start") {})
    (bind shortcut (command "desktop-dictation stop") {release = true;})
  ];
}
