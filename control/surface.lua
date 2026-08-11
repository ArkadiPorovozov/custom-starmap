-- control/surface.lua
-- 1000x1000 empty-space, out-of-map по краям, всегда прогружена как радаром

function get_or_create_surface()
  local surface = game.surfaces[SURFACE_NAME]
  if surface and surface.valid then return surface end

  local mgs = {
    width = 1000,
    height = 1000,
    default_enable_all_autoplace_controls = false,
    autoplace_controls = {},
    autoplace_settings = {tile = {settings = {}}, entity = {settings = {}}, decorative = {settings = {}}},
    property_expression_names = {cliffiness = "0", cliff_elevation = "0"},
    cliff_settings = {cliff_elevation_0 = 0, cliff_elevation_interval = 0, richness = 0},
    starting_area = "none",
    peaceful_mode = true,
    seed = 123456
  }

  surface = game.create_surface(SURFACE_NAME, mgs)
  if surface then
    pcall(function()
      surface.freeze_daytime = true
      surface.daytime = 0.5 -- вечный день
      surface.brightness_visual_weights = {r = 1, g = 1, b = 1}
      surface.min_brightness = 1.0
      surface.show_clouds = false
    end)
    chart_surface_as_radar(surface)
  end
  return surface
end

function chart_surface_as_radar(surface)
  if not surface or not surface.valid then return end
  -- 1000 тайлов = ~32 чанка в каждую сторону (500/32 ~= 15.6)
  local chunk_radius = math.ceil(MAP_LIMIT / 32) + 1
  for cx = -chunk_radius, chunk_radius do
    for cy = -chunk_radius, chunk_radius do
      if not surface.is_chunk_generated({x = cx, y = cy}) then
        surface.request_to_generate_chunks({x = cx * 32, y = cy * 32}, 0)
      end
    end
  end
  pcall(function() surface.force_generate_chunk_requests() end)

  -- Чарт как радаром для всех сил
  for _, force in pairs(game.forces) do
    if force and force.valid then
      pcall(function()
        force.chart(surface, {{-MAP_LIMIT, -MAP_LIMIT}, {MAP_LIMIT, MAP_LIMIT}})
      end)
    end
  end
end

function on_chunk_generated(event)
  if event.surface.name ~= SURFACE_NAME then return end
  local surface = event.surface
  local area = event.area
  local tiles = {}
  local need = false

  -- безопасная проверка кастомного тайла
  local custom_tile_exists = false
  do
    local ok, t = pcall(function() return prototypes.tile["custom-se-empty-space-no-correct"] end)
    custom_tile_exists = ok and t ~= nil
  end

  for x = area.left_top.x, area.right_bottom.x - 1 do
    for y = area.left_top.y, area.right_bottom.y - 1 do
      if x < -MAP_LIMIT or x >= MAP_LIMIT or y < -MAP_LIMIT or y >= MAP_LIMIT then
        table.insert(tiles, {name = "out-of-map", position = {x, y}})
        need = true
      else
        local ct = surface.get_tile(x, y)
        if ct.valid and ct.name ~= "empty-space" then
          local tn = "empty-space"
          if custom_tile_exists then tn = "custom-se-empty-space-no-correct" end
          table.insert(tiles, {name = tn, position = {x, y}})
          need = true
        end
      end
    end
  end
  if need and #tiles > 0 then
    pcall(function() surface.set_tiles(tiles, false, false) end)
  end

  -- Чистим мусор: всё, кроме маркеров планет и персонажей игроков
  local ents = surface.find_entities_filtered({area = area})
  for _, e in ipairs(ents) do
    if e.valid and e.type ~= "character" then
      local n = e.name or ""
      if n ~= "custom-se-planet-marker" and not string.find(n, "^custom%-se%-marker%-") then
        pcall(function() e.destroy() end)
      end
    end
  end
  pcall(function() surface.destroy_decoratives({area = area}) end)
end
