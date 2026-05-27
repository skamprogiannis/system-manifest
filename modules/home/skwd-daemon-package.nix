{
  pkgs,
  inputs,
}:
pkgs.rustPlatform.buildRustPackage {
  pname = "skwd-daemon";
  version = "unstable";
  src = inputs.skwd-wall.inputs.skwd-daemon.outPath;

  cargoHash = "sha256-+go8PEM9X4C/+3wSNoEEdn8vkVV/S9NmqS66d0mD6pk=";

  nativeBuildInputs = with pkgs; [pkg-config];
  buildInputs = with pkgs; [imagemagick];

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
