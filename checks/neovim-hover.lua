local api = vim.api
local original_request = vim.lsp.buf_request_all
local original_open = vim.ui.open
local original_columns = vim.o.columns
local original_lines = vim.o.lines
vim.o.columns = 97
vim.o.lines = 40

local source_win = api.nvim_get_current_win()
api.nvim_win_set_width(source_win, 97)
local source = api.nvim_create_buf(false, true)
api.nvim_win_set_buf(source_win, source)
api.nvim_buf_set_lines(source, 0, -1, false, { 'http.HandleFunc', 'next line', 'last line' })
local calls = 0
local pending
vim.lsp.buf_request_all = function(buf, method, params, callback)
  assert(
    buf == source and method == 'textDocument/hover',
    'K must request LSP hover for the source buffer'
  )
  assert(type(params) == 'function', 'hover positions must use each client encoding')
  calls = calls + 1
  pending = callback
  return function() end
end
local function hover(contents)
  vim.cmd('normal K')
  assert(pending, 'K must start an LSP request')
  local callback = pending
  pending = nil
  callback({ [1] = { result = { contents = contents } } })
  local win = vim.b[source].lsp_floating_preview
  assert(win and api.nvim_win_is_valid(win), 'hover must create a valid float')
  return api.nvim_win_get_buf(win), win
end
local function close(win)
  if api.nvim_win_is_valid(win) then
    api.nvim_win_close(win, true)
  end
  api.nvim_set_current_win(source_win)
end
local function text(buf)
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end
local function link(buf, url)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    if mark[4].url == url then
      return mark
    end
  end
  error('rendered link lost its original destination: ' .. url)
end

local uri =
  'file:///nix/store/i77g9dmcd399rmxk8688qfr4g2wzgk37-go-1.26.7/share/go/src/net/http/server.go'
local prose = 'HandleFunc registers the handler function for the given pattern in [DefaultServeMux]('
  .. uri
  .. '#2588,5). The documentation for [ServeMux]('
  .. uri
  .. '#2575,6) explains how patterns are matched.'
local buf, win = hover({ kind = 'markdown', value = prose })
assert(
  not text(buf):find('file://', 1, true),
  'concealed URLs must not occupy rendered buffer columns'
)
assert(
  api.nvim_win_text_height(win, {}).all == 2,
  'long Go source links must occupy only two visible prose rows at width 93'
)
link(buf, uri .. '#2588,5')
link(buf, uri .. '#2575,6')
local prior_calls = calls
vim.cmd('normal K')
assert(api.nvim_get_current_win() == win, 'second K must focus the existing hover')
assert(calls == prior_calls, 'focusing the hover must not request documentation again')
vim.cmd('normal q')
assert(not api.nvim_win_is_valid(win), 'q must close a focused hover')
api.nvim_set_current_win(source_win)

vim.cmd('vsplit')
local split = api.nvim_get_current_win()
api.nvim_set_current_win(source_win)
api.nvim_win_set_width(source_win, 43)
local wrapped_url = uri .. '#2588,5'
buf, win = hover({
  kind = 'markdown',
  value = '[DefaultServeMux documentation that wraps across several lines](' .. wrapped_url .. ')',
})
local wrapped_links = 0
for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
  if mark[4].url == wrapped_url then
    wrapped_links = wrapped_links + 1
  end
end
assert(
  wrapped_links >= 2,
  'narrow hovers must preserve a clickable URL on every wrapped label segment'
)
assert(
  api.nvim_win_text_height(win, {}).all == api.nvim_buf_line_count(buf),
  'narrow hover wrapping must count visible text only'
)
close(win)
api.nvim_win_close(split, true)

buf, win = hover({ kind = 'plaintext', value = 'literal [text](not-a-link) and *stars*' })
assert(
  text(buf) == 'literal [text](not-a-link) and *stars*',
  'plaintext hover must preserve literal markup'
)
close(win)

buf, win = hover({
  kind = 'markdown',
  value = '```go\nfunc http.HandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request))\n```\n\n---\n\n'
    .. prose
    .. '\n\n---\n\n[http.HandleFunc on pkg.go.dev](https://pkg.go.dev/net/http#HandleFunc)',
})
assert(text(buf):find('func http.HandleFunc', 1, true), 'Go signature must remain readable')
assert(
  api.nvim_win_text_height(win, {}).all == 6,
  'full Go hover must use six rows without extra padding around its dividers'
)
link(buf, uri .. '#2588,5')
link(buf, uri .. '#2575,6')
local footer = link(buf, 'https://pkg.go.dev/net/http#HandleFunc')
local footer_opened
vim.ui.open = function(url)
  footer_opened = url
end
vim.cmd('normal K')
api.nvim_win_set_cursor(win, { footer[2] + 1, footer[3] })
vim.cmd('normal gx')
assert(
  footer_opened == 'https://pkg.go.dev/net/http#HandleFunc',
  'compacting dividers must preserve footer link navigation'
)
vim.ui.open = original_open
local syntax = false
for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
  if (mark[4].hl_group or ''):match('^@.*%.go$') then
    syntax = true
  end
end
assert(syntax, 'Go code blocks must retain treesitter syntax highlighting')
close(win)

buf, win = hover({
  kind = 'markdown',
  value = '```go\nfunc Before() {}\n\n```\n\n---\n\n```go\n\nfunc After() {}\n```\n\nfirst paragraph\n\nsecond paragraph',
})
local rendered = api.nvim_buf_get_lines(buf, 0, -1, false)
assert(rendered[2] == '', 'a blank code row before a divider must survive compaction')
local after_row
for index, line in ipairs(rendered) do
  if line == 'func After() {}' then
    after_row = index - 1
  end
end
assert(
  after_row and rendered[after_row] == '',
  'a blank code row after a divider must survive compaction'
)
assert(
  text(buf):find('first paragraph\n\nsecond paragraph', 1, true),
  'ordinary paragraph separation must survive compaction'
)
local remapped_syntax = false
for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
  if mark[2] == after_row and (mark[4].hl_group or ''):match('^@.*%.go$') then
    remapped_syntax = true
  end
end
assert(remapped_syntax, 'code syntax following a compacted divider must retain its rendered row')
close(win)

vim.cmd('normal K')
local combined = pending
pending = nil
combined({
  [2] = {
    result = { contents = { kind = 'markdown', value = '[second server](' .. uri .. '#2575,6)' } },
  },
  [1] = { result = { contents = { kind = 'plaintext', value = 'first server *literal*' } } },
})
win = vim.b[source].lsp_floating_preview
buf = api.nvim_win_get_buf(win)
assert(
  text(buf):find('first server *literal*', 1, true),
  'mixed-client plaintext must remain literal'
)
assert(text(buf):find('second server', 1, true), 'multiple clients must retain their documentation')
link(buf, uri .. '#2575,6')
close(win)

local destination = vim.fn.tempname() .. '.go'
vim.fn.writefile({ 'package main', 'func Home() {}', '// last' }, destination)
for _, fragment in ipairs({ '#2,3', '#L2' }) do
  local url = vim.uri_from_fname(destination) .. fragment
  buf, win = hover({ kind = 'markdown', value = '[Home](' .. url .. ')' })
  vim.cmd('normal K')
  local mark = link(buf, url)
  api.nvim_win_set_cursor(win, { mark[2] + 1, mark[3] })
  vim.cmd('normal \r')
  assert(
    api.nvim_get_current_win() == source_win,
    'source links must open in the originating window'
  )
  assert(api.nvim_buf_get_name(0) == destination, 'source link must open its file URI')
  local cursor = api.nvim_win_get_cursor(0)
  assert(
    cursor[1] == 2 and cursor[2] == (fragment == '#2,3' and 2 or 0),
    'source link must preserve line and column'
  )
  api.nvim_win_set_buf(source_win, source)
end
api.nvim_buf_delete(vim.fn.bufnr(destination), { force = true })
vim.fn.delete(destination)

local opened
vim.ui.open = function(url)
  opened = url
end
local url = 'https://pkg.go.dev/net/http#HandleFunc'
buf, win = hover({ kind = 'markdown', value = '[online docs](' .. url .. ')' })
vim.cmd('normal K')
local mark = link(buf, url)
api.nvim_win_set_cursor(win, { mark[2] + 1, mark[3] })
vim.cmd('normal gx')
assert(opened == url, 'gx must open the original external URL')
close(win)

vim.cmd('normal K')
local callback = pending
pending = nil
api.nvim_win_set_cursor(source_win, { 2, 0 })
callback({ [1] = { result = { contents = { kind = 'markdown', value = 'stale docs' } } } })
assert(
  not vim.b[source].lsp_floating_preview,
  'late replies for an old cursor position must not open a hover'
)

buf, win = hover({ kind = 'markdown', value = '**fresh docs**' })
api.nvim_exec_autocmds('CursorMoved', { buffer = source })
assert(
  vim.wait(100, function()
    return not api.nvim_win_is_valid(win)
  end),
  'moving the source cursor must close the hover'
)
vim.cmd('normal K')
callback = pending
pending = nil
callback({
  [1] = { result = { contents = { kind = 'markdown', value = '' } } },
  [2] = { error = { message = 'unavailable' } },
})
assert(
  not vim.b[source].lsp_floating_preview,
  'empty or failed replies must not leave a blank hover'
)

vim.lsp.buf_request_all = original_request
vim.ui.open = original_open
vim.o.columns = original_columns
vim.o.lines = original_lines
api.nvim_buf_delete(source, { force = true })
print('Neovim Markdown hover checks passed')
vim.cmd('qa!')
