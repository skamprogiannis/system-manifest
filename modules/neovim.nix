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
      dracula-nvim
    ];

    extraConfig = ''
      colorscheme dracula

      " Move lines with Alt+Up/Down
      " Normal mode
      nnoremap <A-Down> :m .+1<CR>==
      nnoremap <A-Up> :m .-2<CR>==

      " Visual mode
      vnoremap <A-Down> :m '>+1<CR>gv=gv
      vnoremap <A-Up> :m '<-2<CR>gv=gv

      " Insert mode
      inoremap <A-Down> <Esc>:m .+1<CR>==gi
      inoremap <A-Up> <Esc>:m .-2<CR>==gi
    '';
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
