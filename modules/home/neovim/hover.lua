local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace('hover_docs')
local request_id = 0

local function append_content(content, part)
  local offset = #content.lines
  vim.list_extend(content.lines, part.lines)
  for _, key in ipairs({ 'highlights', 'link_metadata' }) do
    for _, entry in ipairs(part[key] or {}) do
      entry.line = entry.line + offset
      table.insert(content[key], entry)
    end
  end
  for _, block in ipairs(part.code_blocks or {}) do
    block.start_line = block.start_line + offset
    block.end_line = block.end_line + offset
    table.insert(content.code_blocks, block)
  end
end

local function render(results, width)
  local Builder = require('md-render.content_builder').ContentBuilder
  local content = { lines = {}, highlights = {}, link_metadata = {}, code_blocks = {} }
  local clients = vim.tbl_keys(results)
  table.sort(clients)
  for _, client_id in ipairs(clients) do
    local response = results[client_id]
    local contents = not response.error and response.result and response.result.contents
    if contents then
      local lines = vim.lsp.util.convert_input_to_markdown_lines(contents)
      if #lines > 0 then
        if #content.lines > 0 then
          table.insert(content.lines, string.rep('─', width))
        end
        if type(contents) == 'table' and contents.kind == 'plaintext' then
          vim.list_extend(content.lines, lines)
        else
          local builder = Builder.new()
          -- Scaled headings reserve extra rows for terminal glyph painting;
          -- a documentation hover uses ordinary text cells.
          builder:render_document(lines, { max_width = width, indent = '', text_scale = false })
          append_content(content, builder:result())
        end
      end
    end
  end
  return content
end

local function open_link(content, win, source_win)
  local cursor = api.nvim_win_get_cursor(win)
  for _, link in ipairs(content.link_metadata) do
    if link.line == cursor[1] - 1 and cursor[2] >= link.col_start and cursor[2] < link.col_end then
      if not link.url:match('^file://') then
        vim.ui.open(link.url)
        return
      end
      local uri, fragment = link.url:match('^(.-)#(.*)$')
      uri = uri or link.url
      -- gopls uses one-based #line,column; other servers use #Lline.
      local row, col = (fragment or ''):match('^L?(%d+)[,:]?C?(%d*)')
      row, col = tonumber(row) or 1, tonumber(col) or 1
      if not api.nvim_win_is_valid(source_win) then
        return
      end
      api.nvim_set_current_win(source_win)
      api.nvim_win_close(win, true)
      local buf = vim.uri_to_bufnr(uri)
      vim.fn.bufload(buf)
      row = math.max(1, math.min(row, api.nvim_buf_line_count(buf)))
      local position = { line = row - 1, character = math.max(0, col - 1) }
      vim.lsp.util.show_document(
        { uri = uri, range = { start = position, ['end'] = position } },
        'utf-8',
        { focus = true }
      )
      return
    end
  end
end

local function display(content, source_win, source_buf, width)
  if #content.lines == 0 then
    return
  end
  local buf, win = vim.lsp.util.open_floating_preview(content.lines, nil, {
    border = 'rounded',
    focus_id = 'hover_docs',
    max_width = width,
    max_height = math.max(1, math.floor(vim.o.lines * 0.5)),
    wrap = true,
  })
  vim.w[win].hover_docs_source_win = source_win
  vim.w[win].hover_docs = source_buf
  -- The native float owns focus/close behavior; md-render owns text and link
  -- extmarks, so concealed URL bytes never influence Neovim's line wrapping.
  vim.bo[buf].modifiable = true
  require('md-render.display_utils').apply_content_to_buffer(buf, namespace, content)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'hover_docs'
  vim.wo[win].conceallevel = 0
  api.nvim_win_set_height(
    win,
    math.min(math.max(1, math.floor(vim.o.lines * 0.5)), api.nvim_win_text_height(win, {}).all)
  )
  for _, key in ipairs({ '<CR>', 'gx' }) do
    vim.keymap.set('n', key, function()
      open_link(content, win, source_win)
    end, { buffer = buf, silent = true, desc = 'Open documentation link' })
  end
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = buf, silent = true, nowait = true, desc = 'Close documentation' })
  end
end

function M.hover()
  local source_win = api.nvim_get_current_win()
  local source_buf = api.nvim_get_current_buf()
  local origin = vim.w[source_win].hover_docs_source_win
  if origin and api.nvim_win_is_valid(origin) then
    api.nvim_set_current_win(origin)
    return
  end
  local existing = vim.b[source_buf].lsp_floating_preview
  if existing and api.nvim_win_is_valid(existing) and vim.w[existing].hover_docs == source_buf then
    api.nvim_set_current_win(existing)
    return
  end
  request_id = request_id + 1
  local id = request_id
  local cursor = api.nvim_win_get_cursor(source_win)
  local changedtick = api.nvim_buf_get_changedtick(source_buf)
  vim.lsp.buf_request_all(source_buf, 'textDocument/hover', function(client)
    return vim.lsp.util.make_position_params(source_win, client.offset_encoding)
  end, function(results)
    if
      id ~= request_id
      or not api.nvim_win_is_valid(source_win)
      or api.nvim_get_current_win() ~= source_win
      or api.nvim_win_get_buf(source_win) ~= source_buf
      or api.nvim_buf_get_changedtick(source_buf) ~= changedtick
      or not vim.deep_equal(api.nvim_win_get_cursor(source_win), cursor)
    then
      return
    end
    local width =
      math.max(1, math.min(100, vim.o.columns - 4, api.nvim_win_get_width(source_win) - 2))
    display(render(results, width), source_win, source_buf, width)
  end)
end

return M
