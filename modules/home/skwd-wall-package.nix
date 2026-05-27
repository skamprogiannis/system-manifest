{
  pkgs,
  inputs,
}: let
  system = pkgs.stdenv.hostPlatform.system;
  skwdWallInput = inputs.skwd-wall;
  quickshellInput = skwdWallInput.inputs.quickshell;
  qsPkgs = quickshellInput.inputs.nixpkgs.legacyPackages.${system};

  quickshellWithModules = quickshellInput.packages.${system}.default.withModules (with qsPkgs.qt6; [
    qtimageformats
    qtmultimedia
    qtsvg
    qt5compat
    qtwayland
  ]);

  daemon = import ./skwd-daemon-package.nix {inherit pkgs inputs;};

  runtimeDeps = with pkgs; [
    daemon
    matugen
    ffmpeg
    imagemagick
    inotify-tools
    sqlite
    curl
    file
    mpvpaper
    jq
    awww
  ];

  daemonDeps = runtimeDeps ++ [quickshellWithModules];

  fonts = with pkgs; [
    nerd-fonts.symbols-only
    roboto
    roboto-mono
    material-design-icons
  ];
in
  pkgs.stdenv.mkDerivation {
    pname = "skwd-wall";
    version = "unstable";
    src = skwdWallInput.outPath;

    nativeBuildInputs = [pkgs.makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/skwd-wall
      cp -a shell.qml qml/ $out/share/skwd-wall/

      mkdir -p $out/share/skwd-wall/data
      cp -a data/matugen/ $out/share/skwd-wall/data/
      cp -a data/scripts/ $out/share/skwd-wall/data/
      install -Dm644 data/config.json.example $out/share/skwd-wall/data/config.json.example

      install -Dm644 data/skwd-wall.desktop $out/share/applications/skwd-wall.desktop

      makeWrapper ${quickshellWithModules}/bin/quickshell $out/bin/skwd-wall \
        --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
        --add-flags "-p $out/share/skwd-wall/shell.qml"

      makeWrapper ${daemon}/bin/skwd $out/bin/skwd \
        --prefix PATH : ${pkgs.lib.makeBinPath daemonDeps} \
        --set SKWD_SHELL_QML "$out/share/skwd-wall/shell.qml" \
        --set SKWD_DATA_DIR "$out/share/skwd-wall/data"

      makeWrapper ${daemon}/bin/skwd-daemon $out/bin/skwd-daemon \
        --prefix PATH : ${pkgs.lib.makeBinPath daemonDeps} \
        --set SKWD_SHELL_QML "$out/share/skwd-wall/shell.qml" \
        --set SKWD_DATA_DIR "$out/share/skwd-wall/data"

      mkdir -p $out/lib/systemd/user
      substitute ${daemon}/lib/systemd/user/skwd-daemon.service \
        $out/lib/systemd/user/skwd-daemon.service \
        --replace-fail "${daemon}/bin/skwd-daemon" "$out/bin/skwd-daemon"

      install -Dm644 LICENSE $out/share/licenses/skwd-wall/LICENSE

      mkdir -p $out/share/fonts
      for font in ${pkgs.lib.concatMapStringsSep " " toString fonts}; do
        if [ -d "$font/share/fonts" ]; then
          for f in $(find "$font/share/fonts" -type f); do
            ln -sf "$f" "$out/share/fonts/$(basename "$f")"
          done
        fi
      done

      runHook postInstall
    '';

    meta = {
      description = "Quickshell-based image, video & Wallpaper Image wallpaper selector with color sorting, Matugen integration, and more";
      homepage = "https://github.com/liixini/skwd-wall";
      license = pkgs.lib.licenses.mit;
      mainProgram = "skwd-wall";
    };
  }
