{
  pkgs,
  inputs,
}:
pkgs.rustPlatform.buildRustPackage {
  pname = "skwd-daemon";
  version = "unstable";
  src = inputs.skwd-wall.inputs.skwd-daemon.outPath;

  cargoHash = "sha256-g2UbjQuhnVAYd5U5j88OKuoA2H2eFFaVYO3HK+okYL8=";
  patches = [
    ./wallpaper/skwd-paper-video-performance.patch
  ];

  nativeBuildInputs = with pkgs; [
    pkg-config
    rustPlatform.bindgenHook
  ];
  buildInputs = with pkgs; [
    alsa-lib.dev
    ffmpeg.dev
    imagemagick
    libglvnd.dev
    libpulseaudio
    wayland.dev
  ];

  postInstall = ''
    install -Dm644 data/skwd-daemon.service $out/lib/systemd/user/skwd-daemon.service
    substituteInPlace $out/lib/systemd/user/skwd-daemon.service \
      --replace-fail "/usr/bin/skwd-daemon" "$out/bin/skwd-daemon"
  '';

  meta = {
    description = "Daemon and CLI for Skwd";
    homepage = "https://github.com/liixini/skwd-daemon";
    license = pkgs.lib.licenses.mit;
    mainProgram = "skwd-daemon";
  };
}
