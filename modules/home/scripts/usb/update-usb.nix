{
  pkgs,
  usb,
}: let
  updateUsbLib = pkgs.runCommand "update-usb-lib" {} ''
    mkdir -p "$out"
    cp ${./update-usb/args.sh} "$out/args.sh"
    cp ${./update-usb/cleanup.sh} "$out/cleanup.sh"
    cp ${./update-usb/main.sh} "$out/main.sh"
    cp ${./update-usb/metadata.sh} "$out/metadata.sh"
    cp ${./update-usb/phases.sh} "$out/phases.sh"
    cp ${./update-usb/squashfs.sh} "$out/squashfs.sh"
    cp ${./update-usb/staging.sh} "$out/staging.sh"
    cp ${./update-usb/transaction.sh} "$out/transaction.sh"
    cp ${./update-usb/telemetry.sh} "$out/telemetry.sh"
  '';
in
  pkgs.writeShellScriptBin "update-usb" ''
    set -euo pipefail

    export USB_UPDATE_LIB_DIR=${updateUsbLib}
    export USB_ROOT_PART=${usb.rootPartByLabel}
    export USB_BOOT_DEV=${usb.bootByLabel}
    export PREFERRED_USB_MAPPER_NAME=${usb.mapperName}
    export UPDATE_USB_JQ=${pkgs.jq}/bin/jq
    export UPDATE_USB_REVISION=${updateUsbLib}

    exec ${pkgs.bash}/bin/bash ${updateUsbLib}/main.sh "$@"
  ''
