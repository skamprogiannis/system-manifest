{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  greeterUser = "stefan";
  greeterHome = "/home/${greeterUser}";
  accountsServiceDir = "/var/lib/AccountsService";
  accountsServiceUsersDir = "${accountsServiceDir}/users";
  accountsServiceIconsDir = "${accountsServiceDir}/icons";
  greeterLogDir = "/var/lib/dms-greeter";
  greeterLogPath = "${greeterLogDir}/greeter.log";
  avatarSourceWebp = ./assets/stefan-avatar.webp;

  portalServicePatchScript = pkgs.writeText "patch-greeter-portal-service.py" ''
    import re
    import sys
    from pathlib import Path

    portal_service = Path(sys.argv[1])
    if not portal_service.exists():
        sys.exit(0)

    text = portal_service.read_text(encoding="utf-8")
    signature_match = re.search(r"function\s+getGreeterUserProfileImage\s*\([^)]*\)\s*\{", text)
    if signature_match is None:
        raise RuntimeError("PortalService lookup function signature not found")

    function_start = text.rfind("\n", 0, signature_match.start()) + 1
    opening_brace = text.find("{", signature_match.start())

    depth = 0
    function_end = None
    for index in range(opening_brace, len(text)):
        character = text[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                function_end = index + 1
                break

    if function_end is None:
        raise RuntimeError("PortalService lookup function closing brace not found")

    if function_end < len(text) and text[function_end] == "\n":
        function_end += 1

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

    portal_service.write_text(
        text[:function_start] + new_lookup + "\n" + text[function_end:],
        encoding="utf-8",
    )
  '';

  greeterBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;

  greeterPatchedPackage = greeterBasePackage.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      target_qml="$out/share/quickshell/dms/Services/PortalService.qml"
      if [ -f "$target_qml" ]; then
        chmod u+w "$target_qml"
        ${pkgs.python3}/bin/python3 ${portalServicePatchScript} "$target_qml"
        chmod a-w "$target_qml"
      fi
    '';
  });

  avatarPng = pkgs.runCommand "${greeterUser}-avatar-png" {nativeBuildInputs = [pkgs.ffmpeg];} ''
    mkdir -p "$out"
    ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel error -y \
      -i ${avatarSourceWebp} \
      "$out/${greeterUser}.png"
  '';
in {
  # DMS greeter (greetd + QuickShell) replaces GDM.
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
  ];

  # Keep avatar files and AccountsService profile in sync for the greeter.
  system.activationScripts.accountsServiceAvatar = lib.stringAfter ["users"] ''
    install -dm0755 ${accountsServiceUsersDir} ${accountsServiceIconsDir} ${greeterLogDir}

    cat > ${accountsServiceUsersDir}/${greeterUser} <<'EOF'
    [User]
    Icon=${accountsServiceIconsDir}/${greeterUser}.png
    SystemAccount=false
    EOF
    chmod 0644 ${accountsServiceUsersDir}/${greeterUser}
    chown root:root ${accountsServiceUsersDir}/${greeterUser}

    install -Dm0644 ${avatarSourceWebp} ${accountsServiceIconsDir}/${greeterUser}.webp
    install -Dm0644 ${avatarPng}/${greeterUser}.png ${accountsServiceIconsDir}/${greeterUser}.png
    chmod 0644 ${accountsServiceIconsDir}/${greeterUser}.webp ${accountsServiceIconsDir}/${greeterUser}.png
    chown root:root ${accountsServiceIconsDir}/${greeterUser}.webp ${accountsServiceIconsDir}/${greeterUser}.png
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
