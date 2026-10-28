{inputs, ...}: {
  imports = [inputs.dux-files.homeModules.dux-files];

  programs.dux-files.enable = true;

  # The NixOS Hyprland module owns portal routing. D-Bus starts Dux Files
  # on demand, so no persistent file-manager service is needed.
  xdg.mimeApps = {
    enable = true;
    associations.added."inode/directory" = ["dev.duxlabs.files.desktop"];
    defaultApplications."inode/directory" = ["dev.duxlabs.files.desktop"];
  };
}
