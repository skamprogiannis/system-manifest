{...}: {
  # Shared wallpaper entrypoint only: compose the common DMS/skwd-wall contract
  # here, but keep host-owned runtime behavior in host imports or per-module
  # `desktop.nix` / `usb.nix` files instead of growing `hostType` branches.
  imports = [
    ../dms
    ../skwd-wall.nix
  ];
}
