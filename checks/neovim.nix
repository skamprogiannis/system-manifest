{ctx}: let
  inherit
    (ctx)
    desktopHome
    desktopNeovimInitFile
    neovimLangmapFile
    pkgs
    ;
in {
  neovim-langmap =
    pkgs.runCommand "neovim-langmap-checks" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      set -euo pipefail

      python3 - ${neovimLangmapFile} <<'PY'
      import sys
      from pathlib import Path

      text = Path(sys.argv[1]).read_text(encoding="utf-8")
      uppercase_greek = sorted({ch for ch in text if "\u0391" <= ch <= "\u03a9"})
      if uppercase_greek:
          print(
              "Neovim langmap must not contain uppercase Greek sources: "
              + ", ".join(uppercase_greek),
              file=sys.stderr,
          )
          raise SystemExit(1)

      chunks = []
      chunk = []
      escaped = False
      for ch in text.strip():
          if escaped:
              chunk.append(ch)
              escaped = False
          elif ch == "\\":
              escaped = True
          elif ch == ",":
              chunks.append("".join(chunk))
              chunk = []
          else:
              chunk.append(ch)
      if chunk:
          chunks.append("".join(chunk))

      punctuation_sources = sorted(
          {entry[0] for entry in chunks if entry and entry[0] in {":", ";"}}
      )
      if punctuation_sources:
          print(
              "Neovim langmap must not remap Vim punctuation command sources: "
              + ", ".join(punctuation_sources),
              file=sys.stderr,
          )
          raise SystemExit(1)
      PY

      cat > check-command-key.lua <<'LUA'
      local file = assert(io.open(os.getenv("LANGMAP_FILE"), "r"))
      local langmap = file:read("*a"):gsub("%s+$", "")
      file:close()

      vim.opt.langmap = langmap
      vim.v.errmsg = ""

      local keys = vim.api.nvim_replace_termcodes(":<Esc>", true, false, true)
      vim.api.nvim_feedkeys(keys, "xt", false)

      if vim.v.errmsg ~= "" then
        io.stderr:write("Neovim ':' command key failed under langmap: " .. vim.v.errmsg .. "\n")
        vim.cmd("cquit")
      end

      vim.cmd("qa!")
      LUA

      export HOME="$TMPDIR/home"
      export XDG_CACHE_HOME="$TMPDIR/cache"
      export XDG_CONFIG_HOME="$TMPDIR/config"
      export XDG_STATE_HOME="$TMPDIR/state"
      mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

      LANGMAP_FILE=${neovimLangmapFile} ${pkgs.coreutils}/bin/timeout 10s \
        ${desktopHome}/bin/nvim --headless -n -u NONE -i NONE \
        +"lua dofile('$PWD/check-command-key.lua')"

      touch "$out"
    '';

  neovim-lsp-health = pkgs.runCommand "neovim-lsp-health-check" {} ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_STATE_HOME="$TMPDIR/state"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

    cat > check-lsp-health.lua <<'LUA'
    vim.cmd("checkhealth vim.lsp")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")
    local unknown = {}

    for filetype in text:gmatch("Unknown filetype '([^']+)'") do
      table.insert(unknown, filetype)
    end

    if #unknown > 0 then
      io.stderr:write("Neovim LSP health reported unknown filetypes: " .. table.concat(unknown, ", ") .. "\n")
      vim.cmd("cquit")
    end

    vim.cmd("qa!")
    LUA

    ${pkgs.coreutils}/bin/timeout 20s \
      ${desktopHome}/bin/nvim --headless -n -i NONE -u ${desktopNeovimInitFile} \
      +"lua dofile('$PWD/check-lsp-health.lua')"

    touch "$out"
  '';
}
