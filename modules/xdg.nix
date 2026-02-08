{
  config,
  pkgs,
  ...
}: {
  # Manage XDG User Directories (Documents, Downloads, Music, etc.)
  # This ensures they are created and managed declaratively.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };
}
