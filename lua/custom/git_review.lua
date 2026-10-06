local M = {}

function M.setup(gitsigns)
  local review_list_id
  local preview_pending = false

  -- Keep the built-in [q / ]q mappings, and preview only our Git list.
  local function schedule_preview()
    if preview_pending or not review_list_id then
      return
    end
    preview_pending = true
    vim.schedule(function()
      preview_pending = false
      local list = vim.fn.getqflist { id = 0, idx = 0, items = 0 }
      if list.id ~= review_list_id or vim.bo.buftype ~= '' then
        return
      end
      local entry = list.items[list.idx]
      local line = vim.api.nvim_win_get_cursor(0)[1]
      if entry and entry.bufnr == vim.api.nvim_get_current_buf()
        and line == math.max(1, math.min(entry.lnum, vim.api.nvim_buf_line_count(0))) then
        gitsigns.preview_hunk_inline()
      end
    end)
  end

  local group = vim.api.nvim_create_augroup('GitQuickfixInlinePreview', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'CursorMoved', 'QuickFixCmdPost' }, {
    group = group,
    callback = schedule_preview,
  })
  -- A newly opened file may still be waiting for Gitsigns to calculate its hunks.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'GitSignsUpdate',
    callback = schedule_preview,
  })

  function M.open_hunks()
    gitsigns.setqflist('all', { open = false }, function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      local list = vim.fn.getqflist { id = 0, size = 0 }
      review_list_id = list.id
      if list.size == 0 then
        vim.notify('No Git hunks to review')
        return
      end
      vim.cmd.cclose()
      vim.cmd.cfirst()
      schedule_preview()
    end)
  end

  function M.open_diff(staged)
    local status = vim.b.gitsigns_status_dict
    local cwd = status and status.root or vim.fn.getcwd()
    local command = { 'git', '--no-pager', 'diff' }
    if staged then
      command[#command + 1] = '--cached'
    end
    vim.cmd.tabnew()
    vim.fn.jobstart(command, { term = true, cwd = cwd })
  end
end

return M
