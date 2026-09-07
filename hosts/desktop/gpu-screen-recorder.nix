{...}: {
  # FFmpeg 9 requires NVENC API 13.1, while the packaged NVIDIA 595 driver
  # exposes 13.0. Remove only the FFmpeg compatibility overrides once driver
  # 610+ lands; the independent tray icon path fix must remain.
  nixpkgs.overlays = [
    (_: previous: let
      compatibleBackend = previous.gpu-screen-recorder.override {
        ffmpeg = previous.ffmpeg_8;
      };
    in {
      gpu-screen-recorder = compatibleBackend;
      gpu-screen-recorder-gtk =
        (previous.gpu-screen-recorder-gtk.override {
          gpu-screen-recorder = compatibleBackend;
        }).overrideAttrs (old: {
          # Native tray icons must use Meson's install path instead of /usr/share.
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace src/main.cpp \
                --replace-fail '"/usr/share/icons/hicolor/32x32/status/' 'GSR_ICONS_PATH "/hicolor/32x32/status/'
            '';
        });
    })
  ];
}
