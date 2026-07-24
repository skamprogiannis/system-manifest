{lib, ...}: {
  # Portable lab hardware may expose a broken Vulkan implementation to Qt.
  _module.args.skwdAdaptiveRhi = lib.mkForce true;
  _module.args.skwdQsgRhiBackend = lib.mkForce "opengl";
}
