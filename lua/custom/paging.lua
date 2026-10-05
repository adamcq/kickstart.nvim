local M = {}
local origin = require 'custom.scroll_origin'
local pending
local generation = 0
local duration = 200
local keys = { ['<C-d>'] = 0.5, ['<C-u>'] = -0.5, ['<C-f>'] = 1, ['<C-b>'] = -1 }

local function stop()
  generation = generation + 1
  if pending then
    pending = nil
    origin.finish()
  end
end

local function page(fraction)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local direction = fraction > 0 and 1 or -1
  local height = vim.api.nvim_win_get_height(win)
  local lines = math.abs(fraction) == 0.5 and vim.wo.scroll or math.max(1, height - 2)
  lines = math.max(1, lines) * vim.v.count1
  -- Repeated presses extend the movement; reversing starts in the new direction.
  if pending and pending.win == win and pending.buf == buf and pending.direction == direction then lines = lines + pending.remaining end
  stop()
  origin.mark()
  pending = { win = win, buf = buf, direction = direction, remaining = lines }
  local current = generation
  local interval = math.max(1, math.floor(duration / lines))
  local motion = direction > 0 and 'gj' or 'gk'

  local function step()
    if current ~= generation or not pending then return end
    if vim.api.nvim_get_current_win() ~= win or vim.api.nvim_get_current_buf() ~= buf then
      stop()
      return
    end
    local before = vim.api.nvim_win_get_cursor(win)
    -- Cursor movement lets Neovim scroll only when the cursor reaches scrolloff.
    -- Screen-line motions also handle wrapped text and closed folds.
    local ok = pcall(vim.cmd.normal, { bang = true, args = { motion } })
    local after = vim.api.nvim_win_get_cursor(win)
    pending.remaining = pending.remaining - 1
    if not ok or pending.remaining == 0 or (before[1] == after[1] and before[2] == after[2]) then
      stop()
    else
      vim.defer_fn(step, interval)
    end
  end
  step()
end

function M.setup()
  stop()
  origin.setup()
  local paging_keys = {}
  for key, fraction in pairs(keys) do
    paging_keys[vim.api.nvim_replace_termcodes(key, true, false, true)] = true
    vim.keymap.set({ 'n', 'x' }, key, function() page(fraction) end, { desc = 'Page with cursor movement and highlight the previous line' })
  end
  -- New input, including mouse scrolling and j/k, interrupts the animation.
  vim.on_key(function(_, typed)
    if typed ~= '' and not paging_keys[typed] then stop() end
  end, vim.api.nvim_create_namespace 'keyboard-scroll-animation')
  vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
    group = vim.api.nvim_create_augroup('cursor-paging', { clear = true }),
    callback = stop,
  })
end

return M
