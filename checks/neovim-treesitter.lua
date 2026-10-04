local samples = {
  go = 'package main\nfunc main() {\n  println("hello")\n}\n',
  c = 'int main() {\n  return 0;\n}\n',
  lua = 'local function hello()\n  return 42\nend\n',
  python = 'def hello():\n    return 42\n',
  javascript = 'function hello() {\n  return 42;\n}\n',
  nix = '{ pkgs, ... }: {\n  home.packages = [ pkgs.git ];\n}\n',
  markdown = '# Heading\n\n```go\npackage main\n```\n',
  css = 'main {\n  color: red;\n}\n',
  html = '<main>\n  <p>Hello</p>\n</main>\n',
}
for lang, sample in pairs(samples) do
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo.filetype = lang
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(sample, '\n', { plain = true }))
  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = assert(parser:parse()[1], lang .. ' tree missing')
  assert(not tree:root():has_error(), lang .. ' parse error')
  local query = assert(vim.treesitter.query.get(lang, 'highlights'), lang .. ' highlights missing')
  local captures = 0
  for _ in query:iter_captures(tree:root(), bufnr, 0, -1) do captures = captures + 1 end
  assert(captures > 0, lang .. ' highlights empty')
  vim.treesitter.start(bufnr, lang)
  if lang == 'go' then
    local textobjects = assert(vim.treesitter.query.get(lang, 'textobjects'))
    local found = false
    for id, node in textobjects:iter_captures(tree:root(), bufnr, 0, -1) do
      if textobjects.captures[id] == 'function.outer' then
        assert(vim.treesitter.get_node_text(node, bufnr):find('func main()', 1, true))
        found = true
      end
    end
    assert(found, 'Go function textobject missing')
    assert(vim.treesitter.query.get(lang, 'folds'), 'Go folds missing')
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.cmd('normal! zx')
    assert(vim.fn.foldlevel(3) > 0, 'Go function folding failed')
  end
  print(lang .. ': parse/highlight OK')
end
vim.cmd('qa!')
