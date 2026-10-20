-- Run: nvim --headless -u NONE -i NONE -l scripts/check-telescope.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd 'packadd plenary.nvim'
vim.cmd 'packadd telescope.nvim'
vim.o.columns = 180
vim.o.lines = 45

local custom = require 'custom.telescope'
custom.setup()
require('telescope').setup {
  defaults = {
    path_display = custom.path_display,
    wrap_results = false,
  },
}

local function check()
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local config = require('telescope.config').values
  local actions = require 'telescope.actions'
  local paths = {
    'src/Short.java',
    'very/long/module/src/main/java/internal/ContinuumReliableMessageBodyWriter.java',
    'another/module/' .. string.rep('Long', 24) .. 'Suffix.java',
    'unicode/目录/' .. string.rep('界', 40) .. '尾.java',
  }
  local function open(results, maker)
    local completed = false
    local picker = pickers.new({}, {
      finder = finders.new_table { results = results, entry_maker = maker },
      sorter = config.generic_sorter {},
      on_complete = { function() completed = true end },
    })
    picker:find()
    assert(vim.wait(3000, function() return completed end), 'Picker did not complete')
    assert(picker._custom_path_width, 'Default alignment callback did not run')
    return picker
  end
  local function display(picker, entry) return require('telescope.pickers.entry_display').resolve(picker, entry) end
  local function check_rows(picker)
    local index = 0
    for entry in picker.manager:iter() do
      index = index + 1
      if index > picker.max_results then break end
      local row = picker:get_row(index)
      local line = vim.api.nvim_buf_get_lines(picker.results_bufnr, row, row + 1, false)[1]
      assert(line:sub(#picker.entry_prefix + 1) == display(picker, entry), 'Results buffer was not redrawn')
    end
  end
  local picker = open(paths, require('telescope.make_entry').gen_from_file { disable_devicons = true })
  local prompt = picker.prompt_bufnr
  local endings = {}
  for entry in picker.manager:iter() do
    local text, styles = display(picker, entry)
    assert(vim.fn.strdisplaywidth(text) == custom.path_width, text)
    assert(vim.str_utfindex(text, 'utf-32') > 0, 'Invalid UTF-8')
    assert(#styles > 0, 'Path highlights missing')
    endings[entry.value] = text
  end
  assert(endings[paths[1]]:match 'Short.java$')
  assert(endings[paths[2]]:match '^%.%.%..*ContinuumReliableMessageBodyWriter.java$')
  assert(endings[paths[3]]:match '^%.%.%..*Suffix.java$')
  assert(endings[paths[4]]:match '^%.%.%..*尾.java$')
  check_rows(picker)
  picker:reset_prompt 'module'
  assert(vim.wait(3000, function() return picker.manager:num_results() == 2 end), 'Directory search failed')
  -- Let the completion callback finish before changing display modes.
  vim.wait(50, function() return false end)
  picker:set_selection(picker:get_row(2))
  local selected = picker:get_selection()
  local original_prompt = picker:_get_prompt()
  for _, mode in ipairs { 'nowrap', 'wrap', 'aligned' } do
    custom.cycle_results_mode(prompt)
    assert(picker._custom_results_mode == mode)
    assert(vim.wo[picker.results_win].wrap == (mode == 'wrap'))
    assert(picker:get_selection() == selected, 'Selection changed')
    assert(picker:_get_prompt() == original_prompt, 'Prompt changed')
    check_rows(picker)
    local text = display(picker, selected)
    if mode ~= 'aligned' then assert(text == selected.value, 'Full path was not restored') end
  end
  vim.api.nvim_win_set_width(picker.results_win, 35)
  for entry in picker.manager:iter() do
    assert(vim.fn.strdisplaywidth((display(picker, entry))) <= 31, 'Path overflows narrow window')
  end
  actions.close(prompt)

  local matches = {}
  local locations = { { 1, 1234 }, { 22, 33 }, { 333, 2 }, { 4444, 111 } }
  for i, path in ipairs(paths) do
    matches[i] = path .. ':' .. locations[i][1] .. ':' .. locations[i][2] .. ':needle source text'
  end
  picker = open(matches, custom.location_entry_maker('grep', { disable_devicons = true }))
  local filename_end, separator_column
  for entry in picker.manager:iter() do
    local text = display(picker, entry)
    local position = assert(text:find ':%s*%d+:%s*%d+ │ needle source text', text)
    local width = vim.fn.strdisplaywidth(text:sub(1, position - 1))
    assert(not filename_end or filename_end == width, 'Grep filenames are not aligned')
    filename_end = width
    local separator = assert(text:find(' │ ', 1, true))
    local column = vim.fn.strdisplaywidth(text:sub(1, separator - 1))
    assert(not separator_column or separator_column == column, 'Grep separators are not aligned with mixed coordinate widths')
    separator_column = column
    assert(entry.filename:match '%.java$', 'Filename changed')
    local line, offset = text:match ':%s*(%d+):%s*(%d+) │ '
    assert(tonumber(line) == entry.lnum and tonumber(offset) == entry.col, 'Location changed')
  end
  check_rows(picker)
  for _, mode in ipairs { 'nowrap', 'wrap', 'aligned' } do
    custom.cycle_results_mode(picker.prompt_bufnr)
    check_rows(picker)
    for entry in picker.manager:iter() do
      local text = display(picker, entry)
      if mode == 'aligned' then
        local separator = assert(text:find(' │ ', 1, true))
        assert(vim.fn.strdisplaywidth(text:sub(1, separator - 1)) == separator_column, 'Mode cycle lost separator alignment')
      else
        assert(text:find(':' .. entry.lnum .. ':' .. entry.col .. ' │ ', 1, true), 'Full-path mode changed coordinates')
      end
    end
  end
  picker:reset_prompt 'Short.java'
  assert(
    vim.wait(3000, function()
      local widths = picker._custom_location_widths
      return picker.manager:num_results() == 1 and widths.line == 1 and widths.column == 4
    end),
    'Coordinate widths did not shrink with filtered results'
  )
  check_rows(picker)
  picker:reset_prompt ''
  assert(
    vim.wait(3000, function()
      local widths = picker._custom_location_widths
      return picker.manager:num_results() == #matches and widths.line == 4 and widths.column == 4
    end),
    'Coordinate widths did not expand with results'
  )
  check_rows(picker)
  actions.close(picker.prompt_bufnr)

  picker = open({ 'a.lua', 'src/b.lua' }, require('telescope.make_entry').gen_from_file { disable_devicons = true })
  assert(picker._custom_path_width == #'src/b.lua', 'Short paths use an unnecessarily wide column')
  actions.close(picker.prompt_bufnr)

  local builtin = require 'telescope.builtin'
  builtin.find_files { find_command = { 'printf', '%s\n', 'a.lua', 'src/b.lua' }, previewer = false, disable_devicons = true }
  picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
  assert(vim.wait(3000, function() return picker._custom_path_width == #'src/b.lua' end), 'find_files default did not align')
  check_rows(picker)
  actions.close(picker.prompt_bufnr)

  builtin.live_grep {
    default_text = 'local M',
    previewer = false,
    entry_maker = custom.location_entry_maker('grep', { disable_devicons = true }),
  }
  picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
  assert(vim.wait(3000, function() return picker._custom_path_width ~= nil end), 'live_grep default did not align')
  check_rows(picker)
  actions.close(picker.prompt_bufnr)
  print 'Telescope checks passed: alignment, truncation, UTF-8, grep locations, resize, mode cycle, find_files, and live_grep'
end

local ok, err = xpcall(check, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
