{
  config,
  pkgs,
  ...
}: {
  # OpenCode Configuration
  home.file.".config/opencode/opencode.json".text = ''
    {
      "$schema": "https://opencode.ai/config.json",
      "theme": "system",
      "plugin": ["opencode-gemini-auth@latest"],
      "mcp": {
        "context7": {
          "type": "local",
          "command": ["npx", "-y", "@upstash/context7-mcp"]
        }
      }
    }
  '';
}
