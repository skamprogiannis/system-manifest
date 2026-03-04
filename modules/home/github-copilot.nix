{ pkgs, ... }: {
  programs.bash = {
    initExtra = ''
      # Set editor for GitHub CLI
      export GH_EDITOR=vim
    '';
  };
}
