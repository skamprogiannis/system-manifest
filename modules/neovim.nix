{
  config,
  pkgs,
  ...
}: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars # Better syntax highlighting
      telescope-nvim # Fuzzy finder
      opencode-nvim # vscode style sidebar for opencode
    ];
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
