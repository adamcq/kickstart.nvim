-- Java-specific support; init.lua owns the single vim.lsp.enable('jdtls') startup path.
local M = {}
local workspaces = {}
local continuum = '/home/opc/dev/graal-continuum'

local function notify(message, level) vim.notify('Java: ' .. message, level or vim.log.levels.INFO) end

function M.root(path)
  if path:match '^%a[%w+.-]*://' then return nil end
  path = vim.uv.fs_realpath(path) or path
  -- Prefer the enclosing multi-project repository over nested Gradle settings.
  local repo = vim.fs.root(path, '.git')
  if repo and (vim.uv.fs_stat(repo .. '/settings.gradle') or vim.uv.fs_stat(repo .. '/settings.gradle.kts') or vim.uv.fs_stat(repo .. '/pom.xml')) then
    return repo
  end
  return vim.fs.root(path, { 'gradlew', 'settings.gradle', 'settings.gradle.kts', 'mvnw', 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git' })
end

function M.workspace_dir(root)
  root = vim.uv.fs_realpath(root) or root
  local name = root == continuum and 'graal-continuum' or (vim.fs.basename(root) .. '-' .. vim.fn.sha256(root):sub(1, 12))
  return vim.fs.joinpath(vim.fn.stdpath 'cache', 'jdtls', 'workspace', name)
end

local function resolve_jdk()
  local home = vim.env.JAVA_HOME
  if not home or home == '' then
    local java = vim.uv.fs_realpath(vim.fn.exepath 'java')
    home = java and vim.fs.dirname(vim.fs.dirname(java))
  end
  if not home or vim.fn.executable(home .. '/bin/java') ~= 1 or not vim.uv.fs_stat(home .. '/release') then
    error 'Set JAVA_HOME to a JDK with bin/java and a release file, then restart Neovim.'
  end
  home = vim.uv.fs_realpath(home) or home
  local release = table.concat(vim.fn.readfile(home .. '/release'), '\n')
  local version = tonumber(release:match 'JAVA_VERSION="(%d+)')
  if not version or version < 21 then error 'JDTLS requires JDK 21 or newer. Continuum requires JDK 25.' end
  return { home = home, version = version, sources = home .. '/lib/src.zip' }
end

local function configure_gradle(root, settings)
  settings.home = nil
  settings.version = nil
  local wrapper = root .. '/gradle/wrapper/gradle-wrapper.properties'
  if not vim.uv.fs_stat(wrapper) then return 'JDTLS default (no root wrapper)' end
  local version = table.concat(vim.fn.readfile(wrapper), '\n'):match 'gradle%-([%d.]+)%-[%w]+%.zip'
  if not version then return 'Root wrapper; custom distribution' end
  -- Included builds such as build-logic have no wrapper of their own. Match the
  -- root distribution rather than falling back to Buildship's bundled Gradle.
  local user_home = vim.env.GRADLE_USER_HOME or vim.fs.joinpath(vim.env.HOME, '.gradle')
  local installs = vim.fn.glob(user_home .. '/wrapper/dists/gradle-' .. version .. '-*/*/gradle-' .. version, false, true)
  for _, home in ipairs(installs) do
    if vim.uv.fs_stat(home .. '/lib') then
      settings.home = home
      return home
    end
  end
  settings.version = version
  return version .. ' (download required; run the root ./gradlew --version first)'
end

local function lock_owner(workspace)
  -- Eclipse takes a POSIX lock, not a flock. Check live locks, not stale lock files.
  if vim.fn.executable 'lslocks' ~= 1 then return nil end
  local result = vim.system({ 'lslocks', '--json', '--notruncate', '--output', 'PATH,PID' }, { text = true }):wait(2000)
  if result.code ~= 0 or result.stdout == '' then return nil end
  local ok, locks = pcall(vim.json.decode, result.stdout)
  if ok then
    for _, lock in ipairs(locks.locks or {}) do
      if lock.path == workspace .. '/.metadata/.lock' then return lock.pid end
    end
  end
end

local function current_client()
  local clients = vim.lsp.get_clients { name = 'jdtls', bufnr = 0 }
  if #clients == 1 then return clients[1] end
  notify('Open a Java buffer with JDTLS attached first.', vim.log.levels.WARN)
end

local function request(client, method, params, callback)
  local sent = client:request(method, params, callback)
  if not sent then callback { message = 'The language server is not accepting requests.' } end
end

local function refresh(client, callback)
  local state = workspaces[client.config.root_dir]
  if state.refresh_callback then
    callback { message = 'A configuration refresh is already running.' }
    return
  end
  state.refresh_callback = callback
  state.refresh_started = false
  state.refresh_result = nil
  -- Updating the root project synchronizes the entire Gradle multi-project build.
  -- This is a notification. Completion is reported by language/status, not an RPC response.
  local sent = client:notify('java/projectConfigurationUpdate', { uri = vim.uri_from_fname(client.config.root_dir) })
  if not sent then
    state.refresh_callback = nil
    callback { message = 'The language server is not accepting notifications.' }
    return
  end
  vim.defer_fn(function()
    if state.refresh_callback == callback then
      state.refresh_callback = nil
      callback { message = 'Refresh did not finish within five minutes. Check Fidget and :JdtShowLogs.' }
    end
  end, 300000)
end

function M.warmup()
  local client = current_client()
  if not client then return end
  local state = workspaces[client.config.root_dir]
  if not state then return end
  if state.busy then
    notify('Workspace warmup is already running.', vim.log.levels.WARN)
    return
  end
  state.busy = true
  state.status = 'Refreshing Gradle configuration'
  notify(state.status .. '; progress is shown by Fidget.')
  refresh(client, function(err)
    if err then
      state.busy = false
      state.status = 'Import failed: ' .. err.message
      notify(state.status, vim.log.levels.ERROR)
      return
    end
    state.status = 'Building the Java workspace'
    notify(state.status)
    request(client, 'java/buildWorkspace', true, function(build_err, result)
      state.busy = false
      local statuses = { [0] = 'failed', [1] = 'completed', [2] = 'completed with build errors', [3] = 'cancelled' }
      state.status = build_err and ('Build failed: ' .. build_err.message) or ('Warmup ' .. (statuses[result] or 'returned an unknown status'))
      if result == 1 and state.refresh_result == 'WARNING' then state.status = state.status .. ' with project import warnings' end
      notify(
        state.status .. '. Use :JavaWorkspaceInfo and :JdtShowLogs for details.',
        result == 1 and state.refresh_result ~= 'WARNING' and vim.log.levels.INFO or vim.log.levels.WARN
      )
      if result ~= 1 then
        local diagnostics = vim.diagnostic.get(nil, { namespace = vim.lsp.diagnostic.get_namespace(client.id), severity = vim.diagnostic.severity.ERROR })
        vim.fn.setqflist({}, 'r', { title = 'Java workspace build errors', items = vim.diagnostic.toqflist(diagnostics) })
        if #diagnostics > 0 then vim.cmd.copen() end
      end
    end)
  end)
end

function M.info()
  local client = current_client()
  if not client then return end
  local state = workspaces[client.config.root_dir]
  local lines = {
    'Root: ' .. client.config.root_dir,
    'Cache: ' .. M.workspace_dir(client.config.root_dir),
    'JDK: ' .. (state and state.jdk.home or 'unknown'),
    'JDK sources: ' .. (state and state.jdk.sources or 'unknown'),
    'Gradle fallback for included builds: ' .. (state and state.gradle or 'unknown'),
    'Source archive available: ' .. tostring(state and vim.uv.fs_stat(state.jdk.sources) ~= nil),
    'Status: ' .. (state and state.status or 'unknown'),
    'Server status: ' .. (state and state.service_status or 'unknown'),
    'Client: ' .. client.id .. '; attached buffers: ' .. vim.tbl_count(client.attached_buffers),
    'JDTLS log: ' .. M.workspace_dir(client.config.root_dir) .. '/.metadata/.log',
    'Neovim LSP log: ' .. vim.lsp.log.get_filename(),
  }
  vim.api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
end

function M.setup()
  local jdtls = require 'jdtls' -- Registers Java code-action command handlers.
  jdtls.settings.jdt_uri_timeout_ms = 30000 -- Allow a first dependency-source download.
  vim.api.nvim_create_user_command('JavaWorkspaceWarmup', M.warmup, { desc = 'Refresh Gradle and build the Java workspace' })
  vim.api.nvim_create_user_command('JavaWorkspaceInfo', M.info, { desc = 'Show Java runtime, workspace, cache, and logs' })
  vim.api.nvim_create_user_command('JavaWorkspaceRefresh', function()
    local client = current_client()
    if client then
      if workspaces[client.config.root_dir].busy then
        notify('Wait for the current workspace warmup to finish.', vim.log.levels.WARN)
        return
      end
      notify 'Refreshing the Java workspace; watch Fidget for progress.'
      refresh(
        client,
        function(err)
          notify(
            err and ('Import failed: ' .. err.message) or 'Workspace refresh finished; check :JavaWorkspaceInfo for project status.',
            err and vim.log.levels.ERROR
          )
        end
      )
    end
  end, { desc = 'Refresh the Java workspace build configuration' })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('custom-java', { clear = true }),
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if not client or client.name ~= 'jdtls' then return end
      local function map(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = 'Java: ' .. desc }) end
      map('n', '<leader>jo', jdtls.organize_imports, 'Organize imports')
      map('n', '<leader>jv', jdtls.extract_variable, 'Extract variable')
      map('x', '<leader>jv', function() jdtls.extract_variable { visual = true } end, 'Extract variable')
      map('n', '<leader>jc', jdtls.extract_constant, 'Extract constant')
      map('x', '<leader>jc', function() jdtls.extract_constant { visual = true } end, 'Extract constant')
      map('x', '<leader>jm', function() jdtls.extract_method { visual = true } end, 'Extract method')
    end,
  })

  return {
    root_dir = function(buf, on_dir)
      local root = M.root(vim.api.nvim_buf_get_name(buf))
      if root then on_dir(root) end
    end,
    cmd = function(dispatchers, config)
      local workspace = M.workspace_dir(config.root_dir)
      local owner = lock_owner(workspace)
      if owner then error('Java workspace is already in use by PID ' .. owner .. '. Close that editor before restarting JDTLS.') end
      local jdk = resolve_jdk()
      if config.root_dir == continuum and jdk.version ~= 25 then error 'Continuum requires JAVA_HOME to point to JDK 25.' end
      config.cmd_env = vim.tbl_extend('force', config.cmd_env or {}, { JAVA_HOME = jdk.home })
      config.settings.java.configuration.runtimes = {
        { name = 'JavaSE-' .. jdk.version, path = jdk.home, sources = jdk.sources, default = true },
      }
      config.settings.java.import.gradle.java = { home = jdk.home }
      local gradle = configure_gradle(config.root_dir, config.settings.java.import.gradle)
      -- JDTLS starts importing during initialize, before didChangeConfiguration.
      config.init_options.settings = config.settings
      workspaces[config.root_dir] = { jdk = jdk, gradle = gradle, status = 'Starting; watch Fidget for import and indexing progress' }
      if not vim.uv.fs_stat(jdk.sources) then
        vim.schedule(function() notify('JDK src.zip is missing; JDK navigation will use decompiled contents.', vim.log.levels.WARN) end)
      end
      local executable = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin', 'jdtls')
      if vim.fn.executable(executable) ~= 1 then error 'Install jdtls with :MasonInstall jdtls@v1.61.0 first.' end
      local args = { executable, '-data', workspace, '--jvm-arg=-Xmx2g' }
      for arg in (vim.env.JDTLS_JVM_ARGS or ''):gmatch '%S+' do
        table.insert(args, '--jvm-arg=' .. arg)
      end
      -- nvim-jdtls's log/restart/recovery commands inspect the resolved argv.
      config.cmd = args
      return vim.lsp.rpc.start(args, dispatchers, { cwd = config.root_dir, env = config.cmd_env, detached = config.detached })
    end,
    init_options = { extendedClientCapabilities = jdtls.extendedClientCapabilities },
    handlers = {
      ['language/status'] = function(_, result, ctx)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        local state = client and workspaces[client.config.root_dir]
        if not state or not result then return end
        state.service_status = result.type .. ': ' .. result.message
        if not state.busy then state.status = state.service_status end
        if state.refresh_callback then
          if result.type == 'Message' and result.message == 'Updating project configurations...' then state.refresh_started = true end
          if state.refresh_started and (result.type == 'ProjectStatus' or result.type == 'Error') then
            local callback = state.refresh_callback
            state.refresh_callback = nil
            state.refresh_result = result.message
            callback(result.type == 'Error' and { message = result.message } or nil)
          end
        end
        if result.type == 'Error' then notify(result.message, vim.log.levels.ERROR) end
      end,
    },
    on_exit = function(code, _, client_id)
      local client = vim.lsp.get_client_by_id(client_id)
      local state = client and workspaces[client.config.root_dir]
      if state then
        state.busy = false
        state.status = 'Server stopped'
        if state.refresh_callback then
          local callback = state.refresh_callback
          state.refresh_callback = nil
          callback { message = 'The language server stopped during refresh.' }
        end
      end
      if code ~= 0 then vim.schedule(function() notify('JDTLS exited with code ' .. code .. '; check :JavaWorkspaceInfo logs.', vim.log.levels.ERROR) end) end
    end,
    settings = {
      java = {
        configuration = { updateBuildConfiguration = 'automatic' },
        import = { gradle = { enabled = true, wrapper = { enabled = true }, annotationProcessing = { enabled = true } } },
        eclipse = { downloadSources = true },
        maven = { downloadSources = true },
        autobuild = { enabled = true },
        signatureHelp = { enabled = true },
        hover = { javadoc = { enabled = true } },
        saveActions = { organizeImports = false },
        -- Keep Java formatting available to the existing Conform LSP fallback.
        format = { enabled = true },
      },
    },
  }
end

return M
