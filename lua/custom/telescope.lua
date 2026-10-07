local M = {}

local function toggle_wrap(prompt_bufnr, pane)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  local win = picker[pane .. '_win']
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local wrap = not vim.wo[win].wrap
  vim.wo[win].wrap = wrap
  if pane == 'results' then
    picker.wrap_results = wrap
  else
    picker._custom_preview_wrap = wrap
  end
end

function M.toggle_results_wrap(prompt_bufnr) toggle_wrap(prompt_bufnr, 'results') end
function M.toggle_preview_wrap(prompt_bufnr) toggle_wrap(prompt_bufnr, 'preview') end

function M.setup()
  vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('custom-telescope-wrap', { clear = true }),
    pattern = 'TelescopePreviewerLoaded',
    callback = function(event)
      -- Buffer previewers reset wrap when loading another entry.
      local state = require 'telescope.state'
      for _, prompt_bufnr in ipairs(state.get_existing_prompt_bufnrs()) do
        local picker = state.get_status(prompt_bufnr).picker
        local win = picker and picker.preview_win
        if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == event.buf then
          vim.wo[win].number = true
          vim.wo[win].relativenumber = false
          if picker._custom_preview_wrap ~= nil then vim.wo[win].wrap = picker._custom_preview_wrap end
        end
      end
    end,
  })
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
      local path, path_style = require('telescope.utils').transform_path(opts, e.filename)
      return displayer { { path, function() return path_style end }, e.symbol_name, type_display }
    end
    return entry
  end
end

return M
