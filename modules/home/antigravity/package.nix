{antigravity-cli, fetchurl}:
antigravity-cli.overrideAttrs (old: {
  version = "1.5.8";
  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.8-4602374149505024/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha512-8I+q7liDJ9uocivcYPJqFPaRWo8tdW7XlZzeCnBtTmL9n4MasaB32s5flHyqpuhRRX31AjGAu40/VDhoBKN4fw==";
  };
  passthru = (old.passthru or {}) // {
    wholeVersion = "1.5.8-4602374149505024";
  };
})
