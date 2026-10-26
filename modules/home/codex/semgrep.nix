{pkgs}: let
  upstream = pkgs.semgrep;
  compatiblePatchelf = pkgs.patchelf.overrideAttrs (_: {
    version = "0.15.2";
    src = pkgs.fetchurl {
      url = "https://github.com/NixOS/patchelf/releases/download/0.15.2/patchelf-0.15.2.tar.bz2";
      hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
    };
  });
in
  if upstream.version == "1.180.0"
  then
    upstream.override (
      {
        # This frontend still imports FastMCP, which MCP 2 removed.
        mcp = pkgs.python3Packages.mcp_1;
      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux" && pkgs.patchelf.version == "0.19.2") {
        # Newer patchelf aborts rewriting this wheel's ELF layout. Preserve
        # upstream no-strip/no-shrink handling until either version changes.
        semgrep-core = upstream.semgrep-core.override {patchelf = compatiblePatchelf;};
      }
    )
  else upstream
