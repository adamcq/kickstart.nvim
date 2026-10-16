-- Change the default here, or use NVIM_JAVA_LSP=jdtls nvim for one session.
local M = {
  server = vim.env.NVIM_JAVA_LSP or 'jdtls', -- 'intellij' or 'jdtls'; restart Neovim after changing.
  intellij_heap = '4g', -- Maximum heap; the JVM and Gradle also use memory outside this limit.
}

assert(M.server == 'jdtls' or M.server == 'intellij', 'NVIM_JAVA_LSP must be jdtls or intellij')

function M.setup()
  if M.server == 'jdtls' then
    vim.lsp.config('jdtls', require('custom.java').setup())
    vim.lsp.enable 'jdtls'
    return
  end

  require('intellij-lsp').setup {
    jdk = vim.env.JAVA_HOME,
    jvm_args = { '-Xmx' .. M.intellij_heap },
    kotlin = true,
    -- The Git root may contain several builds (GraalFlow's is in dthreads/).
    -- Prefer the enclosing wrapper to per-module files or the repository root.
    root_markers = {
      { 'gradlew', 'mvnw' },
      { 'settings.gradle', 'settings.gradle.kts' },
      { 'pom.xml', 'build.gradle', 'build.gradle.kts' },
      { '.git' },
    },
    inlay_hints = 'manual', -- Use the existing <leader>th toggle.
    organize_imports_on_save = false,
    accept_eula = false, -- Review the bundled agreement with :IntellijAcceptEula.
    data_sharing = 'none',
  }
  local on_attach = vim.lsp.config.intellij.on_attach
  vim.lsp.config('intellij', {
    on_attach = function(client, buf)
      if on_attach then on_attach(client, buf) end
      vim.keymap.set('n', '<leader>jo', '<cmd>IntellijOrganizeImports<CR>', { buffer = buf, desc = 'Java: Organize imports' })
    end,
  })
end

function M.restore_library_sources()
  if M.server == 'jdtls' then require('custom.java').restore_library_sources() end
end

return M
