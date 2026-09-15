{
  runCommand,
  python3,
}:
runCommand "bannerlord-codex-runtime-0.1" {
  nativeBuildInputs = [python3];
} ''
  mkdir -p "$out/lib"
  cp ${./adapter.py} "$out/lib/adapter.py"
  cp ${./codex_runner.py} "$out/lib/codex_runner.py"
  cp ${./model-instructions.txt} "$out/lib/model-instructions.txt"
  cp ${./response.schema.json} "$out/lib/response.schema.json"
  cp ${./preflight.py} "$out/lib/preflight.py"
  cp ${./control.py} "$out/lib/control.py"
  python3 -m py_compile "$out"/lib/*.py
''
