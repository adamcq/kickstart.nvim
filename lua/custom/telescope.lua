local M = {}

-- Limit the path column so grep results still have room for source text.
M.path_width = 60

local function current_picker() return (require('telescope.state').get_status(vim.api.nvim_get_current_buf()) or {}).picker end

local function plain_path(opts, path) return require('telescope.utils').transform_path(vim.tbl_extend('force', opts, { path_display = {} }), path) end

local function aligned_path(opts, path, reserve)
  local display = plain_path(opts, path)
  local picker = current_picker()
  if not picker then return display end
  -- on_complete is a picker option, not a Telescope defaults option. Attach
  -- once when a picker first displays a path, including extension pickers.
  if not picker._custom_alignment_callback then
    picker:register_completion_callback(M.align_results)
    picker._custom_alignment_callback = true
  end
  if (picker._custom_results_mode or 'aligned') ~= 'aligned' then return display end
  local win = picker.results_win
  if not win or not vim.api.nvim_win_is_valid(win) then return display end
  local prefix = math.max(vim.fn.strdisplaywidth(picker.selection_caret), vim.fn.strdisplaywidth(picker.entry_prefix))
  -- Allow two cells for a devicon and its separator, even without devicons.
  local available = vim.api.nvim_win_get_width(win) - prefix - 2 - (reserve or 0)
  local width = math.max(4, math.min(picker._custom_path_width or M.path_width, available))
  if vim.fn.strdisplaywidth(display) > width then
    -- Remove whole characters from the left, preserving UTF-8 and the suffix.
    local count = vim.fn.strchars(display)
    local low, high = 0, count
    while low < high do
      local middle = math.floor((low + high) / 2)
      if vim.fn.strdisplaywidth(vim.fn.strcharpart(display, middle)) <= width - 3 then
        high = middle
      else
        low = middle + 1
      end
    end
    display = '...' .. vim.fn.strcharpart(display, low)
  end
  return string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(display))) .. display
end

local function redraw_results(picker)
  if not picker.manager or not vim.api.nvim_buf_is_valid(picker.results_bufnr) then return end
  local selected = picker:get_selection_row()
  local index = 0
  for entry in picker.manager:iter() do
    index = index + 1
    if index > picker.max_results then break end
    picker:entry_adder(index, entry, nil, false)
  end
  picker:set_selection(selected)
end

function M.align_results(picker)
  if not picker.manager then return end
  local width, line_width, column_width = 0, 0, 0
  for entry in picker.manager:iter() do
    local path = entry.filename or entry.path
    if width < M.path_width and type(path) == 'string' then
      local display = plain_path({ cwd = picker.cwd }, path)
      width = math.max(width, vim.fn.strdisplaywidth(display))
    end
    if entry.lnum then line_width = math.max(line_width, #tostring(entry.lnum)) end
    if entry.col then column_width = math.max(column_width, #tostring(entry.col)) end
  end
  picker._custom_path_width = math.min(M.path_width, math.max(4, width))
  picker._custom_location_widths = { line = line_width, column = column_width }
  if (picker._custom_results_mode or 'aligned') == 'aligned' then redraw_results(picker) end
end

local function location_coordinates(entry)
  local picker = current_picker()
  local widths = picker and picker._custom_location_widths
  if not widths or (picker._custom_results_mode or 'aligned') ~= 'aligned' then
    return entry.lnum and (':' .. entry.lnum .. (entry.col and (':' .. entry.col) or '')) or ''
  end
  if widths.line == 0 then return '' end
  local line = entry.lnum and (':' .. string.format('%' .. widths.line .. 's', entry.lnum)) or string.rep(' ', widths.line + 1)
  local column = widths.column > 0 and (':' .. string.format('%' .. widths.column .. 's', entry.col or '')) or ''
  return line .. column
end

local function path_highlights(path)
  local filename = path:match '[^/\\]+$' or ''
  local start = #path - #filename
  local styles = {}
  if start > 0 then styles[#styles + 1] = { { 0, start }, 'Comment' } end
  if #filename > 0 then styles[#styles + 1] = { { start, #path }, 'CustomTelescopeFilename' } end
  return styles
end

local function toggle_wrap(prompt_bufnr, pane, wrap)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  local win = picker[pane .. '_win']
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  if wrap == nil then wrap = not vim.wo[win].wrap end
  vim.wo[win].wrap = wrap
  if pane == 'results' then
    -- The selected caret is not whitespace, so automatic breakindent differs
    -- from unselected rows. Indent both by the width of the results prefix.
    local prefix_width = math.max(vim.fn.strdisplaywidth(picker.selection_caret), vim.fn.strdisplaywidth(picker.entry_prefix))
    vim.wo[win].breakindent = true
    vim.wo[win].breakindentopt = 'min:0,column:' .. prefix_width
    vim.wo[win].showbreak = ''
    picker.wrap_results = wrap
    -- Results are an inactive window while typing in the prompt. Reapply its
    -- cursor so Neovim recalculates the viewport for the new screen-line heights.
    vim.api.nvim_win_set_cursor(win, vim.api.nvim_win_get_cursor(win))
  else
    picker._custom_preview_wrap = wrap
  end
end

function M.cycle_results_mode(prompt_bufnr)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  local mode = picker._custom_results_mode or 'aligned'
  local next_mode = ({ aligned = 'nowrap', nowrap = 'wrap', wrap = 'aligned' })[mode]
  picker._custom_results_mode = next_mode
  local win = picker.results_win
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  -- Reuse the existing continuation indentation for wrapped results.
  toggle_wrap(prompt_bufnr, 'results', next_mode == 'wrap')
  vim.api.nvim_win_call(win, function() vim.fn.winrestview { leftcol = 0 } end)
  redraw_results(picker)
end
function M.toggle_preview_wrap(prompt_bufnr) toggle_wrap(prompt_bufnr, 'preview') end

local function maximized_window_options(picker, columns, lines)
  local original = picker._custom_pane_window_options
  -- Use the picker's own layout without its preview to get the full main area.
  local previewer = picker.previewer
  picker.previewer = nil
  local ok, options = pcall(original, picker, columns, lines)
  picker.previewer = previewer
  if not ok then error(options) end
  if previewer then
    options.preview = require('telescope.pickers.window').get_initial_window_options(picker).preview
    for _, key in ipairs { 'line', 'col', 'width', 'height' } do
      options.preview[key] = options.results[key]
    end
    -- Keep both windows alive for selection, scrolling, and preview updates.
    -- The active pane covers the other pane, including its border.
  end
  return options
end

local function pane_stacking(picker, layout)
  for _, pane in ipairs { 'results', 'preview' } do
    local window = layout[pane]
    if window then
      for _, win in ipairs { window.winid, window.border and window.border.winid } do
        if vim.api.nvim_win_is_valid(win) then
          local original = picker._custom_pane_zindexes[win] or 50
          vim.api.nvim_win_set_config(win, { zindex = pane == picker._custom_maximized_pane and 60 or original })
        end
      end
    end
  end
end

function M.restore_panes(prompt_bufnr)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  if not picker._custom_maximized_pane then return end
  local layout = require('telescope.state').get_status(prompt_bufnr).layout
  picker.get_window_options = picker._custom_pane_window_options
  layout.update = picker._custom_pane_layout_update
  picker._custom_pane_window_options = nil
  picker._custom_pane_layout_update = nil
  picker._custom_maximized_pane = nil
  picker:full_layout_update()
  pane_stacking(picker, layout)
  picker._custom_pane_zindexes = nil
  redraw_results(picker)
end

local function maximize_pane(prompt_bufnr, pane)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  if picker._custom_maximized_pane == pane then return M.restore_panes(prompt_bufnr) end
  if pane == 'preview' and not picker.previewer then return end
  if not picker._custom_maximized_pane then
    local layout = require('telescope.state').get_status(prompt_bufnr).layout
    picker._custom_pane_window_options = picker.get_window_options
    picker._custom_pane_layout_update = layout.update
    picker._custom_pane_zindexes = {}
    for _, name in ipairs { 'results', 'preview' } do
      local window = layout[name]
      if window then
        for _, win in ipairs { window.winid, window.border and window.border.winid } do
          if vim.api.nvim_win_is_valid(win) then picker._custom_pane_zindexes[win] = vim.api.nvim_win_get_config(win).zindex end
        end
      end
    end
    picker.get_window_options = maximized_window_options
    layout.update = function(self)
      picker._custom_pane_layout_update(self)
      -- Plenary's popup.move does not apply zindex options during layout updates.
      pane_stacking(picker, self)
    end
    if not picker._custom_pane_close_hook then
      picker._custom_pane_close_hook = true
      vim.api.nvim_create_autocmd('BufLeave', {
        buffer = prompt_bufnr,
        once = true,
        callback = function()
          -- Resume constructs a new picker from the cached options. Do not
          -- leave it a window-options wrapper that depends on this picker.
          if picker._custom_maximized_pane then
            picker.get_window_options = picker._custom_pane_window_options
            layout.update = picker._custom_pane_layout_update
            picker._custom_maximized_pane = nil
            picker._custom_pane_window_options = nil
            picker._custom_pane_layout_update = nil
            picker._custom_pane_zindexes = nil
          end
          picker._custom_pane_close_hook = nil
        end,
      })
    end
  end
  picker._custom_maximized_pane = pane
  picker:full_layout_update()
  redraw_results(picker)
end

function M.maximize_results(prompt_bufnr) maximize_pane(prompt_bufnr, 'results') end
function M.maximize_preview(prompt_bufnr) maximize_pane(prompt_bufnr, 'preview') end

function M.setup()
  -- Neovim's default extmark priority can put Telescope's selection above its
  -- entry colors. Keep the selection background below filenames and snippets.
  local highlighter = getmetatable(require('telescope.pickers.highlights').new {})
  if not highlighter._custom_selection_priority then
    local hi_selection = highlighter.hi_selection
    local ns = vim.api.nvim_create_namespace 'telescope_selection'
    highlighter.hi_selection = function(self, row, caret)
      hi_selection(self, row, caret)
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(self.picker.results_bufnr, ns, 0, -1, { details = true })) do
        local details = mark[4]
        if details.hl_group == 'TelescopeSelection' then
          vim.api.nvim_buf_set_extmark(self.picker.results_bufnr, ns, mark[2], mark[3], {
            id = mark[1],
            end_row = details.end_row,
            end_col = details.end_col,
            hl_group = 'TelescopeSelection',
            hl_eol = details.hl_eol,
            hl_mode = 'combine',
            priority = 100,
          })
        end
      end
    end
    highlighter._custom_selection_priority = true
  end
  local function highlights()
    local cyan = vim.o.background == 'light' and '#007C91' or '#56D4DD'
    vim.api.nvim_set_hl(0, 'CustomTelescopeFilename', { fg = cyan, ctermfg = 51, bold = true })
    local grey = vim.o.background == 'light' and '#66707B' or '#8B949E'
    vim.api.nvim_set_hl(0, 'CustomTelescopeSnippet', { fg = grey, ctermfg = 245 })
  end
  highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('custom-telescope-highlights', { clear = true }),
    callback = highlights,
  })
  vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('custom-telescope-wrap', { clear = true }),
    pattern = 'TelescopePreviewerLoaded',
    callback = function(event)
      -- Buffer previewers reset wrap when loading another entry.
      -- Let scheduled preview buffer switches finish before configuring the window.
      vim.schedule(function()
        local state = require 'telescope.state'
        for _, prompt_bufnr in ipairs(state.get_existing_prompt_bufnrs()) do
          local status = state.get_status(prompt_bufnr)
          local picker = status.picker
          local win = status.layout and status.layout.preview and status.layout.preview.winid
          if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == event.buf then
            vim.wo[win].number = true
            vim.wo[win].relativenumber = false
            vim.wo[win].numberwidth = 4
            vim.wo[win].statuscolumn = '%l '
            if picker._custom_preview_wrap ~= nil then vim.wo[win].wrap = picker._custom_preview_wrap end
          end
        end
      end)
    end,
  })
end

function M.path_display(opts, path)
  local display = aligned_path(opts, path)
  return display, path_highlights(display)
end

-- Keep location metadata visually separate from the source snippet, without
-- changing the entry's filename, coordinates, or searchable text.
function M.location_entry_maker(kind, opts)
  opts = opts or {}
  local utils = require 'telescope.utils'
  local generator = kind == 'grep' and 'gen_from_vimgrep' or 'gen_from_quickfix'
  local make_entry = require('telescope.make_entry')[generator](opts)
  return function(value)
    local entry = make_entry(value)
    if not entry then return end
    entry.display = function(e)
      local path = aligned_path(opts, e.filename, 24)
      local coordinates = location_coordinates(e)
      local text = e.text or ''
      if kind ~= 'grep' then text = text:gsub('.* | ', '') end
      local display = path .. coordinates .. ' │ ' .. text
      local styles = path_highlights(path)
      styles[#styles + 1] = { { #path, #path + #coordinates }, 'TelescopeResultsLineNr' }
      styles[#styles + 1] = { { #path + #coordinates, #path + #coordinates + #' │ ' }, 'Comment' }
      styles[#styles + 1] = { { #path + #coordinates + #' │ ', #display }, 'CustomTelescopeSnippet' }
      if kind == 'grep' then
        local with_icon, highlight, icon = utils.transform_devicons(e.filename, display, opts.disable_devicons)
        if highlight then styles = utils.merge_styles({ { { 0, #icon }, highlight } }, styles, #icon + 1) end
        display = with_icon
      end
      return display, styles
    end
    return entry
  end
end

function M.symbol_entry_maker(opts)
  opts = opts or {}
  local make_entry = require('telescope.make_entry').gen_from_lsp_symbols(opts)
  local hidden = require('telescope.utils').is_path_hidden(opts)
  local displayer = require('telescope.pickers.entry_display').create {
    separator = ' ',
    -- Keep the full path and symbol; the results window handles wrapping.
    items = hidden and { {}, {} } or { {}, {}, {} },
  }
  return function(symbol)
    local entry = make_entry(symbol)
    entry.bufnr = vim.fn.bufadd(entry.filename)
    entry.display = function(e)
      local kind = e.symbol_type
      local highlight = kind == 'Property' and 'TelescopeResultsOperator' or ('TelescopeResults' .. kind)
      if vim.fn.hlexists(highlight) == 0 then highlight = 'TelescopeResultsNormal' end
      local type_display = { kind:lower(), highlight }
      if hidden then return displayer { e.symbol_name, type_display } end
      local path = aligned_path(opts, e.filename, 24)
      local path_style = path_highlights(path)
      return displayer { { path, function() return path_style end }, e.symbol_name, type_display }
    end
    return entry
  end
end

return M
