{ctx}: let
  inherit
    (ctx)
    pkgs
    usbGamemodeEnabled
    usbGraphics32Enabled
    usbGraphics32Package
    usbMesa32Package
    usbSteamEnabled
    usbSystem
    ;
in {
  usb-steam = pkgs.runCommand "usb-steam-checks" {} ''
    set -euo pipefail

    if [ ${builtins.toJSON usbSteamEnabled} != true ]; then
      echo "USB must enable the declarative NixOS Steam module." >&2
      exit 1
    fi

    if [ ${builtins.toJSON usbGamemodeEnabled} != true ]; then
      echo "USB must enable Gamemode for Steam games." >&2
      exit 1
    fi

    if [ ${builtins.toJSON usbGraphics32Enabled} != true ]; then
      echo "USB Steam must enable the 32-bit graphics stack." >&2
      exit 1
    fi

    if [ "${usbGraphics32Package}" != "${usbMesa32Package}" ]; then
      echo "USB Steam must use the portable 32-bit Mesa graphics package." >&2
      exit 1
    fi

    if [ ! -x ${usbSystem}/sw/bin/steam ]; then
      echo "The generated USB system does not contain the Steam command." >&2
      exit 1
    fi

    if [ ! -f ${usbSystem}/sw/share/applications/steam.desktop ]; then
      echo "The generated USB system does not contain the Steam desktop entry." >&2
      exit 1
    fi

    touch "$out"
  '';
}
