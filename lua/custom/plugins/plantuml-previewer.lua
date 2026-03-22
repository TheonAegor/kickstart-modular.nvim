return {
  'weirongxu/plantuml-previewer.vim',
  ft = { 'plantuml' },
  dependencies = {
    'tyru/open-browser.vim',
    'aklt/plantuml-syntax',
  },
  init = function() end,
  keys = {
    { '<leader>pp', '<cmd>PlantumlOpen<cr>', desc = 'PlantUML Preview' },
  },
}
