-- Run with the real init.lua: nvim --headless -i NONE -c 'luafile scripts/check-java.lua'
-- JAVA_CHECK_ROOT overrides the Continuum checkout; JAVA_CHECK_WARMUP=1 rebuilds it first.
local root = vim.uv.fs_realpath(vim.env.JAVA_CHECK_ROOT or '/home/opc/dev/graal-continuum')
local started = vim.uv.hrtime()
local function report(message) print(string.format('[Java check %.1fs] %s', (vim.uv.hrtime() - started) / 1e9, message)) end

local function run()
  assert(root, 'Continuum checkout not found; set JAVA_CHECK_ROOT')
  local java = require 'custom.java'
  local client
  local function open(relative)
    vim.cmd.edit(vim.fn.fnameescape(root .. '/' .. relative))
    assert(java.root(vim.api.nvim_buf_get_name(0)) == root, 'Incorrect multi-module root')
    assert(
      vim.wait(180000, function()
        local attached = vim.lsp.get_clients { name = 'jdtls', bufnr = 0 }
        if #attached == 1 and attached[1].initialized then
          assert(not client or attached[1].id == client.id, 'Modules started separate clients')
          client = attached[1]
          return true
        end
        return false
      end, 100),
      'JDTLS did not attach; inspect :JdtShowLogs'
    )
  end
  local function position(text)
    for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local col = line:find(text, 1, true)
      if col then
        vim.api.nvim_win_set_cursor(0, { index, col - 1 })
        return { textDocument = { uri = vim.uri_from_bufnr(0) }, position = { line = index - 1, character = col - 1 } }
      end
    end
    error('Symbol not found: ' .. text)
  end
  local function request(method, params)
    local response, err = client:request_sync(method, params, 180000, 0)
    assert(response, method .. ': ' .. vim.inspect(err))
    assert(not response.err, method .. ': ' .. vim.inspect(response.err))
    return response.result
  end
  local function definition(text, expected)
    local locations = request('textDocument/definition', position(text))
    assert(locations and #locations > 0, 'No definition for ' .. text)
    assert(vim.lsp.util.show_document(locations[1], client.offset_encoding, { focus = true }), 'Could not open definition')
    local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(content:find(expected, 1, true), 'Unexpected source contents for ' .. text)
    assert(vim.api.nvim_get_current_line():match '%S', 'Definition cursor landed on an empty line')
    assert(vim.lsp.get_clients({ name = 'jdtls', bufnr = 0 })[1].id == client.id, 'Source buffer is not attached')
    assert(vim.fn.maparg('grr', 'n') ~= '', 'References mapping missing in source buffer')
    report(text .. ' definition opened (' .. vim.api.nvim_buf_line_count(0) .. ' source lines)')
  end

  open 'continuum-api/src/main/java/org/graal/continuum/Durable.java'
  report('Client attached; cache: ' .. java.workspace_dir(root))
  assert(client.capabilities.textDocument.completion.completionItem.snippetSupport, 'Blink capabilities missing')
  assert(client.config.settings.java.configuration.runtimes[1].name == 'JavaSE-25', 'JDK 25 runtime missing')
  if vim.env.JAVA_CHECK_WARMUP == '1' then
    local complete
    local original_notify = vim.notify
    vim.notify = function(message, ...)
      report(message)
      if message:match '^Java: Warmup ' or message:match '^Java: Import failed' or message:match '^Java: Build failed' then complete = message end
      original_notify(message, ...)
    end
    vim.cmd.JavaWorkspaceWarmup()
    assert(vim.wait(600000, function() return complete ~= nil end, 100), 'Workspace warmup timed out')
    vim.notify = original_notify
    report('Warmup result: ' .. complete)
  end
  definition('FunctionalInterface', '@interface FunctionalInterface')
  local annotation_refs =
    request('textDocument/references', vim.tbl_extend('force', position 'FunctionalInterface', { context = { includeDeclaration = false } }))
  assert(annotation_refs and #annotation_refs > 0, 'References from JDK source missing')
  report('FunctionalInterface references from JDK source: ' .. #annotation_refs)

  open 'continuum-api/src/main/java/org/graal/continuum/runspec/ExecutableBinarySpec.java'
  definition('String', 'class String')
  open 'continuum-api/src/main/java/org/graal/continuum/runspec/ExecutableBinarySpec.java'
  definition('substring', 'substring(int')

  open 'continuum-cli/src/main/java/org/graal/continuum/Continuum.java'
  definition('ApplicationContext', 'interface ApplicationContext')
  local micronaut_refs =
    request('textDocument/references', vim.tbl_extend('force', position 'ApplicationContext', { context = { includeDeclaration = false } }))
  assert(micronaut_refs and #micronaut_refs > 0, 'References from Micronaut source missing')
  report('ApplicationContext references from library source: ' .. #micronaut_refs)

  open 'continuum-cli/src/main/java/org/graal/continuum/BinaryUploader.java'
  definition('Singleton', '@interface Singleton')

  open 'continuum-api/src/main/java/org/graal/continuum/DurableFactory.java'
  local params = position 'DurableFactory'
  local refs = request('textDocument/references', vim.tbl_extend('force', params, { context = { includeDeclaration = false } }))
  local modules = {}
  for _, location in ipairs(refs or {}) do
    local relative = vim.uri_to_fname(location.uri):sub(#root + 2)
    modules[relative:match '^[^/]+'] = true
  end
  assert(vim.tbl_count(modules) >= 2, 'References do not span modules')
  local implementations = request('textDocument/implementation', params)
  assert(implementations and #implementations > 0, 'DurableFactory implementation missing')
  report('DurableFactory: references across ' .. vim.tbl_count(modules) .. ' modules; ' .. #implementations .. ' implementation(s)')
  local rename = request('textDocument/rename', vim.tbl_extend('force', params, { newName = 'DurableFactoryNavigationCheck' }))
  assert(rename and (rename.changes or rename.documentChanges), 'Rename preview missing')
  report 'Rename preview returned workspace edits; no edits applied'

  open 'continuum-api/src/main/java/org/graal/continuum/runspec/ExecutableBinarySpec.java'
  -- Give import organization something to remove, in memory only.
  local original_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.api.nvim_buf_set_lines(0, 1, 1, false, { 'import java.util.Set;' })
  -- Organize Imports uses the reconciled AST. Wait for the unsaved change to
  -- produce diagnostics instead of racing JDTLS's asynchronous reconcile job.
  assert(
    vim.wait(30000, function()
      for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
        if diagnostic.message:find('java.util.Set', 1, true) and diagnostic.message:find('never used', 1, true) then return true end
      end
      return false
    end, 100),
    'Unused import diagnostic missing'
  )
  local zero = { line = 0, character = 0 }
  local imports = request('java/organizeImports', {
    textDocument = { uri = vim.uri_from_bufnr(0) },
    range = { start = zero, ['end'] = zero },
    context = { diagnostics = {} },
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, original_lines)
  assert(imports ~= nil, 'Unused import removal edit missing')
  request('textDocument/documentSymbol', { textDocument = { uri = vim.uri_from_bufnr(0) } })
  local range_start = position('path.substring').position
  local expression = 'path.substring(BINARY_SCHEME.length())'
  local range_end = { line = range_start.line, character = range_start.character + #expression }
  local context = { textDocument = { uri = vim.uri_from_bufnr(0) }, range = { start = range_start, ['end'] = range_end }, context = { diagnostics = {} } }
  local refactor = request('java/getRefactorEdit', { command = 'extractVariable', context = context, options = { tabSize = 2, insertSpaces = true } })
  assert(refactor and refactor.edit and not refactor.errorMessage, 'Extract variable edit missing: ' .. vim.inspect(refactor))
  local formatting = request('textDocument/formatting', { textDocument = context.textDocument, options = { tabSize = 2, insertSpaces = true } })
  assert(formatting ~= nil, 'Formatting response missing')
  report 'Import organization, extraction, and formatting edits returned; no edits applied'
  assert(#vim.lsp.get_clients { name = 'jdtls' } == 1, 'Duplicate Java clients')
  assert(type(client.config.cmd) == 'table' and vim.tbl_contains(client.config.cmd, '-data'), 'Resolved command missing for log/restart/recovery support')
  vim.cmd.JavaWorkspaceInfo()
  report 'PASS: JDK/Micronaut sources, source-buffer references, cross-module references, implementations, and client reuse'
end

local ok, err = xpcall(run, debug.traceback)
if not ok then report('FAIL: ' .. err) end
for _, client in ipairs(vim.lsp.get_clients()) do
  client:stop()
end
vim.wait(30000, function() return #vim.lsp.get_clients() == 0 end, 100)
vim.cmd(ok and 'qa!' or 'cquit 1')
