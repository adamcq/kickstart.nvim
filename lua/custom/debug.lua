local M = {}

function M.setup()
  vim.pack.add {
    'https://github.com/mfussenegger/nvim-dap',
    'https://github.com/nvim-neotest/nvim-nio',
    'https://github.com/rcarriga/nvim-dap-ui',
  }

  local dap = require 'dap'
  local dapui = require 'dapui'
  dapui.setup {
    icons = { expanded = 'v', collapsed = '>', current_frame = '>' },
    controls = {
      icons = {
        pause = '||',
        play = '>',
        step_into = 'v',
        step_over = '->',
        step_out = '^',
        step_back = '<-',
        run_last = '>>',
        terminate = '[]',
        disconnect = 'X',
      },
    },
  }

  dap.configurations.java = {
    {
      type = 'java',
      request = 'attach',
      name = 'Attach to JVM (127.0.0.1:5005)',
      hostName = '127.0.0.1',
      port = 5005,
      projectName = function() return require('custom.java').debug_project_name() end,
      sourcePaths = function() return require('custom.java').debug_source_paths() end,
    },
  }

  require('which-key').add { { '<leader>d', group = '[D]ebug' } }
  local function map(key, callback, description) vim.keymap.set('n', '<leader>d' .. key, callback, { desc = 'Debug: ' .. description }) end
  map('b', dap.toggle_breakpoint, 'Toggle breakpoint')
  map('B', function()
    vim.ui.input({ prompt = 'Breakpoint condition: ' }, function(condition)
      if condition and condition:match '%S' then dap.set_breakpoint(condition) end
    end)
  end, 'Set conditional breakpoint')
  map('c', dap.continue, 'Start or continue')
  map('n', dap.step_over, 'Step over')
  map('i', dap.step_into, 'Step into')
  map('o', dap.step_out, 'Step out')
  map('t', dap.terminate, 'Stop debugging')
  map('r', dap.repl.open, 'Open console')
  map('u', dapui.toggle, 'Toggle panels')

  dap.listeners.after.event_initialized['custom-debug-ui'] = function() dapui.open() end
  -- Keep the final output visible until the user closes the panels with <leader>du.
end

return M
