{pkgs}: let
  version = "0.12.2";
  src = pkgs.fetchFromGitHub {
    owner = "open-webui";
    repo = "open-webui";
    tag = "v${version}";
    hash = "sha256-e7A2wcOoRQAKKZiXr/mGcgicjWHlkUuhkvsGw70CuIo=";
  };
  # Update both halves together while retaining Nixpkgs' packaging hooks.
  frontend = pkgs.open-webui.frontend.overrideAttrs {
    inherit version src;
    name = "open-webui-frontend-${version}";
    npmDeps = pkgs.fetchNpmDeps {
      inherit src;
      name = "open-webui-frontend-${version}-npm-deps";
      hash = "sha256-4rZUxkp/VMc3sp5fittjs5BxdJ4qGTqfVjeABxuHrgw=";
    };
  };
in
  pkgs.open-webui.overridePythonAttrs (old: {
    inherit version src;
    dependencies = old.dependencies ++ (with pkgs.python3Packages; [pyotp qrcode]);
    makeWrapperArgs =
      map (
        pkgs.lib.replaceStrings
        ["${pkgs.open-webui.frontend}"]
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
