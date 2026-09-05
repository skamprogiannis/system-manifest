{...}: {
  # FFmpeg 9 requires NVENC API 13.1, while the packaged NVIDIA 595 driver
  # exposes 13.0. Remove this compatibility overlay once driver 610+ lands.
  nixpkgs.overlays = [
    (_: previous: let
      compatibleBackend = previous.gpu-screen-recorder.override {
        ffmpeg = previous.ffmpeg_8;
      };
    in {
      gpu-screen-recorder = compatibleBackend;
      gpu-screen-recorder-gtk = previous.gpu-screen-recorder-gtk.override {
        gpu-screen-recorder = compatibleBackend;
      };
    })
  ];
}
