{
  config,
  lib,
  ...
}: {
  imports = [
    ../player2-ai-influence
    ../bannerlord-codex
    ../bannerlord-speech
  ];

  options.system_manifest.bannerlord.enable = lib.mkEnableOption "Bannerlord AI and speech tooling";
}
