-- control/events.lua
-- Регистрация всех событий, чтобы control.lua был почти пустым

script.on_init(function()
  storage.planets = {}
  storage.planet_by_name = {}
  storage.star_render_ids = {}
  storage.info_visible = false
  storage.player_prev = {}
  storage.player_states = {}
  get_or_create_surface()
  rebuild_star_system()
end)

script.on_configuration_changed(function()
  get_or_create_surface()
  rebuild_star_system()
end)

script.on_event(defines.events.on_surface_created, function(event)
  local s = game.surfaces[event.surface_index]
  if s and s.name == SURFACE_NAME then rebuild_star_system() end
end)

script.on_event(defines.events.on_chunk_generated, on_chunk_generated)

script.on_event(defines.events.on_player_changed_surface, function(e)
  local p = game.players[e.player_index]
  if p then update_player_view_settings(p) end
end)

script.on_event(defines.events.on_player_joined_game, function(e)
  local p = game.players[e.player_index]
  if p then update_player_view_settings(p) end
end)

script.on_event(defines.events.on_player_created, function(e)
  local p = game.players[e.player_index]
  if p then update_player_view_settings(p) end
end)

-- После перезахода в сейв пересобираем систему: константы/настройки могли
-- поменяться, а on_configuration_changed при обычной загрузке НЕ срабатывает,
-- и storage.planets хранит старые радиусы.
local rebuild_after_load = false
script.on_load(function()
  rebuild_after_load = true
end)

script.on_event(defines.events.on_tick, function(e)
  if rebuild_after_load then
    rebuild_after_load = false
    pcall(rebuild_star_system)
  end
  -- рендер двигаем КАЖДЫЙ тик — иначе планеты и орбиты лун идут рывками
  update_orbits()
  -- камера предпросмотра платформы и инфо-окно планеты при наведении
  -- (оба снимают player.selected -> зелёной selection-рамки нет)
  for _, p in pairs(game.players) do
    pcall(update_platform_camera, p)
    pcall(update_planet_info, p)
  end
  if e.tick % 30 == 0 then
    for _, p in pairs(game.players) do update_player_view_settings(p) end
  end
  -- всегда прогружать поверхность как радаром
  if e.tick % 180 == 0 then
    local surf = game.surfaces[SURFACE_NAME]
    if surf then pcall(function() chart_surface_as_radar(surf) end) end
  end
  -- периодически обновлять треугольники платформ (прилёт/улёт без события)
  if e.tick % 600 == 0 then
    pcall(refresh_platform_marks)
  end
end)

-- Привязка к исследованиям УБРАНА: видимость планет от них не зависит.
-- Технологии открытия можно принудительно исследовать командой /starmap-open.

-- Платформа сменила состояние (прилетела/улетела со стоянки)
pcall(function()
  script.on_event(defines.events.on_space_platform_changed_state, function(e)
    pcall(refresh_platform_marks)
  end)
end)

script.on_event("custom-se-open-starmap", function(e)
  local p = game.players[e.player_index]
  teleport_to_starmap(p, true)
end)

script.on_event("custom-se-toggle-info", function(e)
  local p = game.players[e.player_index]
  toggle_info_cards(p)
end)

script.on_event("custom-se-left-click", function(e)
  local p = game.players[e.player_index]
  if p and p.surface.name ~= SURFACE_NAME then return end
  local cp = e.cursor_position or (p and p.position)
  handle_planet_click(p, cp)
end)

script.on_event("custom-se-right-click", function(e)
  local p = game.players[e.player_index]
  if p and p.surface.name ~= SURFACE_NAME then return end
  local cp = e.cursor_position or (p and p.position)
  handle_planet_click(p, cp)
end)

commands.add_command("starmap", "Телепорт на SE-карту", function(e)
  local p = game.players[e.player_index]
  if p then teleport_to_starmap(p, false) end
end)

commands.add_command("starmap-rebuild", "Пересобрать систему", function(e)
  rebuild_star_system()
  local p = e.player_index and game.players[e.player_index] or nil
  if p then
    p.print("[custom-se-starmap] Пересобрано: " .. (#storage.planets) .. " тел")
  end
end)

-- Диагностика: что мод видит в runtime (писать и в чат, и в лог)
commands.add_command("starmap-debug", "Диагностика звездной карты", function(e)
  local p = e.player_index and game.players[e.player_index] or nil
  local function say(s)
    if p then p.print(s) end
    log(s)
  end

  local planets_n, planets_sample = 0, {}
  local ok_p, err_p = pcall(function()
    for name, _ in pairs(game.planets) do
      planets_n = planets_n + 1
      if #planets_sample < 10 then table.insert(planets_sample, name) end
    end
  end)
  say("[starmap-debug] game.planets: " .. planets_n .. " [" .. table.concat(planets_sample, ", ") .. "]"
      .. (ok_p and "" or (" ERROR: " .. tostring(err_p))))

  local locs_n, locs_sample = 0, {}
  local ok_l, err_l = pcall(function()
    for name, _ in pairs(prototypes.space_location) do
      locs_n = locs_n + 1
      if #locs_sample < 10 then table.insert(locs_sample, name) end
    end
  end)
  say("[starmap-debug] prototypes.space_location: " .. locs_n .. " [" .. table.concat(locs_sample, ", ") .. "]"
      .. (ok_l and "" or (" ERROR: " .. tostring(err_l))))

  say("[starmap-debug] storage.planets: " .. #(storage.planets or {})
      .. " | planet_by_name: " .. (function() local c = 0 for _ in pairs(storage.planet_by_name or {}) do c = c + 1 end return c end)())

  local dd = get_discovery_data()
  say("[starmap-debug] discovery techs: " .. #dd.techs)

  local ic_n = 0
  local ok_i = pcall(function()
    local d = prototypes.mod_data["custom-se-starmap-icons"].data
    if type(d) == "table" then for _ in pairs(d) do ic_n = ic_n + 1 end end
  end)
  say("[starmap-debug] icons mod-data: " .. ic_n .. (ok_i and "" or " ERROR reading mod-data"))

  local od_n = 0
  pcall(function()
    local d = prototypes.mod_data["custom-se-starmap-orbits"].data
    if type(d) == "table" then for _ in pairs(d) do od_n = od_n + 1 end end
  end)
  say("[starmap-debug] orbits mod-data: " .. od_n)

  local surf = game.surfaces[SURFACE_NAME]
  say("[starmap-debug] starmap surface: " .. (surf and "exists" or "MISSING"))

  -- Проверка, какие формы SpritePath валидны на этой сборке
  local test_name = planets_sample[1] or "nauvis"
  local forms = {
    "space-location/" .. test_name,
    "planet/" .. test_name,
    "entity/custom-se-marker-" .. test_name,
    "entity/custom-se-planet-marker",
    "item/satellite",
    "__space-age__/graphics/icons/starmap-planet-" .. test_name .. ".png",
  }
  local parts = {}
  for _, f in ipairs(forms) do
    local ok, v = pcall(function() return helpers.is_valid_sprite_path(f) end)
    table.insert(parts, f .. "=" .. (ok and tostring(v) or ("ERR:" .. tostring(v))))
  end
  say("[starmap-debug] sprite paths: " .. table.concat(parts, " ; "))

  -- Платформы: сколько стоит на каких локациях (по всем силам)
  local plat_counts, plat_total = {}, 0
  for _, force in pairs(game.forces) do
    if force.valid then
      local ok, plats = pcall(function() return force.platforms end)
      if ok and plats then
        for _, platform in pairs(plats) do
          local ok2, loc = pcall(function()
            if not platform.valid then return nil end
            return platform.space_location
          end)
          if ok2 and loc and loc.name then
            plat_counts[loc.name] = (plat_counts[loc.name] or 0) + 1
            plat_total = plat_total + 1
          end
        end
      end
    end
  end
  local plat_parts = {}
  for loc_name, c in pairs(plat_counts) do table.insert(plat_parts, loc_name .. "=" .. c) end
  say("[starmap-debug] platforms parked: total=" .. plat_total .. " {" .. table.concat(plat_parts, ", ") .. "}")
  local tri = 0
  for _, pl in ipairs(storage.planets or {}) do
    if pl.platform_render_ids then tri = tri + #pl.platform_render_ids end
  end
  say("[starmap-debug] platform triangles drawn: " .. tri)
end)

commands.add_command("starmap-back", "Вернуться", function(e)
  local p = game.players[e.player_index]
  if p and storage.player_prev and storage.player_prev[p.index] then
    teleport_to_starmap(p, true)
  end
end)

-- Открытие планет: /starmap-open — все планеты; /starmap-open <имя> — одну.
-- Технологии найдены сканом data.raw в data-final-fixes.lua (mod-data карта).
commands.add_command("starmap-open", "Открыть планеты: /starmap-open — все; /starmap-open <имя> — одну", function(e)
  local player = e.player_index and game.players[e.player_index] or nil
  local force = player and player.force or game.forces["player"]
  if not force then return end

  local data = get_discovery_data()
  local researched_count = 0

  local function research_tech(tech_name)
    local ok, done = pcall(function()
      local t = force.technologies[tech_name]
      if t and t.valid and not t.researched then
        t.researched = true
        return true
      end
      return false
    end)
    if ok and done then researched_count = researched_count + 1 end
    return ok and done
  end

  local param = e.parameter
  if param then
    param = param:gsub("^%s+", ""):gsub("%s+$", "")
    if param == "" then param = nil end
  end

  if param then
    local tech_name = data.map[param] or param
    local ok_flag = research_tech(tech_name)
    if player then
      if ok_flag then
        player.print("[custom-se-starmap] Открыто: " .. param .. " (технология " .. tech_name .. ")")
      else
        player.print("[custom-se-starmap] Не удалось открыть «" .. param .. "» — технология «" .. tech_name .. "» не найдена или уже исследована")
      end
    end
  else
    for _, tech_name in ipairs(data.techs) do
      research_tech(tech_name)
    end
    if player then
      player.print("[custom-se-starmap] Открыты все планеты. Технологий в карте: "
        .. #data.techs .. ", новых исследовано: " .. researched_count)
    end
    log("[custom-se-starmap] /starmap-open: force=" .. force.name .. ", techs=" .. #data.techs .. ", new=" .. researched_count)
  end
end)

pcall(function()
  script.on_event(defines.events.on_player_controller_changed, function(e)
    local p = game.players[e.player_index]
    if p then update_player_view_settings(p) end
  end)
end)
