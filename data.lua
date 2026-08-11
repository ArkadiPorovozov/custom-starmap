-- data.lua - базовые прототипы для SE-style starmap
-- Factorio 2.1.14, SA

data:extend({
  {
    type = "custom-input",
    name = "custom-se-open-starmap",
    key_sequence = "SHIFT + M",
    alternative_key_sequence = "CONTROL + SHIFT + M",
    consuming = "game-only",
    order = "a"
  },
  {
    type = "custom-input",
    name = "custom-se-toggle-info",
    key_sequence = "SHIFT + I",
    consuming = "game-only",
    order = "b"
  },
  {
    type = "custom-input",
    name = "custom-se-left-click", -- имя оставлено для совместимости, но теперь ПКМ
    key_sequence = "mouse-button-2",
    consuming = "none",
    include_selected_prototype = true,
    action = "lua",
    order = "c"
  },
  {
    type = "custom-input",
    name = "custom-se-right-click",
    key_sequence = "mouse-button-2",
    consuming = "none",
    include_selected_prototype = true,
    action = "lua",
    order = "d"
  }
})

-- Спрайты платформ из ванильного листа (3 картинки в столбец, 54x37 каждая;
-- лист 54x111). Регистрируем как SpritePrototype — тогда для рендера
-- доступен валидный SpritePath "custom-se-starmap-platform-N".
-- Если файла нет (другая сборка) — control упадёт на polygon-заглушку.
for i = 1, 3 do
  data:extend({
    {
      type = "sprite",
      name = "custom-se-starmap-platform-" .. i,
      filename = "__core__/graphics/icons/starmap-platform-moving-states.png",
      position = {0, (i - 1) * 37},
      size = {54, 37},
      scale = 1
    }
  })
end

data:extend({
  {
    type = "simple-entity",
    name = "custom-se-planet-marker",
    flags = {
      "placeable-off-grid",
      "not-blueprintable",
      "not-deconstructable",
      "not-flammable",
      "not-repairable"
    },
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}}, -- компактный фоллбэк (основные — клоны по размеру планеты)
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
    order = "z-custom-se-marker"
  }
})

-- Кликабельный маркер орбитальной платформы (наведение → камера платформы).
-- selection_box ЗЕРКАЛИТ PLATFORM_MARKER_HALF из control/constants.lua —
-- держать синхронно (data-стадия не видит control-константы)!
data:extend({
  {
    type = "simple-entity",
    name = "custom-se-platform-marker",
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
    order = "z-custom-se-platform-marker"
  }
})

-- Тайл космоса без автокоррекции для заливки поверхности
if data.raw.tile["empty-space"] then
  local empty = table.deepcopy(data.raw.tile["empty-space"])
  empty.name = "custom-se-empty-space-no-correct"
  empty.autoplace = nil
  data:extend({empty})
end
