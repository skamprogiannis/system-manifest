{ ... }: {
  # Enable ssh-agent service for persistent authentication
  services.ssh-agent.enable = true;

  # SSH configuration for multi-host support
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "github.com" = {
        AddKeysToAgent = "yes";
        IdentityFile = ["~/.ssh/id_ed25519_github"];
        IdentitiesOnly = true;
      };
      "commerce-01 62.83.94.211" = {
        HostName = "62.83.94.211";
        User = "deploy";
        IdentityFile = ["~/.ssh/netcup-hosting_ed25519"];
        IdentitiesOnly = true;
        UserKnownHostsFile = "~/.ssh/netcup-hosting_known_hosts";
        StrictHostKeyChecking = "yes";
        ConnectTimeout = 30;
        ServerAliveInterval = 15;
        ServerAliveCountMax = 3;
        ControlMaster = "auto";
        ControlPath = "/tmp/ssh-deploy-commerce01-%r@%h:%p";
        ControlPersist = "180s";
      };
    };
  };
}
