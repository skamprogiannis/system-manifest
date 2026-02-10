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
        libsoup_2_4
        libsoup_3
        graphene
      ];
  };

  # Wrapper for Native Messaging (headless mode)
  pearpassNativeWrapper = pkgs.writeShellScript "pearpass-native" ''
    exec ${pearpassFHS}/bin/pearpass run --trusted pear://rdy3nr56u7k13dppa3sirj4qk3kfz6k7sss6zms3m5rspwr9wery "$@"
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
  home.packages = [pearpassFHS];

  xdg.desktopEntries.pearpass = {
    name = "PearPass";
    exec = "pearpass";
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
