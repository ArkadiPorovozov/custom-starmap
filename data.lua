-- data.lua: прототипы тестового мода. Factorio 2.1.14 + Space Age.

data:extend({
  {
    type = "custom-input",
    name = "space-map-rework-open-starmap",
    key_sequence = "SHIFT + M",
    alternative_key_sequence = "CONTROL + SHIFT + M",
    consuming = "game-only",
    order = "a"
  },
  {
    type = "custom-input",
    name = "space-map-rework-toggle-info",
    key_sequence = "SHIFT + I",
    consuming = "game-only",
    order = "b"
  },
  {
    type = "custom-input",
    name = "space-map-rework-left-click", -- имя историческое; физически это ПКМ
    key_sequence = "mouse-button-2",
    consuming = "none",
    include_selected_prototype = true,
    action = "lua",
    order = "c"
  },
  {
    type = "custom-input",
    name = "space-map-rework-right-click",
    key_sequence = "mouse-button-2",
    consuming = "none",
    include_selected_prototype = true,
    action = "lua",
    order = "d"
  },
  {
    type = "custom-input",
    name = "space-map-rework-pin-platform", -- закреп/откреп платформы (мини-окно с камерой)
    key_sequence = "SHIFT + P",
    consuming = "game-only",
    order = "e"
  }
})

-- SpritePrototype на каждый кадр ванильного листа платформ
-- (starmap-platform-moving-states.png: 3 кадра 54x37 по вертикали).
-- При отсутствии файла control-стадия использует polygon-заглушку.
for i = 1, 3 do
  data:extend({
    {
      type = "sprite",
      name = "space-map-rework-platform-" .. i,
      filename = "__core__/graphics/icons/starmap-platform-moving-states.png",
      position = {0, (i - 1) * 37},
      size = {54, 37},
      scale = 1
    }
  })
end

-- Стоячая платформа на орбите: ванильный лист stacked-states
-- (__core__/graphics/icons/starmap-platform-stacked-states.png, лист 54x162 —
-- 3 кадра вертикально по 54x54; берётся только первый, верхний).
data:extend({
  {
    type = "sprite",
    name = "space-map-rework-platform-parked",
    filename = "__core__/graphics/icons/starmap-platform-stacked-states.png",
    position = {0, 0},
    size = {54, 54},
    scale = 1
  }
})

-- Плейсхолдер неисследованных тел (vanilla mip/not-available.png, 32x32).
-- Потребитель: control/starsystem.lua (рисунок вместо иконки тела).
data:extend({
  {
    type = "sprite",
    name = "space-map-rework-body-undiscovered",
    filename = "__core__/graphics/icons/mip/not-available.png",
    position = {0, 0},
    size = {32, 32},
    scale = 1
  }
})

data:extend({
  {
    type = "simple-entity",
    name = "space-map-rework-planet-marker",
    flags = {
      "placeable-off-grid",
      "not-blueprintable",
      "not-deconstructable",
      "not-flammable",
      "not-repairable"
    },
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.3, -0.3}, {0.3, 0.3}}, -- fallback; рабочие маркеры — клоны под размер планеты
    collision_mask = {layers = {}},
    selectable_in_game = true,
    max_health = 10000000,
    picture = {
      filename = "__core__/graphics/empty.png",
      width = 1,
      height = 1
    },
    icon = "__core__/graphics/empty.png",
    icon_size = 1,
    order = "z-space-map-rework-marker"
  }
})

-- Кликабельный маркер орбитальной платформы (hover -> камера платформы).
-- selection_box — ЗЕРКАЛО PLATFORM_MARKER_HALF из control/constants.lua
-- (data-стадия не видит control-константы; держать синхронно).
data:extend({
  {
    type = "simple-entity",
    name = "space-map-rework-platform-marker",
    flags = {
      "placeable-off-grid",
      "not-blueprintable",
      "not-deconstructable",
      "not-flammable",
      "not-repairable"
    },
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.7, -0.7}, {0.7, 0.7}}, -- PLATFORM_MARKER_HALF = 0.7
    collision_mask = {layers = {}},
    selectable_in_game = true,
    max_health = 10000000,
    picture = {
      filename = "__core__/graphics/empty.png",
      width = 1,
      height = 1
    },
    icon = "__core__/graphics/empty.png",
    icon_size = 1,
    order = "z-space-map-rework-platform-marker"
  }
})

-- Кликабельный маркер летящей платформы. Имя — ЗЕРКАЛО TRAVEL_MARKER_NAME
-- из control/constants.lua. Невидимый (спрайт рисует routes.lua), только хитбокс.
data:extend({
  {
    type = "simple-entity",
    name = "space-map-rework-travel-marker",
    flags = {
      "placeable-off-grid",
      "not-blueprintable",
      "not-deconstructable",
      "not-flammable",
      "not-repairable"
    },
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    -- selection_box — ЗЕРКАЛО TRAVEL_MARKER_HALF (1.6), держать синхронно
    selection_box = {{-1.6, -1.6}, {1.6, 1.6}},
    collision_mask = {layers = {}},
    selectable_in_game = true,
    max_health = 10000000,
    picture = {
      filename = "__core__/graphics/empty.png",
      width = 1,
      height = 1
    },
    icon = "__core__/graphics/empty.png",
    icon_size = 1,
    order = "z-space-map-rework-travel-marker"
  }
})

-- Клон empty-space без autoplace: заливка поверхности карты.
if data.raw.tile["empty-space"] then
  local empty = table.deepcopy(data.raw.tile["empty-space"])
  empty.name = "space-map-rework-empty-space-no-correct"
  empty.autoplace = nil
  data:extend({empty})
end

