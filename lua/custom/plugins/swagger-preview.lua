return {
  'vinnymeller/swagger-preview.nvim',
  build = 'npm install --prefix . swagger-ui-watcher',
  cmd = { 'SwaggerPreview', 'SwaggerPreviewStop' },
  ft = { 'yaml', 'json' },
  keys = {
    { '<leader>sp', '<cmd>SwaggerPreviewSafe<cr>', desc = 'Swagger Preview' },
    { '<leader>sP', '<cmd>SwaggerPreviewStop<cr>', desc = 'Swagger Preview Stop' },
  },
  config = function()
    require('swagger-preview').setup({
      port = 8123,
      host = 'localhost',
    })

    -- Kill any orphan process on the port (e.g. from a previous Neovim session)
    -- before starting, so EADDRINUSE never occurs.
    local function safe_start()
      local sp = require('swagger-preview')
      if not sp.server_on then
        vim.fn.system("lsof -ti:8123 | xargs kill -9 2>/dev/null")
      end
      sp.start_server()
    end

    vim.api.nvim_create_user_command('SwaggerPreviewSafe', safe_start, {})
  end,
}
