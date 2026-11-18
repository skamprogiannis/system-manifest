{pkgs}: let
  package = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "modern-web-guidance";
    version = "1.0.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/modern-web-guidance/-/modern-web-guidance-${version}.tgz";
      hash = "sha512-5ztUh5F1p2PewnSkA6EhsGUXqomaZY9qe6iWJCU4JbIQxHTky7s5lMJcPE4EbD1uhbQZIhl0HROH0+s6fIiGzg==";
    };
    nativeBuildInputs = [pkgs.makeWrapper pkgs.python3];
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      runtime="$out/lib/modern-web-guidance"
      skill_runtime="$runtime/skills/modern-web-guidance"
      mkdir -p "$skill_runtime" "$out/bin"
      cp package.json LICENSE THIRD_PARTY_NOTICES "$runtime/"
      upstream=skills/modern-web-guidance
      for resource in gen guides legacy-scan.mjs modern-web.mjs package.json search.mjs skill-version.txt; do
        cp -r "$upstream/$resource" "$skill_runtime/"
      done
      # Retain the npm layout so upstream resolves the release version and data.
      python3 ${./adapt-modern-web-guidance.py} "$skill_runtime" "$out/bin/modern-web-guidance"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/modern-web-guidance" \
        --set DISABLE_TELEMETRY 1 \
        --set ENABLE_FILE_LOGGING false \
        --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.git]} \
        --add-flags "$skill_runtime/modern-web.mjs"
      runHook postInstall
    '';
  };
  skill = pkgs.runCommand "modern-web-guidance-skill" {} ''
    mkdir -p "$out"
    substitute ${./skills/modern-web-guidance/SKILL.md} "$out/SKILL.md" \
      --replace-fail '@cli@' '${package}/bin/modern-web-guidance'
  '';
in {inherit package skill;}
