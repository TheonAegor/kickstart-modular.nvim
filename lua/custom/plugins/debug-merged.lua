-- Объединённая конфигурация DAP с расширениями для launch.json и .env
-- Объединяет kickstart/plugins/debug.lua с нашими расширениями

-- Импортируем функции расширений
local function read_env_file(file_path)
  local env_vars = {}
  local file = io.open(file_path, 'r')
  if file then
    for line in file:lines() do
      -- Пропускаем комментарии и пустые строки
      if line:match('^%s*[^#%s]') then
        local key, value = line:match('^%s*([%w_]+)%s*=%s*(.*)%s*$')
        if key and value then
          -- Убираем кавычки, если они есть
          value = value:gsub('^["\']', ''):gsub('["\']$', '')
          env_vars[key] = value
        end
      end
    end
    file:close()
  end
  return env_vars
end

-- Функция для поиска корневой директории проекта
local function find_project_root()
  local current_dir = vim.fn.expand('%:p:h')
  local markers = {'.git', '.gitignore', 'package.json', 'go.mod', 'Cargo.toml', 'pyproject.toml', 'requirements.txt'}
  
  while current_dir ~= '/' do
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(current_dir .. '/' .. marker) == 1 or 
         vim.fn.isdirectory(current_dir .. '/' .. marker) == 1 then
        return current_dir
      end
    end
    current_dir = vim.fn.fnamemodify(current_dir, ':h')
  end
  
  -- Если не найден маркер проекта, возвращаем директорию текущего файла
  return vim.fn.expand('%:p:h')
end

-- Функция для замены переменных в строках конфигурации
local function substitute_variables(value, project_root)
  if type(value) == 'string' then
    value = value:gsub('${workspaceFolder}', project_root)
    value = value:gsub('${file}', vim.fn.expand('%:p'))
    value = value:gsub('${workspaceRootFolderName}', vim.fn.fnamemodify(project_root, ':t'))
    value = value:gsub('${fileBasename}', vim.fn.expand('%:t'))
    value = value:gsub('${fileBasenameNoExtension}', vim.fn.expand('%:t:r'))
    value = value:gsub('${fileDirname}', vim.fn.expand('%:p:h'))
  end
  return value
end

-- Рекурсивная замена переменных в конфигурации
local function substitute_config_variables(config, project_root)
  if type(config) == 'table' then
    local result = {}
    for key, value in pairs(config) do
      if type(value) == 'table' then
        result[key] = substitute_config_variables(value, project_root)
      else
        result[key] = substitute_variables(value, project_root)
      end
    end
    return result
  else
    return substitute_variables(config, project_root)
  end
end

-- Функция для чтения launch.json
local function load_launch_json()
  local project_root = find_project_root()
  local launch_json_path = project_root .. '/.vscode/launch.json'
  
  if vim.fn.filereadable(launch_json_path) == 1 then
    local file = io.open(launch_json_path, 'r')
    if file then
      local content = file:read('*all')
      file:close()
      
      -- Удаляем комментарии из JSON (простая версия)
      content = content:gsub('//.-\n', '\n')
      
      local success, decoded = pcall(vim.json.decode, content)
      if success and decoded.configurations then
        return decoded.configurations, project_root
      else
        vim.notify('Ошибка парсинга launch.json: ' .. (decoded or 'неизвестная ошибка'), vim.log.levels.WARN)
      end
    end
  end
  
  return nil, project_root
end

-- Функция для применения конфигураций из launch.json
local function apply_launch_configurations(dap)
  local configurations, project_root = load_launch_json()
  if not configurations then
    return
  end
  
  for _, config in ipairs(configurations) do
    -- Создаем копию конфигурации для обработки
    local processed_config = vim.deepcopy(config)
    
    -- Заменяем переменные в конфигурации
    processed_config = substitute_config_variables(processed_config, project_root)
    
    local filetype = processed_config.type or 'unknown'
    
    -- Устанавливаем рабочую директорию как корень проекта, если не указана
    if not processed_config.cwd then
      processed_config.cwd = project_root
    end
    
    -- Загружаем переменные окружения из .env файла
    local env_file_path = project_root .. '/.env'
    if vim.fn.filereadable(env_file_path) == 1 then
      local env_vars = read_env_file(env_file_path)
      if not processed_config.env then
        processed_config.env = {}
      end
      
      -- Объединяем переменные из .env с уже существующими
      for key, value in pairs(env_vars) do
        if not processed_config.env[key] then
          processed_config.env[key] = value
        end
      end
    end
    
    -- Инициализируем конфигурации для соответствующего типа файла
    if not dap.configurations[filetype] then
      dap.configurations[filetype] = {}
    end
    
    -- Проверяем, не существует ли уже конфигурация с таким именем
    local exists = false
    for _, existing in ipairs(dap.configurations[filetype]) do
      if existing.name == processed_config.name then
        exists = true
        break
      end
    end
    
    if not exists then
      table.insert(dap.configurations[filetype], processed_config)
    end
  end
  
  vim.notify('Загружены конфигурации из launch.json для проекта: ' .. project_root, vim.log.levels.INFO)
end

-- Функция для создания функции окружения
local function create_env_function(project_root)
  return function()
    local env_file_path = project_root .. '/.env'
    if vim.fn.filereadable(env_file_path) == 1 then
      return read_env_file(env_file_path)
    end
    return {}
  end
end

return {
  -- NOTE: Yes, you can install new plugins here!
  'mfussenegger/nvim-dap',
  -- NOTE: And you can specify dependencies as well
  dependencies = {
    -- Creates a beautiful debugger UI
    'rcarriga/nvim-dap-ui',

    -- Required dependency for nvim-dap-ui
    'nvim-neotest/nvim-nio',

    -- Installs the debug adapters for you
    'mason-org/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',

    -- Add your own debuggers here
    'leoluz/nvim-dap-go',
  },
  keys = {
    -- Basic debugging keymaps, feel free to change to your liking!
    {
      '<F5>',
      function()
        require('dap').continue()
      end,
      desc = 'Debug: Start/Continue',
    },
    {
      '<F1>',
      function()
        require('dap').step_into()
      end,
      desc = 'Debug: Step Into',
    },
    {
      '<F2>',
      function()
        require('dap').step_over()
      end,
      desc = 'Debug: Step Over',
    },
    {
      '<F3>',
      function()
        require('dap').step_out()
      end,
      desc = 'Debug: Step Out',
    },
    {
      '<leader>b',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = 'Debug: Toggle Breakpoint',
    },
    {
      '<leader>B',
      function()
        require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
      end,
      desc = 'Debug: Set Breakpoint',
    },
    -- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
    {
      '<F7>',
      function()
        require('dapui').toggle()
      end,
      desc = 'Debug: See last session result.',
    },
  },
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'

    require('mason-nvim-dap').setup {
      -- Makes a best effort to setup the various debuggers with
      -- reasonable debug configurations
      automatic_installation = true,

      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      handlers = {},

      -- You'll need to check that you have the required things installed
      -- online, please don't ask me how to install them :)
      ensure_installed = {
        -- Update this to ensure that you have the debuggers for the langs you want
        'delve',
      },
    }

    -- Dap UI setup
    -- For more information, see |:help nvim-dap-ui|
    dapui.setup {
      -- Set icons to characters that are more likely to work in every terminal.
      --    Feel free to remove or use ones that you like more! :)
      --    Don't feel like these are good choices.
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      controls = {
        icons = {
          pause = '⏸',
          play = '▶',
          step_into = '⏎',
          step_over = '⏭',
          step_out = '⏮',
          step_back = 'b',
          run_last = '▶▶',
          terminate = '⏹',
          disconnect = '⏏',
        },
      },
    }

    -- Change breakpoint icons
    -- vim.api.nvim_set_hl(0, 'DapBreak', { fg = '#e51400' })
    -- vim.api.nvim_set_hl(0, 'DapStop', { fg = '#ffcc00' })
    -- local breakpoint_icons = vim.g.have_nerd_font
    --     and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
    --   or { Breakpoint = '●', BreakpointCondition = '⊜', BreakpointRejected = '⊘', LogPoint = '◆', Stopped = '⭔' }
    -- for type, icon in pairs(breakpoint_icons) do
    --   local tp = 'Dap' .. type
    --   local hl = (type == 'Stopped') and 'DapStop' or 'DapBreak'
    --   vim.fn.sign_define(tp, { text = icon, texthl = hl, numhl = hl })
    -- end

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close

    -- Install golang specific config
    require('dap-go').setup {
      delve = {
        -- On Windows delve must be run attached or it crashes.
        -- See https://github.com/leoluz/nvim-dap-go/blob/main/README.md#configuring
        detached = vim.fn.has 'win32' == 0,
      },
    }

    -- ========================================
    -- НАШИ РАСШИРЕНИЯ ДЛЯ DAP
    -- ========================================

    -- Настройка адаптера для Go (дополнительно к dap-go)
    dap.adapters.go = {
      type = 'server',
      port = '${port}',
      executable = {
        command = vim.fn.expand('~/go/bin/dlv'), -- Используем полный путь к delve
        args = { 'dap', '-l', '127.0.0.1:${port}' },
      },
      options = {
        initialize_timeout_sec = 20,
      },
    }
    
    -- Настройка адаптера для Python
    dap.adapters.python = {
      type = 'executable',
      command = 'python',
      args = { '-m', 'debugpy.adapter' },
    }
    
    -- Настройка адаптера для Node.js
    dap.adapters.node2 = {
      type = 'executable',
      command = 'node',
      args = { vim.fn.stdpath('data') .. '/mason/packages/node-debug2-adapter/out/src/nodeDebug.js' },
    }

    -- Расширенные конфигурации для Go
    if not dap.configurations.go then
      dap.configurations.go = {}
    end
    
    table.insert(dap.configurations.go, {
      type = 'go',
      name = 'Debug (from current file directory)',
      request = 'launch',
      program = function()
        return find_project_root()
      end,
      cwd = function()
        return find_project_root()
      end,
      env = function()
        local project_root = find_project_root()
        return create_env_function(project_root)()
      end,
    })
    
    table.insert(dap.configurations.go, {
      type = 'go',
      name = 'Debug current file',
      request = 'launch',
      program = '${file}',
      cwd = function()
        return find_project_root()
      end,
      env = function()
        local project_root = find_project_root()
        return create_env_function(project_root)()
      end,
    })
    
    table.insert(dap.configurations.go, {
      type = 'go',
      name = 'Debug with arguments',
      request = 'launch',
      program = function()
        return find_project_root()
      end,
      cwd = function()
        return find_project_root()
      end,
      args = function()
        return vim.split(vim.fn.input('Arguments: '), ' ')
      end,
      env = function()
        local project_root = find_project_root()
        return create_env_function(project_root)()
      end,
    })
    
    -- Настройка для Python
    if not dap.configurations.python then
      dap.configurations.python = {}
    end
    
    table.insert(dap.configurations.python, {
      type = 'python',
      request = 'launch',
      name = 'Launch file (from project root)',
      program = '${file}',
      pythonPath = function()
        return '/usr/bin/python3'
      end,
      cwd = function()
        return find_project_root()
      end,
      env = function()
        local project_root = find_project_root()
        return create_env_function(project_root)()
      end,
    })
    
    -- Настройка для Node.js
    if not dap.configurations.javascript then
      dap.configurations.javascript = {}
    end
    
    table.insert(dap.configurations.javascript, {
      type = 'node2',
      request = 'launch',
      name = 'Launch file (from project root)',
      program = '${file}',
      cwd = function()
        return find_project_root()
      end,
      env = function()
        local project_root = find_project_root()
        return create_env_function(project_root)()
      end,
    })
    
    -- То же самое для TypeScript
    dap.configurations.typescript = dap.configurations.javascript
    
    -- Автозагрузка конфигураций из launch.json при старте дебаггера
    local original_continue = dap.continue
    dap.continue = function(...)
      apply_launch_configurations(dap)
      return original_continue(...)
    end
    
    -- Команды для ручной перезагрузки конфигураций
    vim.api.nvim_create_user_command('DapReloadConfig', function()
      apply_launch_configurations(dap)
    end, { desc = 'Перезагрузить конфигурации DAP из launch.json' })
    
    vim.api.nvim_create_user_command('DapShowProjectRoot', function()
      local root = find_project_root()
      vim.notify('Корень проекта: ' .. root, vim.log.levels.INFO)
    end, { desc = 'Показать определенную корневую директорию проекта' })
    
    vim.api.nvim_create_user_command('DapShowEnvVars', function()
      local project_root = find_project_root()
      local env_file_path = project_root .. '/.env'
      if vim.fn.filereadable(env_file_path) == 1 then
        local env_vars = read_env_file(env_file_path)
        local vars_str = ''
        for key, value in pairs(env_vars) do
          vars_str = vars_str .. key .. '=' .. value .. '\n'
        end
        if vars_str ~= '' then
          vim.notify('Переменные из .env:\n' .. vars_str, vim.log.levels.INFO)
        else
          vim.notify('Файл .env пуст или не содержит корректных переменных', vim.log.levels.WARN)
        end
      else
        vim.notify('Файл .env не найден в: ' .. env_file_path, vim.log.levels.WARN)
      end
    end, { desc = 'Показать переменные окружения из .env файла' })
    
    vim.api.nvim_create_user_command('DapCheckAdapters', function()
      local adapters_info = ''
      for adapter_name, adapter_config in pairs(dap.adapters) do
        adapters_info = adapters_info .. '✅ ' .. adapter_name .. ': '
        if adapter_config.type == 'executable' then
          adapters_info = adapters_info .. 'executable (' .. adapter_config.command .. ')\n'
        elseif adapter_config.type == 'server' then
          adapters_info = adapters_info .. 'server\n'
        else
          adapters_info = adapters_info .. adapter_config.type .. '\n'
        end
      end
      if adapters_info ~= '' then
        vim.notify('Настроенные адаптеры DAP:\n' .. adapters_info, vim.log.levels.INFO)
      else
        vim.notify('Адаптеры DAP не настроены', vim.log.levels.WARN)
      end
    end, { desc = 'Показать настроенные адаптеры DAP' })
    
    -- Автоматическое обнаружение типа файла для дебаггера
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'go', 'python', 'javascript', 'typescript' },
      callback = function()
        -- Загружаем конфигурации при открытии поддерживаемого типа файла
        apply_launch_configurations(dap)
      end,
    })

    vim.notify('DAP настроен с расширениями: поддержка launch.json и .env файлов активна', vim.log.levels.INFO)
  end,
} 