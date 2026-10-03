{
  lib,
  runCommand,
  callPackage,
  makeWrapper,
  python313,
  cudaPackages_13_0,
  whisper-cpp,
  pipewire,
  systemd,
  dictationOnly ? false,
}: let
  models = callPackage ./models.nix {};
  # CUDA is confined to this Python package set; desktop dictation stays CPU-only.
  speechPython = python313.override {
    packageOverrides = final: prev: {
      cuda-bindings = prev.cuda-bindings.override {cudaPackages = cudaPackages_13_0;};
      torch-bin = prev.torch-bin.override {
        cudaPackages = cudaPackages_13_0;
        cuda-bindings = final.cuda-bindings;
        # Torch requires setuptools <82; pkg_resources remains in this pinned variant.
        setuptools = prev.setuptools_80;
      };
      # These English frontend dependencies also propagate setuptools at runtime.
      spacy = prev.spacy.override {setuptools = prev.setuptools_80;};
      langcodes = prev.langcodes.override {setuptools = prev.setuptools_80;};
      torch = final.torch-bin;
      torchvision = prev.torchvision-bin.override {
        cudaPackages = cudaPackages_13_0;
        torch-bin = final.torch-bin;
      };
    };
  };
  python =
    if dictationOnly
    then python313
    else speechPython.withPackages (ps: [ps.kokoro ps.soundfile ps.spacy-models.en_core_web_sm]);
  whisper = whisper-cpp.override {
    cudaSupport = false;
    rocmSupport = false;
    vulkanSupport = false;
  };
  engineEnvironment =
    {
      WHISPER_BIN = "${whisper}/bin/whisper-cli";
      WHISPER_MODEL = toString models.whisper;
      PW_RECORD_BIN = "${pipewire}/bin/pw-record";
      OMP_NUM_THREADS = "2";
      OPENBLAS_NUM_THREADS = "2";
      MKL_NUM_THREADS = "2";
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
    }
    // lib.optionalAttrs dictationOnly {CUDA_VISIBLE_DEVICES = "";}
    // lib.optionalAttrs (!dictationOnly) {
      BANNERLORD_SPEECH_DEVICE = "auto";
      KOKORO_MODEL = toString models.kokoro;
      KOKORO_CONFIG = toString models.config;
      KOKORO_VOICES = toString models.voices;
      HF_HUB_OFFLINE = "1";
      HF_HUB_DISABLE_TELEMETRY = "1";
      TRANSFORMERS_OFFLINE = "1";
      TOKENIZERS_PARALLELISM = "false";
    };
  wrapperArguments = lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "${
      if name == "BANNERLORD_SPEECH_DEVICE"
      then "--set-default"
      else "--set"
    } ${name} ${lib.escapeShellArg value}")
    engineEnvironment);
in
  runCommand (
    if dictationOnly
    then "desktop-dictation-runtime-0.1"
    else "bannerlord-speech-runtime-0.1"
  ) {
    nativeBuildInputs = [python makeWrapper];
    passthru = {inherit python whisper models engineEnvironment speechPython;};
  } ''
    mkdir -p "$out/lib" "$out/bin"
    cp ${./service.py} "$out/lib/service.py"
    cp ${./engine.py} "$out/lib/engine.py"
    python3 -m py_compile "$out"/lib/*.py
    rm -r "$out/lib/__pycache__"
    makeWrapper ${python}/bin/python3 "$out/bin/bannerlord-speech-service" \
      --add-flags "$out/lib/service.py" \
      ${wrapperArguments}
    ${lib.optionalString (!dictationOnly) ''
      mkdir -p "$out/share/bannerlord-speech"
      cp ${./control.py} "$out/lib/control.py"
      python3 -m py_compile "$out/lib/control.py"
      rm -rf "$out/lib/__pycache__"
      cat > "$out/share/bannerlord-speech/models.json" <<'JSON'
      ${builtins.toJSON models.provenance}
      JSON
      makeWrapper ${python313}/bin/python3 "$out/bin/bannerlord-speech" \
        --add-flags "$out/lib/control.py" \
        --prefix PATH : ${lib.makeBinPath [systemd]}
    ''}
  ''
