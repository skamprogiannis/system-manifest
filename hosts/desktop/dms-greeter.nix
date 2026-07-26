{
  pkgs,
  lib,
  config,
  ...
}: let
  greeterUser = "stefan";
  greeterHome = "/home/${greeterUser}";
  accountsServiceDir = "/var/lib/AccountsService";
  accountsServiceUsersDir = "${accountsServiceDir}/users";
  accountsServiceIconsDir = "${accountsServiceDir}/icons";
  greeterLogDir = "/var/lib/dms-greeter";
  greeterLogPath = "${greeterLogDir}/greeter.log";
  greeterUsersCacheDir = "${greeterLogDir}/users";
  avatarSourceWebp = ./assets/stefan-avatar.webp;

  avatarPng = pkgs.runCommand "${greeterUser}-avatar-png" {nativeBuildInputs = [pkgs.ffmpeg];} ''
    mkdir -p "$out"
    ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel error -y \
      -i ${avatarSourceWebp} \
      "$out/${greeterUser}.png"
  '';
in {
  # DMS greeter (greetd + QuickShell) replaces GDM.
  services.displayManager.gdm.enable = false;

  programs.dms-greeter = {
    enable = true;
    compositor = {
      name = "hyprland";
      customConfig = ''
        misc {
          disable_hyprland_logo = true
        }
      '';
    };
    configHome = greeterHome;
    logs.save = true;
    logs.path = greeterLogPath;
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
  users.users.${greeterUser}.extraGroups = lib.mkAfter ["greeter"];
  systemd.tmpfiles.rules = [
    "d /var/cache/dms-greeter 2775 root greeter - -"
    "z /var/cache/dms-greeter 2775 root greeter - -"
  ];

  # Keep avatar files and AccountsService profile in sync for the greeter.
  system.activationScripts.accountsServiceAvatar = lib.stringAfter ["users"] ''
    install -dm0755 ${accountsServiceUsersDir} ${accountsServiceIconsDir} ${greeterLogDir} ${greeterUsersCacheDir}/${greeterUser}

    cat > ${accountsServiceUsersDir}/${greeterUser} <<'EOF'
    [User]
    Icon=${accountsServiceIconsDir}/${greeterUser}.png
    SystemAccount=false
    EOF
    chmod 0644 ${accountsServiceUsersDir}/${greeterUser}
    chown root:root ${accountsServiceUsersDir}/${greeterUser}

    install -Dm0644 ${avatarSourceWebp} ${accountsServiceIconsDir}/${greeterUser}.webp
    install -Dm0644 ${avatarPng}/${greeterUser}.png ${accountsServiceIconsDir}/${greeterUser}
    install -Dm0644 ${avatarPng}/${greeterUser}.png ${accountsServiceIconsDir}/${greeterUser}.png
    chmod 0644 ${accountsServiceIconsDir}/${greeterUser} ${accountsServiceIconsDir}/${greeterUser}.webp ${accountsServiceIconsDir}/${greeterUser}.png
    chown root:root ${accountsServiceIconsDir}/${greeterUser} ${accountsServiceIconsDir}/${greeterUser}.webp ${accountsServiceIconsDir}/${greeterUser}.png

    install -Dm0644 ${avatarPng}/${greeterUser}.png ${greeterUsersCacheDir}/${greeterUser}/profile.png
    chmod 0644 ${greeterUsersCacheDir}/${greeterUser}/profile.png
    chown root:greeter ${greeterUsersCacheDir}/${greeterUser} ${greeterUsersCacheDir}/${greeterUser}/profile.png
  '';

  # System-wide cursor theme (needed for greeter and other non-HM contexts).
  environment.variables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # DMS greeter shells out to bash+dbus-send for user profile icons.
  systemd.services.greetd.path = with pkgs; [bash dbus gnugrep gnused systemd];

  # Ensure greeter DBus queries and Qt image loaders resolve correctly.
  systemd.services.greetd.environment = {
    DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
    QT_PLUGIN_PATH = lib.concatStringsSep ":" [
      "${pkgs.qt6.qtbase}/lib/qt-6/plugins"
      "${pkgs.qt6.qtimageformats}/lib/qt-6/plugins"
    ];
  };
}
