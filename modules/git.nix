{
  config,
  pkgs,
  ...
}: {
  programs.git = {
    enable = true;
    # Using 'settings' structure as recommended by recent Home Manager versions
    settings = {
      user = {
        name = "skamprogiannis";
        email = "boot.stefan.os@proton.me";
      };
      core = {
        editor = "nvim";
      };
      credential = {
        helper = "${pkgs.gh}/bin/gh auth git-credential";
      };
    };
  };
}
