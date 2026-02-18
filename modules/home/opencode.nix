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
      },
      "formatter": {
        "prettier": {
          "command": ["npx", "prettier", "--write", "$FILE"],
          "extensions": [".js", ".ts", ".jsx", ".tsx", ".json", ".css", ".md"]
        },
        "ruff": {
          "command": ["ruff", "format", "$FILE"],
          "extensions": [".py", ".pyi"]
        },
        "gofmt": {
          "command": ["gofmt", "-w", "$FILE"],
          "extensions": [".go"]
        }
      },
      "lsp": {
        "gopls": {
          "command": ["gopls"],
          "extensions": [".go"]
        },
        "typescript-language-server": {
          "command": ["npx", "typescript-language-server", "--stdio"],
          "extensions": [".ts", ".tsx", ".js", ".jsx"]
        }
      }
    }
  '';
}
