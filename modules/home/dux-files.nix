{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.dux-files.homeModules.dux-files];

  programs.dux-files.enable = true;
  programs.dux-files.package = import ./dux-files-package.nix {inherit inputs pkgs;};

  # The NixOS Hyprland module owns portal routing. D-Bus starts Dux Files
  # on demand, so no persistent file-manager service is needed.
  xdg.mimeApps = {
    enable = true;
    associations.added."inode/directory" = ["dev.duxlabs.files.desktop"];
    defaultApplications."inode/directory" = ["dev.duxlabs.files.desktop"];
  };
}
