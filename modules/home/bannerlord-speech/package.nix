{
  lib,
  runCommand,
  callPackage,
  makeWrapper,
  python313,
  whisper-cpp,
  pipewire,
  systemd,
}: let
  models = callPackage ./models.nix {};
  python = python313.withPackages (ps: [ps.kokoro ps.soundfile ps.spacy-models.en_core_web_sm]);
  whisper = whisper-cpp.override {
    cudaSupport = false;
    rocmSupport = false;
    vulkanSupport = false;
  };
  engineEnvironment = {
    WHISPER_BIN = "${whisper}/bin/whisper-cli";
    WHISPER_MODEL = toString models.whisper;
    KOKORO_MODEL = toString models.kokoro;
    KOKORO_CONFIG = toString models.config;
    KOKORO_VOICES = toString models.voices;
    PW_RECORD_BIN = "${pipewire}/bin/pw-record";
    OMP_NUM_THREADS = "2";
    OPENBLAS_NUM_THREADS = "2";
    MKL_NUM_THREADS = "2";
    HF_HUB_OFFLINE = "1";
    HF_HUB_DISABLE_TELEMETRY = "1";
    TRANSFORMERS_OFFLINE = "1";
    TOKENIZERS_PARALLELISM = "false";
    CUDA_VISIBLE_DEVICES = "";
    PYTHONDONTWRITEBYTECODE = "1";
    PYTHONUNBUFFERED = "1";
  };
  wrapperArguments = lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "--set ${name} ${lib.escapeShellArg value}") engineEnvironment);
in
  runCommand "bannerlord-speech-runtime-0.1" {
    nativeBuildInputs = [python makeWrapper];
    passthru = {inherit python whisper models engineEnvironment;};
  } ''
    mkdir -p "$out/lib" "$out/bin" "$out/share/bannerlord-speech"
    cp ${./service.py} "$out/lib/service.py"
    cp ${./engine.py} "$out/lib/engine.py"
    cp ${./control.py} "$out/lib/control.py"
    python3 -m py_compile "$out"/lib/*.py
    rm -r "$out/lib/__pycache__"
    cat > "$out/share/bannerlord-speech/models.json" <<'JSON'
    ${builtins.toJSON models.provenance}
    JSON
    makeWrapper ${python}/bin/python3 "$out/bin/bannerlord-speech-service" \
      --add-flags "$out/lib/service.py" \
      ${wrapperArguments}
    makeWrapper ${python313}/bin/python3 "$out/bin/bannerlord-speech" \
      --add-flags "$out/lib/control.py" \
      --prefix PATH : ${lib.makeBinPath [systemd]}
  ''
