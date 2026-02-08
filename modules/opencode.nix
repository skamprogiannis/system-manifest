{
  config,
  pkgs,
  ...
}: {
  # Opencode Configuration
  home.file.".config/opencode/opencode.json".text = ''
    {
      "$schema": "https://opencode.ai/config.json",
      "theme": "system",
      "plugin": ["opencode-gemini-auth@latest"],
      "mcpServers": {
        "context7": {
          "command": "npx",
          "args": ["-y", "@upstash/context7-mcp"]
        }
      }
    }
  '';
}
