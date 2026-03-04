{ pkgs, ... }: {
  # GitHub Copilot CLI Configuration
  programs.bash = {
    initExtra = ''
      # Set editor for GitHub CLI (Ctrl+Y opens editor)
      export GH_EDITOR=vim
    '';
  };

  # Copy instructions to GH Copilot config directory
  home.file.".config/gh-copilot/instructions.md".text = builtins.readFile ./instructions.md;
}
