{pkgs, lib, ...}: {
  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
    openFirewall = false;
    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH = "True";
      ENABLE_WEB_SEARCH = "True";
      WEB_SEARCH_ENGINE = "searxng";
      SEARXNG_QUERY_URL = "http://127.0.0.1:8888/search";
      WEB_SEARCH_RESULT_COUNT = "5";
    };
  };

  services.searx = {
    enable = true;
    openFirewall = false;
    environmentFile = "/var/lib/searx-local/secret.env";
    settings = {
      search = {
        safe_search = 0;
        formats = ["html" "json"];
      };
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        secret_key = "$SEARXNG_SECRET";
        limiter = false;
        public_instance = false;
      };
    };
  };

  # Leave both services installed but start them only through ai-search.
  systemd.services.open-webui.wantedBy = lib.mkForce [];
  systemd.services.searx.wantedBy = lib.mkForce [];

  # Keep the secret out of the world-readable Nix store.
  systemd.services.searx-secret = {
    description = "Generate a persistent local SearXNG secret";
    serviceConfig = {
      Type = "oneshot";
      User = "searx";
      Group = "searx";
      StateDirectory = "searx-local";
      StateDirectoryMode = "0700";
    };
    script = ''
      umask 077
      if [ ! -s /var/lib/searx-local/secret.env ]; then
        printf 'SEARXNG_SECRET=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" > /var/lib/searx-local/secret.env
      fi
    '';
  };

  systemd.services.searx-init = {
    requires = ["searx-secret.service"];
    after = ["searx-secret.service"];
  };

  systemd.services.open-webui = {
    wants = ["ollama.service" "searx.service"];
    after = ["ollama.service" "searx.service"];
  };
}
