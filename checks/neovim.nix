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

    local ok, pretty_hover = pcall(require, "pretty_hover")
    if not ok then
      io.stderr:write("pretty_hover must be available for LSP hover rendering\n")
      vim.cmd("cquit")
    end

    local hover_config = pretty_hover.get_config()
    if hover_config.border ~= "rounded" or hover_config.wrap ~= true or hover_config.toggle ~= true then
      io.stderr:write("pretty_hover configuration regressed\n")
      vim.cmd("cquit")
    end

    local hover_map = vim.fn.maparg("K", "n", false, true)
    if type(hover_map) ~= "table" or not hover_map.rhs or not hover_map.rhs:find("pretty_hover", 1, true) then
      io.stderr:write("K must use pretty_hover for LSP hover rendering\n")
      vim.cmd("cquit")
    end

    local parsed = require("pretty_hover.parser").parse({ "@brief Hover docs keep readable prose." })
    if type(parsed.text) ~= "table" or #parsed.text == 0 then
      io.stderr:write("pretty_hover parser returned no hover text\n")
      vim.cmd("cquit")
    end

    local _, hover_win = vim.lsp.util.open_floating_preview(
      parsed.text,
      "markdown",
      { focusable = true, wrap = hover_config.wrap, border = hover_config.border }
    )

    if not vim.api.nvim_win_is_valid(hover_win) then
      io.stderr:write("Neovim LSP hover float was not created\n")
      vim.cmd("cquit")
    end

    if not vim.wo[hover_win].wrap then
      io.stderr:write("Neovim LSP hover floats must wrap readable prose\n")
      vim.cmd("cquit")
    end

    vim.cmd("qa!")
    LUA

    cat > check-clang-format-indent.lua <<'LUA'
    local function fail(message)
      io.stderr:write(message .. "\n")
      vim.cmd("cquit")
    end

    local function write_file(path, text)
      local file = assert(io.open(path, "w"))
      file:write(text)
      file:close()
    end

    local function assert_equal(actual, expected, label)
      if actual ~= expected then
        fail(string.format("%s: got %q, expected %q", label, tostring(actual), tostring(expected)))
      end
    end

    local function assert_buffer_indent(expected)
      assert_equal(vim.bo.shiftwidth, expected.shiftwidth, expected.label .. " shiftwidth")
      assert_equal(vim.bo.tabstop, expected.tabstop, expected.label .. " tabstop")
      assert_equal(vim.bo.expandtab, expected.expandtab, expected.label .. " expandtab")
      assert_equal(vim.bo.softtabstop, expected.softtabstop, expected.label .. " softtabstop")
      assert_equal(vim.bo.cindent, true, expected.label .. " cindent")
    end

    local function open_c_buffer(directory, filename)
      local path = directory .. "/" .. filename
      write_file(path, "int main() {\nreturn 0;\n}\n")
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      if vim.bo.filetype ~= "c" then
        fail("expected C filetype for " .. path .. ", got " .. vim.bo.filetype)
      end
      return path
    end

    local function assert_reindent(expected_prefix, label)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd("normal! ==")
      assert_equal(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], expected_prefix .. "return 0;", label)
    end

    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")

    local fallback_dir = root .. "/fallback"
    vim.fn.mkdir(fallback_dir, "p")
    open_c_buffer(fallback_dir, "fallback.c")
    assert_buffer_indent({
      label = "LLVM fallback",
      shiftwidth = 2,
      tabstop = 8,
      expandtab = true,
      softtabstop = 2,
    })
    assert_reindent("  ", "LLVM fallback nested indentation")

    local four_space_dir = root .. "/four-space"
    vim.fn.mkdir(four_space_dir, "p")
    write_file(four_space_dir .. "/.clang-format", table.concat({
      "BasedOnStyle: LLVM",
      "IndentWidth: 4",
      "TabWidth: 4",
      "UseTab: Never",
      "",
    }, "\n"))
    open_c_buffer(four_space_dir, "four.c")
    assert_buffer_indent({
      label = "project four-space style",
      shiftwidth = 4,
      tabstop = 4,
      expandtab = true,
      softtabstop = 4,
    })
    assert_reindent("    ", "project four-space nested indentation")

    local tabs_dir = root .. "/tabs"
    vim.fn.mkdir(tabs_dir, "p")
    write_file(tabs_dir .. "/.clang-format", table.concat({
      "BasedOnStyle: LLVM",
      "IndentWidth: 8",
      "TabWidth: 8",
      "UseTab: Always",
      "",
    }, "\n"))
    open_c_buffer(tabs_dir, "tabs.c")
    assert_buffer_indent({
      label = "project tab style",
      shiftwidth = 8,
      tabstop = 8,
      expandtab = false,
      softtabstop = -1,
    })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "int main() {", "", "}" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local tab = vim.api.nvim_replace_termcodes("i<Tab><Esc>", true, false, true)
    vim.api.nvim_feedkeys(tab, "xt", false)
    assert_equal(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], "\t", "project tab style Tab key")

    vim.cmd("qa!")
    LUA

    cat > check-go-format.lua <<'LUA'
    local function fail(message)
      io.stderr:write(message .. "\n")
      vim.cmd("cquit")
    end

    local function write_file(path, text)
      local file = assert(io.open(path, "w"))
      file:write(text)
      file:close()
    end

    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local path = root .. "/main.go"
    write_file(path, table.concat({
      "package main",
      "",
      "import \"fmt\"",
      "",
      "func main() {",
      "if true {",
      "fmt.Println(\"ok\")",
      "}",
      "}",
      "",
    }, "\n"))

    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if vim.bo.filetype ~= "go" then
      fail("expected Go filetype for " .. path .. ", got " .. vim.bo.filetype)
    end

    local ok, conform = pcall(require, "conform")
    if not ok then
      fail("conform.nvim must be available")
    end

    local attempted = conform.format({ async = false, timeout_ms = 2000 })
    if attempted ~= true then
      fail("conform did not attempt Go formatting")
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")
    if not text:find("\tif true {", 1, true) or not text:find("\t\tfmt.Println(\"ok\")", 1, true) then
      fail("gofmt did not apply canonical tab indentation")
    end

    vim.cmd("qa!")
    LUA

    ${pkgs.coreutils}/bin/timeout 20s \
      ${desktopHome}/bin/nvim --headless -n -i NONE -u ${desktopNeovimInitFile} \
      +"lua dofile('$PWD/check-lsp-health.lua')"

    ${pkgs.coreutils}/bin/timeout 20s \
      ${desktopHome}/bin/nvim --headless -n -i NONE -u ${desktopNeovimInitFile} \
      +"lua dofile('$PWD/check-clang-format-indent.lua')"

    ${pkgs.coreutils}/bin/timeout 20s \
      ${desktopHome}/bin/nvim --headless -n -i NONE -u ${desktopNeovimInitFile} \
      +"lua dofile('$PWD/check-go-format.lua')"

    touch "$out"
  '';
}
