local M = {}
local namespace = vim.api.nvim_create_namespace 'scroll-origin'
local duration = 1200
local origin
local generation = 0

local function clear()
  if origin and vim.api.nvim_buf_is_valid(origin.buf) then
    vim.api.nvim_buf_del_extmark(origin.buf, namespace, origin.id)
  end
  origin = nil
end

function M.setup()
  local function highlight()
    vim.api.nvim_set_hl(0, 'ScrollOrigin', { link = 'IncSearch', default = true })
  end
  highlight()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('scroll-origin-highlight', { clear = true }),
    callback = highlight,
  })
end

-- Restart the expiry after the animation ends. The generation prevents an older
-- timer from clearing a newer marker when paging repeatedly or reversing direction.
function M.finish()
  generation = generation + 1
  local current = generation
  vim.defer_fn(function()
    if generation == current then clear() end
  end, duration)
end

function M.mark()
  clear()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  origin = {
    buf = buf,
    id = vim.api.nvim_buf_set_extmark(buf, namespace, row, 0, {
      line_hl_group = 'ScrollOrigin',
      priority = 200,
    }),
  }
  -- Also expire at file boundaries, where neoscroll may not start an animation.
  M.finish()
end

return M
