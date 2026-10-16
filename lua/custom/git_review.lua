local M = {}

function M.setup(gitsigns)
  local review_list_id
  local pr_list_id
  local pr_hunks = {}
  local preview_buf
  local preview_ns = vim.api.nvim_create_namespace 'GitPRInlinePreview'
  local preview_pending = false

  -- Keep the built-in [q / ]q mappings, and preview only our Git list.
  local function schedule_preview()
    if preview_pending or not (review_list_id or pr_list_id) then
      return
    end
    preview_pending = true
    vim.schedule(function()
      preview_pending = false
      local list = vim.fn.getqflist { id = 0, idx = 0, items = 0 }
      if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
        vim.api.nvim_buf_clear_namespace(preview_buf, preview_ns, 0, -1)
      end
      preview_buf = nil
      if list.id == pr_list_id then
        local entry = list.items[list.idx]
        local hunk = pr_hunks[list.idx]
        if not entry or not hunk or entry.bufnr ~= vim.api.nvim_get_current_buf()
          or vim.api.nvim_win_get_cursor(0)[1] ~= entry.lnum then
          return
        end
        preview_buf = entry.bufnr
        local row = entry.lnum - 1
        if #hunk.removed > 0 then
          local lines = {}
          for _, line in ipairs(hunk.removed) do
            lines[#lines + 1] = { { '- ' .. line, 'DiffDelete' } }
          end
          vim.api.nvim_buf_set_extmark(preview_buf, preview_ns, row, 0, {
            virt_lines = lines, virt_lines_above = hunk.count > 0 or hunk.start == 0,
          })
        end
        for added_row = hunk.start - 1, hunk.start + hunk.count - 2 do
          vim.api.nvim_buf_set_extmark(preview_buf, preview_ns, added_row, 0, {
            line_hl_group = hunk.deleted and 'DiffDelete' or 'DiffAdd',
          })
        end
        return
      end
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

  local function with_pr_base(callback)
    local status = vim.b.gitsigns_status_dict
    local cwd = status and status.root or vim.b.pr_review_root or vim.fn.getcwd()
    local function git_output(args)
      local command = { 'git' }
      vim.list_extend(command, args)
      local result = vim.system(command, { cwd = cwd, text = true }):wait()
      return result.code == 0 and vim.trim(result.stdout) or nil
    end
    local root = git_output { 'rev-parse', '--show-toplevel' }
    if not root then
      vim.notify('Open a file or directory inside a Git repository', vim.log.levels.WARN)
      return
    end
    cwd = root
    local function resolve_base(base)
      if not base then
        base = git_output { 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' }
        for _, candidate in ipairs { 'origin/main', 'origin/master' } do
          if not base and git_output { 'rev-parse', '--verify', candidate .. '^{commit}' } then
            base = candidate
          end
        end
      end
      if not base or not git_output { 'rev-parse', '--verify', base .. '^{commit}' } then
        vim.notify('PR base is unavailable locally. Fetch the base branch from origin first.', vim.log.levels.WARN)
        return
      end
      callback(cwd, base, git_output)
    end
    if vim.fn.executable 'gh' == 0 then
      resolve_base()
      return
    end
    vim.system({ 'gh', 'pr', 'view', '--json', 'baseRefName', '--jq', '.baseRefName' },
      { cwd = cwd, text = true, timeout = 10000 }, function(result)
        vim.schedule(function()
          local name = result.code == 0 and vim.trim(result.stdout) or ''
          resolve_base(name ~= '' and ('origin/' .. name) or nil)
        end)
      end)
  end

  function M.open_pr_diff()
    with_pr_base(function(cwd, base)
      vim.cmd.tabnew()
      vim.fn.jobstart({ 'git', '--no-pager', 'diff', base .. '...HEAD', '--' }, { term = true, cwd = cwd })
    end)
  end

  function M.open_pr_hunks()
    with_pr_base(function(root, base, git_output)
      local head = git_output { 'rev-parse', 'HEAD' }
      local ancestor = head and git_output { 'merge-base', base, head }
      local result = ancestor and vim.system({ 'git', 'diff', '--no-renames', '--name-only', '-z', ancestor, head, '--' },
        { cwd = root, text = true }):wait()
      local paths = result and result.code == 0 and result.stdout
      if not paths then
        vim.notify('Could not read PR changes', vim.log.levels.ERROR)
        return
      end
      local items, hunks = {}, {}
      local function read_file(revision, path)
        local result = vim.system({ 'git', 'show', revision .. ':' .. path }, { cwd = root, text = true }):wait()
        return result.code == 0 and result.stdout or ''
      end
      for path in paths:gmatch('[^%z]+') do
        local before, after = read_file(ancestor, path), read_file(head, path)
        -- Binary files have no line-based hunks to navigate.
        if not before:find('\0', 1, true) and not after:find('\0', 1, true) then
          local changes = vim.diff(before, after, { result_type = 'indices', ctxlen = 0 })
          if #changes > 0 then
            local deleted = after == '' and not git_output { 'cat-file', '-e', head .. ':' .. path }
            local content = deleted and before or after
            local lines = vim.split(content, '\n', { plain = true })
            if lines[#lines] == '' then table.remove(lines) end
            local name = ('pr-review://%s/%s..%s/%s'):format(root, ancestor, head, path)
            local buf = vim.fn.bufnr(name)
            if buf == -1 then
              buf = vim.api.nvim_create_buf(false, true)
              vim.api.nvim_buf_set_name(buf, name)
            end
            vim.bo[buf].modifiable = true
            vim.bo[buf].buftype = 'nofile'
            vim.bo[buf].bufhidden = 'hide'
            vim.bo[buf].swapfile = false
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].filetype = vim.filetype.match { filename = root .. '/' .. path, buf = buf } or ''
            vim.bo[buf].modifiable = false
            vim.bo[buf].readonly = true
            vim.b[buf].pr_review_root = root
            local old_lines = vim.split(before, '\n', { plain = true })
            for _, change in ipairs(changes) do
              local old_start, old_count, start, count = unpack(change)
              local removed = {}
              for i = old_start, old_start + old_count - 1 do
                removed[#removed + 1] = old_lines[i]
              end
              local lnum = deleted and old_start or start
              items[#items + 1] = {
                bufnr = buf, lnum = math.max(1, math.min(lnum, vim.api.nvim_buf_line_count(buf))),
                text = ('%s: -%d,%d +%d,%d%s'):format(path, old_start, old_count, start, count, deleted and ' (deleted)' or ''),
              }
              hunks[#hunks + 1] = { removed = deleted and {} or removed, start = start, count = count, deleted = deleted }
              if deleted then
                -- The old snapshot itself is the removed hunk.
                hunks[#hunks].start, hunks[#hunks].count = old_start, old_count
              end
            end
          end
        end
      end
      if #items == 0 then
        vim.notify('No text hunks in the current PR to review')
        return
      end
      vim.fn.setqflist({}, ' ', { title = 'PR hunks (' .. base .. '...HEAD)', items = items })
      pr_list_id = vim.fn.getqflist { id = 0 }.id
      pr_hunks = hunks
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
