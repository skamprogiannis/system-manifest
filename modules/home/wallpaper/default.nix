{
  # DMS remains the shell-side wallpaper/theme consumer. skwd-wall v2 itself is
  # provided by the system-level services.skwd-deck module.
  imports = [
    ../dms
    ./skwd-wall-v2.nix
  ];
}
