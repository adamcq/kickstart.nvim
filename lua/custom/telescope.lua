local M = {}

local function path_highlights(path)
  local filename = path:match '[^/\\]+$' or ''
  local start = #path - #filename
  local styles = {}
  if start > 0 then styles[#styles + 1] = { { 0, start }, 'Comment' } end
  if #filename > 0 then styles[#styles + 1] = { { start, #path }, 'CustomTelescopeFilename' } end
  return styles
end

local function toggle_wrap(prompt_bufnr, pane)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  local win = picker[pane .. '_win']
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local wrap = not vim.wo[win].wrap
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

function M.toggle_results_wrap(prompt_bufnr) toggle_wrap(prompt_bufnr, 'results') end
function M.toggle_preview_wrap(prompt_bufnr) toggle_wrap(prompt_bufnr, 'preview') end

function M.setup()
  -- Neovim's default extmark priority can put Telescope's selection above its
  -- entry colors. Keep the selection background below filenames and snippets.
  local highlighter = getmetatable(require('telescope.pickers.highlights').new({}))
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
  local display = require('telescope.utils').transform_path(vim.tbl_extend('force', opts, { path_display = {} }), path)
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
      local path = utils.transform_path(opts, e.filename)
      local coordinates = e.lnum and (':' .. e.lnum .. (e.col and (':' .. e.col) or '')) or ''
      local text = e.text or ''
      if kind ~= 'grep' then text = text:gsub('.* | ', '') end
      local display = path .. coordinates .. ' │ ' .. text
      local styles = path_highlights(path)
      styles[#styles + 1] = { { #path, #path + #coordinates }, 'TelescopeResultsLineNr' }
      styles[#styles + 1] = { { #path + #coordinates, #path + #coordinates + #' │ ' }, 'Comment' }
      styles[#styles + 1] = { { #path + #coordinates + #' │ ', #display }, 'CustomTelescopeSnippet' }
      if kind == 'grep' then
        local with_icon, highlight, icon = utils.transform_devicons(e.filename, display, opts.disable_devicons)
        if highlight then
          styles = utils.merge_styles({ { { 0, #icon }, highlight } }, styles, #icon + 1)
        end
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
      local path = require('telescope.utils').transform_path(opts, e.filename)
      local path_style = path_highlights(path)
      return displayer { { path, function() return path_style end }, e.symbol_name, type_display }
    end
    return entry
  end
end

return M
