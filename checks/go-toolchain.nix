{ctx}: let
  go = ctx.homePackage "desktop" "go";
  shared = builtins.all (host: (ctx.homePackage host "go").outPath == go.outPath) ctx.registry.host;
in {
  go-toolchain = assert shared;
    ctx.pkgs.runCommand "go-toolchain-check" {
      nativeBuildInputs = [go ctx.pkgs.stdenv.cc];
    } ''
      export GOCACHE="$TMPDIR/go-cache" GOTOOLCHAIN=local
      test "$(go env GOVERSION)" = go1.27.4
      cat > main.go <<'GO'
      package main
      /* int answer(void) { return 42; } */
      import "C"
      import "fmt"
      func main() { fmt.Println(C.answer()) }
      GO
      gofmt -w main.go
      test -z "$(gofmt -l main.go)"
      go build -o smoke main.go
      test "$(./smoke)" = 42
      touch "$out"
    '';
}
