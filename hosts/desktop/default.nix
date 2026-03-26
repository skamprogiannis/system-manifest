{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  portalServicePatchScript = pkgs.writeText "patch-greeter-portal-service.py" ''
    import re
    import sys
    from pathlib import Path

    portal_service = Path(sys.argv[1])
    text = portal_service.read_text()

    lookup_pattern = re.compile(r"    function getGreeterUserProfileImage\(username\) \{\n.*?\n    \}\n", re.S)
    new_lookup = """    function getGreeterUserProfileImage(username) {
        if (!username) {
            profileImage = "";
            return;
        }

        const safeUsername = username.replace(/[^a-zA-Z0-9._-]/g, "");
        if (!safeUsername) {
            profileImage = "";
            return;
        }

        const lookupScript = [
            "uid=$(id -u " + safeUsername + " 2>/dev/null)",
            "if [ -z \\"$uid\\" ]; then",
            "  echo \\"\\"",
            "  exit 0",
            "fi",
            "",
            "icon_path=$(dbus-send --system --print-reply --dest=org.freedesktop.Accounts /org/freedesktop/Accounts/User$uid org.freedesktop.DBus.Properties.Get string:org.freedesktop.Accounts.User string:IconFile 2>/dev/null | sed -n 's/.*string \\"\\\\(.*\\\\)\\"/\\\\1/p' | sed -n '1p')",
            "",
            "if [ -n \\"$icon_path\\" ] && [ \\"$icon_path\\" != \\"/var/lib/AccountsService/icons/\\" ]; then",
            "  echo \\"$icon_path\\"",
            "elif [ -r \\"/var/lib/AccountsService/icons/" + safeUsername + ".png\\" ]; then",
            "  echo \\"/var/lib/AccountsService/icons/" + safeUsername + ".png\\"",
            "elif [ -r \\"/var/lib/AccountsService/icons/" + safeUsername + ".jpg\\" ]; then",
            "  echo \\"/var/lib/AccountsService/icons/" + safeUsername + ".jpg\\"",
            "elif [ -r \\"/var/lib/AccountsService/icons/" + safeUsername + ".jpeg\\" ]; then",
            "  echo \\"/var/lib/AccountsService/icons/" + safeUsername + ".jpeg\\"",
            "elif [ -r \\"/var/lib/AccountsService/icons/" + safeUsername + ".webp\\" ]; then",
            "  echo \\"/var/lib/AccountsService/icons/" + safeUsername + ".webp\\"",
            "else",
            "  echo \\"\\"",
            "fi"
        ].join("\\n");

        console.info("Greeter avatar lookup for user:", safeUsername);
        userProfileCheckProcess.command = ["bash", "-c", lookupScript];
        userProfileCheckProcess.running = true;
    }"""

    text, lookup_replacements = lookup_pattern.subn(new_lookup + "\n", text, count=1)
    if lookup_replacements != 1:
        raise RuntimeError("PortalService lookup function not found while patching greeter avatar fallback")
    portal_service.write_text(text)
  '';

  greeterBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;

  greeterPatchedPackage = greeterBasePackage.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      chmod u+w "$out/share/quickshell/dms/Services/PortalService.qml"
      ${pkgs.python3}/bin/python3 ${portalServicePatchScript} \
        "$out/share/quickshell/dms/Services/PortalService.qml"
      chmod a-w "$out/share/quickshell/dms/Services/PortalService.qml"
    '';
  });

  avatarPng = pkgs.runCommand "stefan-avatar-png" {nativeBuildInputs = [pkgs.ffmpeg];} ''
    mkdir -p "$out"
    ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel error -y \
      -i ${./assets/stefan-avatar.webp} \
      "$out/stefan-avatar.png"
  '';
in {
  imports = [
    ../common/default.nix
    ../../modules/desktop-enviroments/hyprland.nix
    ./hardware-configuration.nix
  ];

  # DMS greeter (greetd + QuickShell) replaces GDM
  services.displayManager.gdm.enable = false;
  programs.dank-material-shell.greeter = {
    enable = true;
    package = greeterPatchedPackage;
    compositor = {
      name = "hyprland";
      customConfig = ''
        misc {
          disable_hyprland_logo = true
        }

        debug {
          disable_logs = true
        }
      '';
    };
    configHome = "/home/stefan";
    logs.save = true;
    logs.path = "/var/lib/dms-greeter/greeter.log";
  };
  services.greetd.settings.default_session.user = "greeter";

  # Keep a canonical greetd config path for DMS greeter CLI status/sync checks.
  # Use a regular file (not immutable /etc symlink) so dms greeter sync can
  # still update it when triggered from UI/CLI.
  system.activationScripts.greetdCompatConfig = lib.stringAfter ["etc"] ''
    install -d -m0755 /etc/greetd
    install -m0644 ${(pkgs.formats.toml {}).generate "greetd-config.toml" config.services.greetd.settings} /etc/greetd/config.toml
  '';

  # Allow user-triggered greeter sync helpers to access greeter-managed assets.
  users.users.stefan.extraGroups = lib.mkAfter ["greeter"];

  # AccountsService user config — required for the greeter avatar.
  environment.etc."AccountsService/users/stefan".text = ''
    [User]
    Icon=/var/lib/AccountsService/icons/stefan.png
    SystemAccount=false
  '';

  # Keep a real PNG icon for maximum greeter compatibility.
  system.activationScripts.accountsServiceAvatar = lib.stringAfter ["users"] ''
    install -dm0755 /var/lib/AccountsService/users /var/lib/AccountsService/icons

    cat > /var/lib/AccountsService/users/stefan <<'EOF'
    [User]
    Icon=/var/lib/AccountsService/icons/stefan.png
    SystemAccount=false
    EOF
    chmod 0644 /var/lib/AccountsService/users/stefan
    chown root:root /var/lib/AccountsService/users/stefan

    install -Dm0644 ${./assets/stefan-avatar.webp} /var/lib/AccountsService/icons/stefan.webp
    install -Dm0644 ${avatarPng}/stefan-avatar.png /var/lib/AccountsService/icons/stefan.png
    chmod 0644 /var/lib/AccountsService/icons/stefan.webp /var/lib/AccountsService/icons/stefan.png
    chown root:root /var/lib/AccountsService/icons/stefan.webp /var/lib/AccountsService/icons/stefan.png
  '';

  # System-wide cursor theme (needed for greeter and other non-HM contexts)
  environment.variables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # DMS greeter shells out to bash+dbus-send for user profile icons
  systemd.services.greetd.path = with pkgs; [ bash dbus gnugrep gnused systemd ];
  # Ensure greeter DBus queries and Qt image loaders resolve correctly.
  systemd.services.greetd.environment = {
    DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
    QT_PLUGIN_PATH = lib.concatStringsSep ":" [
      "${pkgs.qt6.qtbase}/lib/qt-6/plugins"
      "${pkgs.qt6.qtimageformats}/lib/qt-6/plugins"
    ];
  };

  networking.hostName = "desktop";

  # Bootloader
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    gfxmodeEfi = "1920x1080";
    configurationLimit = 20;
    theme = pkgs.stdenv.mkDerivation {
      pname = "hollow-knight-grub-theme";
      version = "1.0";
      src = pkgs.fetchFromGitHub {
        owner = "sergoncano";
        repo = "hollow-knight-grub-theme";
        rev = "9515f805f72dc214e3da59967f0b678d9910adf1";
        sha256 = "sha256-0hn3MFC+OtfwtA//pwjnWz7Oz0Cos3YzbgUlxKszhyA=";
      };
      installPhase = ''
        mkdir -p $out
        cp -r hollow-grub/* $out
        # Center the keybinds description and move it below options
        sed -i '/#Keybinds/,/}/ s/left = 10%/left = 0\n\twidth = 100%/' $out/theme.txt
        sed -i '/#Keybinds/,/}/ s/top = 82%/top = 85%/' $out/theme.txt

        # Center the logo (Nudged further left to fix bias)
        sed -i '/#Title/,/}/ s/left = 20%/left = 2%/' $out/theme.txt

        # Center the boot menu (Reverted to the 'mostly centered' 25%)
        sed -i '/#Boot menu/,/}/ s/left = 35%/left = 25%/' $out/theme.txt
      '';
    };
  };
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;

  # Disk Encryption (Additional drives)
  boot.initrd.luks.devices."luks-a96ee21e-bc18-42ab-864c-d3ec22f4247a".device = "/dev/disk/by-uuid/a96ee21e-bc18-42ab-864c-d3ec22f4247a";
  boot.initrd.luks.devices."luks-a2df8182-4853-442b-ba7c-6ca18af8696a".device = "/dev/disk/by-uuid/a2df8182-4853-442b-ba7c-6ca18af8696a";

  # File Systems
  fileSystems."/home/stefan/games" = {
    device = "/dev/disk/by-uuid/af2d7832-b398-49d2-ab40-61aa312dbf83";
    fsType = "ext4";
  };

  # Ensure user ownership of the Games folder
  systemd.tmpfiles.rules = [
    "d /home/stefan/games 0755 stefan users - -"
  ];

  # Load the NVIDIA driver
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true; # Fixes suspend/resume issues
    powerManagement.finegrained = false;
    open = false; # Switch to open kernel modules for better suspend stability on RTX 3080
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Suppress kernel messages during boot (greeter handles the display)
  boot.consoleLogLevel = 0;

  # Fix for Nvidia suspend/wake issues
  boot.kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "mem_sleep_default=deep"
    "quiet"
    "udev.log_level=3"
  ];

  # Disable USB wakeup for mice to prevent accidental wakeups from hibernation
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*Mouse*", ATTR{power/wakeup}="disabled"
  '';

  # Enable Steam & Gamemode
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports for Source Dedicated Server
  };
  programs.gamemode.enable = true;

  # Gaming Specialisation (Steam Big Picture Mode)
  specialisation = {
    gaming-box.configuration = {
      system.nixos.tags = ["gaming-box"];
      programs.hyprland.enable = lib.mkForce false;
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
      };
      programs.gamemode.enable = true;
      environment.sessionVariables = lib.mkForce {};
    };
  };
}
