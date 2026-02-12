{
  config,
  pkgs,
  ...
}: {
  home.packages = [
    pkgs.git-credential-manager
  ];

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "skamprogiannis";
        email = "boot.stefan.os@proton.me";
      };
      core = {
        editor = "nvim";
        sshCommand = "ssh -o AddKeysToAgent=yes";
      };
      credential = {
        helper = "manager";
        credentialStore = "secretservice";
        "https://github.com".helper = "${pkgs.gh}/bin/gh auth git-credential";
        "https://platform.zone01.gr".helper = "store";
        "https://platform.zone01.gr".provider = "generic";
      };

      push = {
        autoSetupRemote = true;
      };
    };
  };

  # Enable ssh-agent service for persistent authentication
  services.ssh-agent.enable = true;

  # SSH configuration for multi-host support
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "github.com" = {
        host = "github.com";
        identityFile = "~/.ssh/id_ed25519_github";
        addKeysToAgent = "yes";
        identitiesOnly = true;
      };
    };
  };
}
