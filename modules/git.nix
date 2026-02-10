{
  config,
  pkgs,
  ...
}: {
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
        helper = "";
      };
      url = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
        "git@platform.zone01.gr:" = {
          insteadOf = "https://platform.zone01.gr/";
        };
      };
    };
  };

  # Enable ssh-agent service for persistent authentication
  services.ssh-agent.enable = true;

  # SSH configuration for multi-host support
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "github.com" = {
        host = "github.com";
        identityFile = "~/.ssh/id_ed25519_github";
        addKeysToAgent = "yes";
        identitiesOnly = true;
      };
      "platform.zone01.gr" = {
        host = "platform.zone01.gr";
        identityFile = "~/.ssh/id_ed25519_gitea";
        addKeysToAgent = "yes";
        identitiesOnly = true;
      };
    };
  };
}
