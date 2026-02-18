{
  pkgs,
  lib,
  config,
  ...
}: let
  # The vault path provided by the user
  vaultPath = "${config.home.homeDirectory}/tabletop_games/dungeons_and_dragons/obsidian";
  pluginId = "webpage-html-export";
  pluginPath = "${vaultPath}/.obsidian/plugins/${pluginId}";

  # Fetch the Webpage HTML Export plugin files
  mainJs = pkgs.fetchurl {
    url = "https://github.com/KosmosisDire/obsidian-webpage-export/releases/download/1.9.2/main.js";
    sha256 = "1gryz38i8vhy762fi11j5sjqnrwn0ip9jgpngr6z709kdi9cwi0m";
  };

  manifest = pkgs.fetchurl {
    url = "https://github.com/KosmosisDire/obsidian-webpage-export/releases/download/1.9.2/manifest.json";
    sha256 = "10fk24k15y0njgsril37ira8dp3g0f4iqzy2lm5adf6q5n5ym0yd";
  };

  styles = pkgs.fetchurl {
    url = "https://github.com/KosmosisDire/obsidian-webpage-export/releases/download/1.9.2/styles.css";
    sha256 = "0xzk8lrl0hr4a8d3861x62x6rj92i8yvqjbkpf4il3iw3jwp1rk0";
  };

  # Script to copy plugin files
  installScript = pkgs.writeShellScript "install-obsidian-webpage-html-export" ''
    mkdir -p "${pluginPath}"
    
    # Copy files
    cp -f "${mainJs}" "${pluginPath}/main.js"
    cp -f "${manifest}" "${pluginPath}/manifest.json"
    cp -f "${styles}" "${pluginPath}/styles.css"
    
    # Ensure proper permissions
    chmod -R u+rw "${pluginPath}"
  '';
in {
  # Use a systemd user service to copy files at login
  # This is necessary because Obsidian's sandbox can't follow symlinks outside the vault
  systemd.user.services.obsidian-webpage-html-export = {
    Unit = {
      Description = "Install Webpage HTML Export plugin for Obsidian";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = installScript;
      RemainAfterExit = true;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
