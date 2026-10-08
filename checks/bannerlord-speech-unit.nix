{ctx}: let
  inherit (ctx) pkgs;
  python = pkgs.python313.withPackages (ps: [ps.numpy ps.soundfile]);
in {
  bannerlord-speech-unit =
    pkgs.runCommand "bannerlord-speech-unit-check" {
      nativeBuildInputs = [python];
    } ''
      export PYTHONDONTWRITEBYTECODE=1
      export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2
      mkdir source
      cp ${../modules/home/bannerlord-speech/service.py} source/service.py
      cp ${../modules/home/bannerlord-speech/engine.py} source/engine.py
      cp ${../modules/home/bannerlord-speech/test_service.py} source/test_service.py
      cp ${../modules/home/bannerlord-speech/test_engine.py} source/test_engine.py
      python3 -m unittest discover -s source -p 'test_*.py' -v
      touch "$out"
    '';
}
