{pkgs}: let
  version = "0.12.4";
  src = pkgs.fetchFromGitHub {
    owner = "open-webui";
    repo = "open-webui";
    tag = "v${version}";
    hash = "sha256-WGKM0Y63E9e1GEsxRt4nfJh+FoBgCBc/YDcwWbWksl4=";
  };
  # PostHog's test instrumentation still targets MCP 1; WebUI itself uses MCP 2.
  pythonPackages = pkgs.python3Packages.overrideScope (final: prev: {
    posthog = prev.posthog.override {mcp = final.mcp_1;};
  });
  base = pkgs.open-webui.override {python3Packages = pythonPackages;};
  # Update both halves together while retaining Nixpkgs' packaging hooks.
  frontend = base.frontend.overrideAttrs {
    inherit version src;
    name = "open-webui-frontend-${version}";
    npmDeps = pkgs.fetchNpmDeps {
      inherit src;
      name = "open-webui-frontend-${version}-npm-deps";
      hash = "sha256-CB4r96Rd6/i33Dzq3J0iou7XRjcS9msmndqE0GaVebg=";
    };
  };
in
  base.overridePythonAttrs (old: {
    inherit version src;
    makeWrapperArgs =
      map (
        pkgs.lib.replaceStrings
        ["${base.frontend}"]
        ["${frontend}"]
      )
      old.makeWrapperArgs;
    passthru = old.passthru // {inherit frontend;};
    meta =
      old.meta
      // {
        changelog = "https://github.com/open-webui/open-webui/blob/v${version}/CHANGELOG.md";
      };
  })
