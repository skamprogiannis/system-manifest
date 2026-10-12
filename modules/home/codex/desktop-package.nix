{
  pkgs,
  lib,
  ...
}:
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "chatgpt-desktop";
  version = "26.1007.21434";

  src = pkgs.fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${finalAttrs.version}_amd64.deb";
    hash = "sha256-J2tTQcPXSyYdOtUhBvf6ft3gaEHkdn/ipAy1QJmx8+0=";
  };

  nativeBuildInputs = with pkgs; [dpkg autoPatchelfHook makeWrapper wrapGAppsHook3];
  buildInputs = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libGL
    libusb1
    libxkbcommon
    mesa
    (lib.getLib musl)
    nspr
    nss
    openssl
    pango
    (lib.getLib qt5.qtbase)
    (lib.getLib qt6.qtbase)
    stdenv.cc.cc.lib
    systemd
    tpm2-tss
    zlib
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];
  runtimeDependencies = map lib.getLib [pkgs.libsecret pkgs.libnotify pkgs.vulkan-loader];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin"
    cp -a usr/lib/chatgpt "$out/lib/"
    cp -a usr/share "$out/"
    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix PATH : ${lib.makeBinPath [pkgs.git pkgs.glib pkgs.xdg-utils pkgs.xz]}
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail "Exec=chatgpt %U" "Exec=$out/bin/chatgpt %U" \
      --replace-fail "Comment=ChatGPT by OpenAI" "Comment=ChatGPT with Codex by OpenAI"
    printf '%s\n' 'Keywords=Codex;OpenAI;ChatGPT;AI;' >> "$out/share/applications/chatgpt.desktop"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [pkgs.desktop-file-utils];
  installCheckPhase = ''
    runHook preInstallCheck
    desktop-file-validate "$out/share/applications/chatgpt.desktop"
    test -x "$out/bin/chatgpt"
    test -s "$out/share/pixmaps/chatgpt.png"
    ${pkgs.glibc.bin}/bin/ldd "$out/lib/chatgpt/ChatGPT" > dependencies.txt
    if grep -q 'not found' dependencies.txt; then
      cat dependencies.txt
      exit 1
    fi
    runHook postInstallCheck
  '';

  # Keep the upstream application and bundled Codex resources together.
  dontStrip = true;
  meta = {
    description = "Official ChatGPT desktop app with Codex";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    platforms = ["x86_64-linux"];
    mainProgram = "chatgpt";
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
})
