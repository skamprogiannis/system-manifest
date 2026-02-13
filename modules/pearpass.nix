{
  config,
  pkgs,
  ...
}: let
  pearpassExtensionId = "pdeffakfmcdnjjafophphgmddmigpejh";
  pearpassNativeHostName = "com.pears.pass";

  pearpassSource = pkgs.fetchurl {
    url = "https://github.com/tetherto/pearpass-app-desktop/releases/download/v1.3.0/PearPass-Desktop-Linux-x64-v1.3.0.AppImage";
    sha256 = "1fl5g4jb7k6y5j50cm8dfdib2kw31g4c0akz4svkbwf4szwlm1dn";
  };

  # Extract the AppImage to get the icon and resources
  pearpassExtracted = pkgs.appimageTools.extract {
    pname = "pearpass";
    version = "1.3.0";
    src = pearpassSource;
  };

  # Create an FHS environment for PearPass
  # This mimics a standard Linux filesystem (Ubuntu/Debian) which proprietary apps expect
  pearpassFHS = pkgs.appimageTools.wrapType2 {
    pname = "pearpass";
    version = "1.3.0";
    src = pearpassSource;
    extraPkgs = pkgs:
      with pkgs; [
        # Base libraries
        glibc
        glib
        gcc-unwrapped
        xorg.libX11
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrender
        xorg.libXtst
        xorg.libXcomposite
        xorg.libXrandr
        xorg.libXScrnSaver
        nss
        nspr
        dbus
        atk
        at-spi2-atk
        at-spi2-core
        cups
        expat
        libdrm
        libxkbcommon
        mesa
        alsa-lib
        cairo
        pango
        gtk3
        gtk4
        gdk-pixbuf
        libsecret
        libnotify
        libappindicator-gtk3
        libdbusmenu-gtk3
        systemd
        udev
        vulkan-loader
        xdg-utils
        zlib
        webkitgtk_6_0
        libsoup_2_4 # Keep v2 for compatibility
        libsoup_3 # Add v3 for PearPass native host
        graphene
        # Additional GUI libraries for PearPass
        libadwaita
        gnome-themes-extra
        gtk3
        # Use OpenSSL 1.1 for AppImage compatibility
        openssl_1_1
        libgcrypt
        libgpg-error
        libxml2
        libxslt
        libnotify
        libsecret
        libxslt
        libxml2
        libgpg-error
        libgcrypt
        openssl_1_1
        icu
        libglvnd
        libGL
        xorg.libXxf86vm
        libxshmfence
        sqlite
      ];
  };

  # Launcher to force XWayland by unsetting OZONE
  pearpassLauncher = pkgs.writeShellScriptBin "pearpass-gui" ''
    unset NIXOS_OZONE_WL
    exec ${pearpassFHS}/bin/pearpass "$@"
  '';

  # Wrapper for Native Messaging (headless mode)
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    unset NIXOS_OZONE_WL
    
    # Log startup for debugging
    exec 2>/tmp/pearpass-native-error.log
    echo "Starting PearPass Native Host..." >&2

    # Trusted URLs for PearPass:
    # General: pear://i49831s3quatekogbc411cdfmg6xmjt1dycxxr3kt1b1qms5x8ro
    # Archive: (missing, please provide if known)
    
    # We rely on unsetting NIXOS_OZONE_WL (handled above) rather than forcing flags
    exec ${pearpassFHS}/bin/pearpass run \
      --trusted pear://i49831s3quatekogbc411cdfmg6xmjt1dycxxr3kt1b1qms5x8ro \
      "$@"
  '';

  pearpassManifest = pkgs.writeText "pearpass-manifest.json" (builtins.toJSON {
    name = pearpassNativeHostName;
    description = "PearPass Native Messaging Host";
    path = "${pearpassNativeWrapper}";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://${pearpassExtensionId}/"
    ];
  });
in {
  home.packages = [pearpassFHS pearpassLauncher];

  xdg.desktopEntries.pearpass = {
    name = "PearPass";
    exec = "pearpass-gui";
    icon = "${pearpassExtracted}/PearPass.png";
    comment = "PearPass Password Manager";
    categories = ["Utility"];
    settings = {
      StartupWMClass = "pear-runtime";
    };
  };

  home.file = {
    ".config/google-chrome/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/chromium/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
    ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/${pearpassNativeHostName}.json".source = pearpassManifest;
  };
}
