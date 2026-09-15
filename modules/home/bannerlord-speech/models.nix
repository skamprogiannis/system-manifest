{
  fetchurl,
  linkFarm,
  lib,
}: let
  kokoroRevision = "f3ff3571791e39611d31c381e3a41a3af07b4987";
  whisperRevision = "5359861c739e955e79d9a303bcbc70fb988958b1";
  kokoroUrl = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/${kokoroRevision}";
  voiceHashes = {
    bf_alice = "sha256-0pJlG2r2wNgXBcJYDctEY/zMD/e41hikcdu05FZVs/M=";
    bf_emma = "sha256-0KQj3qv0pStPSTGMUXQsVOIbuJu76aEhQed1jdtdpwE=";
    bf_isabella = "sha256-zdTDcAOAUQTR0I+x4FhVyPssaN4kym5x8mSjCqpZ7v0=";
    bf_lily = "sha256-bgnC5IHi1TAE1+WufToyU2nhMKb0XDWmAC3nUIS+koU=";
    bm_daniel = "sha256-/D/OTpwS7U28j6loDP5R7hkKlkRM58OtZHVJowgj/F0=";
    bm_fable = "sha256-1Ek18xNSV6kGTfmfAH/BNC/xqnZ1UrSk+kw7Lm5ZB5w=";
    bm_george = "sha256-8byBIhPcWXdHaeXIAASxPut5vXgTCxGy1/k0VC2rgRs=";
    bm_lewis = "sha256-tSBHUNy6AQKdKsnOwXrsOyCm1kBzxXnWlKI8tA7/vQ4=";
  };
in {
  # Official model repositories, pinned independently from engine versions.
  whisper = fetchurl {
    name = "ggml-base.en.bin";
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/${whisperRevision}/ggml-base.en.bin";
    hash = "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=";
  };
  kokoro = fetchurl {
    name = "kokoro-v1_0.pth";
    url = "${kokoroUrl}/kokoro-v1_0.pth";
    hash = "sha256-SW26EY0aWPXz2y78iNvcIW4Eg/yJ/m5H7h8sU/GK0eQ=";
  };
  config = fetchurl {
    name = "kokoro-config.json";
    url = "${kokoroUrl}/config.json";
    hash = "sha256-WrsB4kA7ByvwPQT94WBEPiCdeg2tSaQjvhUZa5tDwX8=";
  };
  voices = linkFarm "kokoro-english-voices" (lib.mapAttrsToList (name: hash: {
      name = "${name}.pt";
      path = fetchurl {
        name = "${name}.pt";
        url = "${kokoroUrl}/voices/${name}.pt";
        inherit hash;
      };
    })
    voiceHashes);
  provenance = {
    kokoro = {
      repository = "https://huggingface.co/hexgrad/Kokoro-82M";
      revision = kokoroRevision;
      licence = "Apache-2.0";
    };
    whisper = {
      repository = "https://huggingface.co/ggerganov/whisper.cpp";
      revision = whisperRevision;
      licence = "MIT";
    };
    voices = builtins.attrNames voiceHashes;
  };
}
