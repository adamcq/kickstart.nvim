local M = {}

function M.setup()
  local sessions = require 'mini.sessions'
  sessions.setup {
    autoread = false,
    -- Restore the saved layout without overwriting it with the current one.
    autowrite = false,
    -- Keep all sessions outside project directories, accessible from anywhere.
    file = '',
  }

  local function directory_session()
    local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/+$', '')
    local name = vim.fn.fnamemodify(cwd, ':t')
    if name == '' then name = 'root' end
    return name .. '-' .. vim.fn.sha256(cwd):sub(1, 12) .. '.vim'
  end

  local function save(name)
    -- Session files store the layout, not unsaved buffer contents.
    -- Stop if any buffer cannot be written (including unnamed buffers).
    vim.cmd 'wall'
    sessions.write(name)
  end

  vim.keymap.set('n', '<leader>Ss', function() save(directory_session()) end, { desc = 'Session: Save current directory' })
  vim.keymap.set('n', '<leader>Sr', function() sessions.read(directory_session()) end, { desc = 'Session: Restore current directory' })
  vim.keymap.set('n', '<leader>Sl', function() sessions.select 'read' end, { desc = 'Session: List saved sessions' })
  vim.keymap.set('n', '<leader>Sn', function()
    vim.ui.input({ prompt = 'Save session as: ' }, function(name)
      if name == nil or vim.trim(name) == '' then return end
      name = vim.trim(name)
      if name:find '[/\\]' or name == '.' or name == '..' then
        vim.notify('Use a session name without directory separators.', vim.log.levels.ERROR)
        return
      end
      if not name:match '%.vim$' then name = name .. '.vim' end
      save(name)
    end)
  end, { desc = 'Session: Save with a name' })
  vim.keymap.set('n', '<leader>Sq', function()
    save(directory_session())
    vim.cmd 'qa'
  end, { desc = 'Session: Save current directory and quit' })
end

return M
