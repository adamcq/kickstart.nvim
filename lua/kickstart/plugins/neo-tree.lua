-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

vim.pack.add {
  { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '\\', '<Cmd>Neotree reveal<CR>', { desc = 'NeoTree reveal', silent = true })

local function expand_levels(state)
  local levels = vim.v.count
  if levels == 0 then
    require('neo-tree.sources.filesystem.commands').toggle_node(state)
    return
  end

  local selected = state.tree:get_node()
  if not selected or selected.type ~= 'directory' then return end
  local selected_id = selected:get_id()
  local renderer = require 'neo-tree.ui.renderer'
  local fs_scan = require 'neo-tree.sources.filesystem.lib.fs_scan'
  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}

  require('plenary.async').run(function()
    local function expand(id, depth)
      if depth == 0 then return end
      local node = state.tree:get_node(id)
      if not node or node.type ~= 'directory' then return end
      state.explicitly_opened_nodes[id] = true
      if not node.loaded then
        -- Load only this level; recursive scanning would read the whole subtree.
        fs_scan.get_dir_items_async(state, id, false)
        node = state.tree:get_node(id)
        if not node then return end
      end
      node:expand()
      for _, child in ipairs(state.tree:get_nodes(id)) do
        expand(child:get_id(), depth - 1)
      end
    end
    expand(selected_id, levels)
  end, function()
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
    renderer.redraw(state)
    renderer.focus_node(state, selected_id)
  end)
end

require('neo-tree').setup {
  default_component_configs = {
    indent = {
      indent_size = 1,
      padding = 0,
    },
  },
  filesystem = {
    hijack_netrw_behavior = 'disabled', -- Open the side pane only when requested with \.
    window = {
      mappings = {
        ['Z'] = 'expand_all_subnodes',
        ['<space>'] = { expand_levels, nowait = false, desc = 'Toggle folder / expand count levels' },
        ['\\'] = 'close_window',
      },
    },
  },
}
