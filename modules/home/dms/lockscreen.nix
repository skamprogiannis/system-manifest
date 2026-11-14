{...}: {
  # Widget definitions are declarative; runtime placement stays writable.
  programs.dank-material-shell.settings =
    (builtins.fromJSON (builtins.readFile ./lockscreen.json)).settings;
}
