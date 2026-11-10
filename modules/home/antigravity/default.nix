{
  config,
  lib,
  pkgs,
  agentSkills,
  context7McpPackage,
  ...
}: let
  mcpSeed = pkgs.writeText "antigravity-mcp-seed.json" (builtins.toJSON {
    mcpServers = {
      context7 = {
        command = "${context7McpPackage}/bin/context7-mcp";
      };
      etsy = {
        url = "https://mcp.api.etsycloud.com/mcp";
      };
      linear = {
        url = "https://mcp.linear.app/mcp";
      };
      openaiDeveloperDocs = {
        url = "https://developers.openai.com/mcp";
      };
      ms365_vera = {
        command = "env";
        args = [
          "MS365_MCP_TENANT_ID=consumers"
          "MS365_MCP_EXPECTED_USERNAME=Vera_Bogiari@hotmail.gr"
          "MS365_MCP_TOKEN_CACHE_PATH=/home/stefan/.config/ms365-mcp-vera/token-cache.json"
          "MS365_MCP_SELECTED_ACCOUNT_PATH=/home/stefan/.config/ms365-mcp-vera/selected-account.json"
          "MS365_MCP_REDACT_PII=true"
          "npx"
          "-y"
          "@softeria/ms-365-mcp-server@0.126.0"
          "--read-only"
          "--allowed-scopes"
          "User.Read Mail.Read"
          "--expected-username"
          "Vera_Bogiari@hotmail.gr"
          "--enabled-tools"
          "^(get-current-user|list-mail-folders|list-mail-messages|get-mail-message|get-mail-message-mime)$"
        ];
      };
    };
  });

  mcpMerger = pkgs.writeTextFile {
    name = "merge-antigravity-mcp";
    destination = "/bin/merge-antigravity-mcp";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      ${builtins.readFile ./merge-mcp.py}
    '';
  };

  skillDir = source: {
    inherit source;
    force = true;
  };

  skillHomeFiles = builtins.listToAttrs (map (skill: {
    name = ".gemini/config/skills/${skill.name}";
    value = skillDir skill.package;
  }) agentSkills);
in {
  home.packages = [
    pkgs.antigravity-cli
  ];

  home.file =
    skillHomeFiles
    // {
      ".gemini/config/AGENTS.md".text = builtins.readFile ./instructions.md;
    };

  home.activation.ensureWritableAntigravityMcpConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
    run mkdir -p "$HOME/.gemini/config"
    run ${mcpMerger}/bin/merge-antigravity-mcp ${mcpSeed} "$HOME/.gemini/config/mcp_config.json"
  '';
}
