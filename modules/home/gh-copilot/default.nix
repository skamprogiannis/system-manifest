{ pkgs, ... }: {
  # Ensure Copilot and gh open Neovim from any launcher context (shell, zellij, etc.)
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    GH_EDITOR = "nvim";
  };

  programs.gh = {
    settings = {
      editor = "nvim";
    };
  };

  # Copy instructions to GH Copilot config directory
  home.file.".config/gh-copilot/instructions.md".text = builtins.readFile ./instructions.md;
}
