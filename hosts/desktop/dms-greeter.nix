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
  greeterUsersCacheDir = "${greeterLogDir}/users";
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

  greeterLauncherPatchScript = pkgs.writeText "patch-greeter-launcher.py" (lib.concatStringsSep "\n" [
    "import sys"
    "from pathlib import Path"
    ""
    "launcher = Path(sys.argv[1])"
    "if not launcher.exists():"
    "    sys.exit(0)"
    ""
    "text = launcher.read_text(encoding=\"utf-8\")"
    "old = ("
    "    '    if command -v systemd-cat >/dev/null 2>&1; then\\n'"
    "    '        exec \"$@\" > >(systemd-cat -t \"dms-greeter/$log_tag\" -p info) 2>&1\\n'"
    "    '    fi\\n'"
    "    '\\n'"
    "    '    exec \"$@\"\\n'"
    ")"
    "new = ("
    "    '    if [[ \"$log_tag\" == \"hyprland\" ]]; then\\n'"
    "    '        exec \"$@\" >> \"$CACHE_DIR/hyprland.log\" 2>&1\\n'"
    "    '    fi\\n'"
    "    '\\n'"
    "    '    if command -v systemd-cat >/dev/null 2>&1; then\\n'"
    "    '        exec \"$@\" > >(systemd-cat -t \"dms-greeter/$log_tag\" -p info) 2>&1\\n'"
    "    '    fi\\n'"
    "    '\\n'"
    "    '    exec \"$@\"\\n'"
    ")"
    "if old not in text:"
    "    raise RuntimeError(\"greeter compositor logging block not found\")"
    ""
    "text = text.replace(old, new, 1)"
    ""
    "old_check = ("
    "    \"        if ! command -v start-hyprland >/dev/null 2>&1 && ! command -v Hyprland >/dev/null 2>&1; then\\n\""
    "    \"            echo \\\"Error: neither 'start-hyprland' nor 'Hyprland' was found in PATH\\\" >&2\\n\""
    "    \"            exit 1\\n\""
    "    \"        fi\\n\""
    ")"
    "new_check = ("
    "    \"        if ! command -v Hyprland >/dev/null 2>&1; then\\n\""
    "    \"            echo \\\"Error: Hyprland was not found in PATH\\\" >&2\\n\""
    "    \"            exit 1\\n\""
    "    \"        fi\\n\""
    ")"
    "if old_check not in text:"
    "    raise RuntimeError(\"greeter Hyprland availability check not found\")"
    "text = text.replace(old_check, new_check, 1)"
    ""
    "old_launch = ("
    "    '        if command -v start-hyprland >/dev/null 2>&1; then\\n'"
    "    '            exec_compositor \"hyprland\" start-hyprland -- --config \"$COMPOSITOR_CONFIG\"\\n'"
    "    '        else\\n'"
    "    '            exec_compositor \"hyprland\" Hyprland -c \"$COMPOSITOR_CONFIG\"\\n'"
    "    '        fi\\n'"
    ")"
    "new_launch = '        exec_compositor \"hyprland\" Hyprland -c \"$COMPOSITOR_CONFIG\"\\n'"
    "if old_launch not in text:"
    "    raise RuntimeError(\"greeter Hyprland launch block not found\")"
    "text = text.replace(old_launch, new_launch, 1)"
    ""
    "launcher.write_text(text, encoding=\"utf-8\")"
    ""
  ]);

  greeterBasePackage = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;

  greeterPatchedPackage = greeterBasePackage.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        target_qml="$out/share/quickshell/dms/Services/PortalService.qml"
        if [ -f "$target_qml" ]; then
          chmod u+w "$target_qml"
          ${pkgs.python3}/bin/python3 ${portalServicePatchScript} "$target_qml"
          chmod a-w "$target_qml"
        fi

        target_launcher="$out/share/quickshell/dms/Modules/Greetd/assets/dms-greeter"
        if [ -f "$target_launcher" ]; then
          chmod u+w "$target_launcher"
          ${pkgs.python3}/bin/python3 ${greeterLauncherPatchScript} "$target_launcher"
          chmod a-w "$target_launcher"
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
          disable_splash_rendering = true
        }

        debug {
          disable_logs = true
          enable_stdout_logs = false
          disable_time = true
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
