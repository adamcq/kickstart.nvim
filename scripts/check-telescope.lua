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
  local function open(results, maker, opts)
    local completed = false
    local picker = pickers.new(opts or {}, {
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

  local buffers = {}
  for i, path in ipairs(paths) do
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn['repeat']({ '' }, 175))
    buffers[i] = { bufnr = bufnr, flag = ' ', info = { name = path, hidden = 1, changed = 0, lnum = 175 } }
  end
  picker = open(buffers, require('telescope.make_entry').gen_from_buffer { bufnr_width = 2, disable_devicons = true })
  for _, width in ipairs { 100, 85, 70, 55, 40 } do
    vim.api.nvim_win_set_width(picker.results_win, width)
    custom.align_results(picker)
    for entry in picker.manager:iter() do
      local text = display(picker, entry)
      assert(text:match ':175$', 'Buffer line number disappeared')
      assert(vim.fn.strdisplaywidth(text) + #picker.entry_prefix <= width, 'Buffer filename or line number is clipped at the right edge')
      assert(text:find(entry.filename:match '([^/]+)$':sub(-12), 1, true), 'Buffer filename ending disappeared')
    end
    check_rows(picker)
  end
  actions.close(picker.prompt_bufnr)
  for _, buffer in ipairs(buffers) do vim.api.nvim_buf_delete(buffer.bufnr, { force = true }) end

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
  local full_width = vim.api.nvim_win_get_width(picker.results_win)
  -- There is room for the path and location, but not the old 24-cell reserve.
  vim.api.nvim_win_set_width(picker.results_win, separator_column + 8)
  for entry in picker.manager:iter() do
    local text = display(picker, entry)
    local separator = assert(text:find(' │ ', 1, true))
    assert(vim.fn.strdisplaywidth(text:sub(1, separator - 1)) == separator_column, 'Shrinking clipped filenames before the source text')
  end
  vim.api.nvim_win_set_width(picker.results_win, separator_column - 8)
  for entry in picker.manager:iter() do
    local text = display(picker, entry)
    local separator = assert(text:find(' │ ', 1, true))
    local column = vim.fn.strdisplaywidth(text:sub(1, separator - 1))
    assert(column < separator_column, 'Narrow results did not shorten paths after reaching the separator')
    assert(column + 3 <= vim.api.nvim_win_get_width(picker.results_win) - #picker.entry_prefix, 'Location separator exceeds results width')
  end
  vim.api.nvim_win_set_width(picker.results_win, full_width)
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

  picker = open(paths, require('telescope.make_entry').gen_from_file { disable_devicons = true }, {
    previewer = require('telescope.previewers').new_buffer_previewer {
      define_preview = function(self, entry) vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { 'preview: ' .. entry.filename }) end,
    },
  })
  prompt = picker.prompt_bufnr
  local original_getter = picker.get_window_options
  local result_width = vim.api.nvim_win_get_width(picker.results_win)
  local preview_width = vim.api.nvim_win_get_width(picker.preview_win)
  local function check_visible(pane)
    if vim.env.TELESCOPE_CHECK_SCREEN ~= '1' then return end
    local win = picker[pane .. '_win']
    local expected = picker:get_selection().filename:match '[^/]+$'
    if pane == 'preview' then
      expected = 'preview: ' .. picker:get_selection().filename
      assert(
        vim.wait(3000, function() return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1] == expected end),
        'Preview buffer did not load'
      )
    end
    vim.cmd 'redraw!'
    local position = vim.api.nvim_win_get_position(win)
    local screen = {}
    for row = position[1] + 1, position[1] + vim.api.nvim_win_get_height(win) do
      local cells = {}
      for column = position[2] + 1, position[2] + vim.api.nvim_win_get_width(win) do
        cells[#cells + 1] = vim.fn.screenstring(row, column)
      end
      screen[#screen + 1] = table.concat(cells)
    end
    assert(table.concat(screen, '\n'):find(expected, 1, true), pane .. ' content is covered on screen')
  end
  local function check_maximized(pane)
    assert(picker._custom_maximized_pane == pane, 'Wrong pane maximized')
    local active = picker[pane .. '_win']
    local inactive = picker[(pane == 'results' and 'preview' or 'results') .. '_win']
    assert(vim.api.nvim_win_get_width(active) > math.max(result_width, preview_width), 'Maximized pane did not grow')
    assert(vim.deep_equal(vim.api.nvim_win_get_position(active), vim.api.nvim_win_get_position(inactive)), 'Panes do not overlap')
    assert(vim.api.nvim_win_get_config(active).zindex > vim.api.nvim_win_get_config(inactive).zindex, 'Inactive pane covers maximized pane')
    local border = picker[pane .. '_border'].winid
    if border and vim.api.nvim_win_is_valid(border) then
      assert(vim.api.nvim_win_get_config(active).zindex > vim.api.nvim_win_get_config(border).zindex, 'Border covers maximized content')
    end
    check_rows(picker)
    check_visible(pane)
  end
  local function check_restored()
    assert(picker._custom_maximized_pane == nil)
    assert(picker.get_window_options == original_getter, 'Original layout was not restored')
    assert(vim.api.nvim_win_get_width(picker.results_win) == result_width, 'Results width was not restored')
    assert(vim.api.nvim_win_get_width(picker.preview_win) == preview_width, 'Preview width was not restored')
    assert(vim.api.nvim_win_get_config(picker.results_win).zindex == vim.api.nvim_win_get_config(picker.preview_win).zindex, 'Pane stacking was not restored')
    check_rows(picker)
    check_visible 'results'
    check_visible 'preview'
  end
  selected = picker:get_selection()
  custom.maximize_results(prompt)
  check_maximized 'results'
  custom.maximize_preview(prompt)
  check_maximized 'preview'
  assert(picker:get_selection() == selected, 'Maximizing changed selection')
  actions.move_selection_next(prompt)
  assert(picker:get_selection() ~= selected, 'Selection cannot move while preview is maximized')
  assert(
    vim.wait(3000, function()
      local preview_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(picker.preview_win), 0, -1, false)
      return preview_lines[1] == 'preview: ' .. picker:get_selection().filename
    end),
    'Maximized preview did not follow selection'
  )
  picker:reset_prompt 'Short.java'
  assert(vim.wait(3000, function() return picker.manager:num_results() == 1 end), 'Cannot filter while preview is maximized')
  vim.wait(50, function() return false end)
  check_maximized 'preview'
  vim.o.columns = 150
  picker:full_layout_update()
  assert(picker._custom_maximized_pane == 'preview', 'Resize lost maximized pane')
  assert(vim.api.nvim_win_get_width(picker.preview_win) == vim.api.nvim_win_get_width(picker.results_win), 'Resize broke pane overlap')
  vim.o.columns = 180
  custom.maximize_preview(prompt)
  check_restored()
  assert(picker:_get_prompt() == 'Short.java', 'Restoring changed search text')
  custom.maximize_results(prompt)
  check_maximized 'results'
  custom.maximize_results(prompt)
  check_restored()
  custom.maximize_preview(prompt)
  custom.restore_panes(prompt)
  check_restored()
  selected = picker:get_selection()
  custom.move_divider_left(prompt)
  assert(vim.api.nvim_win_get_width(picker.preview_win) > preview_width, 'Moving divider left did not widen preview')
  assert(vim.api.nvim_win_get_width(picker.results_win) < result_width, 'Moving divider left did not shrink results')
  custom.move_divider_right(prompt)
  assert(math.abs(vim.api.nvim_win_get_width(picker.preview_win) - preview_width) <= 1, 'Opposite divider moves did not restore width')
  for _ = 1, 30 do custom.move_divider_left(prompt) end
  assert(picker._custom_preview_ratio == 0.8, 'Preview width limit failed')
  assert(vim.api.nvim_win_get_width(picker.results_win) > 0, 'Results disappeared')
  for _ = 1, 30 do custom.move_divider_right(prompt) end
  assert(picker._custom_preview_ratio == 0.2, 'Results width limit failed')
  local ratio = vim.api.nvim_win_get_width(picker.preview_win) / vim.api.nvim_win_get_width(picker.results_win)
  vim.o.columns = 150
  picker:full_layout_update()
  assert(math.abs(vim.api.nvim_win_get_width(picker.preview_win) / vim.api.nvim_win_get_width(picker.results_win) - ratio) < 0.03, 'Resize lost divider ratio')
  custom.maximize_preview(prompt)
  custom.restore_panes(prompt)
  assert(picker._custom_preview_ratio == 0.2, 'Maximizing lost divider ratio')
  assert(picker:get_selection() == selected, 'Moving divider changed selection')
  assert(picker:_get_prompt() == 'Short.java', 'Moving divider changed search text')
  check_rows(picker)
  vim.o.columns = 180
  actions.close(prompt)

  picker = open({ 'a.lua', 'src/b.lua' }, require('telescope.make_entry').gen_from_file { disable_devicons = true })
  custom.maximize_preview(picker.prompt_bufnr)
  assert(picker._custom_maximized_pane == nil, 'Picker without a preview entered preview mode')
  custom.move_divider_left(picker.prompt_bufnr)
  assert(picker._custom_preview_ratio == nil, 'Picker without a preview changed divider ratio')
  assert(picker._custom_path_width == #'src/b.lua', 'Short paths use an unnecessarily wide column')
  custom.maximize_results(picker.prompt_bufnr)
  actions.close(picker.prompt_bufnr)

  local builtin = require 'telescope.builtin'
  builtin.resume()
  picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
  assert(vim.wait(3000, function() return picker.manager and picker:get_selection() ~= nil end), 'Cannot resume a maximized picker')
  assert(not picker._custom_maximized_pane, 'Resumed picker did not restore its normal layout')
  actions.close(picker.prompt_bufnr)
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
  print 'Telescope checks passed: alignment, truncation, UTF-8, grep locations, pane maximization, divider movement, resize, resume, mode cycle, find_files, and live_grep'
end

local ok, err = xpcall(check, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
