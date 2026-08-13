-- control/events.lua
-- Регистрация событий мода.

script.on_init(function()
  storage.planets = {}
  storage.planet_by_name = {}
  storage.star_render_ids = {}
  storage.info_visible = false
  storage.player_prev = {}
  storage.player_states = {}
  -- Переименование мода: storage старого имени недоступно, а объекты рендера
  -- на поверхности остаются сиротами (id хранились в storage). Поверхность
  -- перед построением очищается от рендеров целиком (чужих объектов на ней
  -- нет; маркер-сущности убирает destroy_star_system внутри rebuild).
  local surf = get_or_create_surface()
  if surf and surf.valid then
    pcall(function() rendering.clear(surf) end)
  end
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

-- on_configuration_changed на обычной загрузке сейва не вызывается;
-- пересборка откладывается на первый тик (в on_load storage недоступен).
local rebuild_after_load = false
script.on_load(function()
  rebuild_after_load = true
end)

script.on_event(defines.events.on_tick, function(e)
  if rebuild_after_load then
    rebuild_after_load = false
    pcall(rebuild_star_system)
  end
  -- орбиты пересчитываются каждый тик
  update_orbits()
  -- маршруты и маркеры летящих платформ (control/routes.lua)
  update_routes_safe()
  -- hover-окна (снимают player.selected -> зелёной рамки нет)
  -- и окна закреплённых платформ
  for _, p in pairs(game.players) do
    pcall(update_platform_camera, p)
    pcall(update_planet_info, p)
    pcall(update_pinned_follows, p)
  end
  if e.tick % 30 == 0 then
    for _, p in pairs(game.players) do update_player_view_settings(p) end
  end
  -- поддержание чарта поверхности
  if e.tick % 180 == 0 then
    local surf = game.surfaces[SURFACE_NAME]
    if surf then pcall(function() chart_surface_as_radar(surf) end) end
  end
  -- сверка маркеров платформ (прилёт/улёт без события)
  if e.tick % 600 == 0 then
    pcall(refresh_platform_marks)
  end
end)

-- Видимость планет от исследований не зависит. /starmap-open исследует
-- технологии открытия принудительно.

pcall(function()
  script.on_event(defines.events.on_space_platform_changed_state, function(e)
    pcall(refresh_platform_marks)
  end)
end)

-- Накопленный урон платформ (storage.platform_damage, по индексу платформы):
-- суммарного агрегата в API нет; урон по тайлам основания событий не даётся.
-- Окно статистики (gui.lua) показывает живой дефицит прочности сущностей +
-- урон тайлов (platform.damaged_tiles); этот счётчик — суммарная история с
-- момента введения учёта, из окна не читается. Старые ключи не чистятся
-- (индекс платформы уникален).
script.on_event(defines.events.on_entity_damaged, function(e)
  local ent = e.entity
  if not (ent and ent.valid) then return end
  local ok_p, platform = pcall(function() return ent.surface.platform end)
  if not (ok_p and platform) then return end
  local ok_v, valid = pcall(function() return platform.valid end)
  if not (ok_v and valid) then return end
  storage.platform_damage = storage.platform_damage or {}
  local ok_i, idx = pcall(function() return platform.index end)
  if not (ok_i and type(idx) == "number") then return end
  storage.platform_damage[idx] = (storage.platform_damage[idx] or 0) + (e.final_damage_amount or 0)
end)

-- Граф связей перестраивается при открытии тел (исследование
-- unlock-space-location) и при смене живой настройки фильтра
-- исследованности (routes.lua, conn_discovered_only).
pcall(function()
  script.on_event(defines.events.on_research_finished, function(e)
    local effs = nil
    pcall(function() effs = e.research.prototype.effects end)
    for _, eff in ipairs(effs or {}) do
      if eff.type == "unlock-space-location" then
        -- граф связей + перерисовка иконок тел (плейсхолдер -> иконка)
        pcall(force_routes_rebuild)
        pcall(rebuild_star_system)
        break
      end
    end
  end)
end)
pcall(function()
  script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
    if e and e.setting == "space-map-rework-conn-discovered-only" then
      pcall(force_routes_rebuild)
    end
  end)
end)

-- on_selected_entity_changed: источник hover-данных.
--  1) запись пробника (имя+позиция+тик) в storage.hover_probe;
--  2) немедленное снятие выделения (selection-рамка не рисуется).
-- clear_selected_entity() рекурсивно вызывает это же событие с selected=nil —
-- пробник при nil НЕ стирается (иначе сгорает в тот же тик); его TTL
-- отслеживает gui.lua по HOVER_PROBE_TTL. Движок перевыделяет сущность под
-- курсором каждый тик: курсор на маркере -> пробник обновляется.
pcall(function()
  script.on_event(defines.events.on_selected_entity_changed, function(e)
    local p = game.players[e.player_index]
    if not (p and p.valid) then return end
    storage.hover_probe = storage.hover_probe or {}
    if not (p.surface and p.surface.name == SURFACE_NAME) then
      storage.hover_probe[p.index] = nil
      return
    end
    pcall(function()
      local s = p.selected
      if s and s.valid and starmap_is_marker_name(s.name) then
        storage.hover_probe[p.index] = {name = s.name, x = s.position.x, y = s.position.y, tick = game.tick}
        p.clear_selected_entity()
      end
      -- selected == nil (реентерабельный вызов или уход курсора): не трогаем.
    end)
  end)
end)

script.on_event("space-map-rework-open-starmap", function(e)
  local p = game.players[e.player_index]
  teleport_to_starmap(p, true)
end)

script.on_event("space-map-rework-toggle-info", function(e)
  local p = game.players[e.player_index]
  toggle_info_cards(p)
end)

-- SHIFT+P: закрепить/открепить наведённую платформу (паркованную или летящую)
script.on_event("space-map-rework-pin-platform", function(e)
  local p = game.players[e.player_index]
  if not (p and p.valid) then return end
  local hit = starmap_hovered_platform(p)
  if hit then
    toggle_pin_platform(p, hit)
  elseif p.surface and p.surface.name == SURFACE_NAME then
    p.print("[space-map-rework] Наведите курсор на маркер платформы, чтобы закрепить её")
  end
end)

-- кнопка X следящего окна закрепа -> открепить
script.on_event(defines.events.on_gui_click, function(e)
  local el = e.element
  if not (el and el.valid) then return end
  if el.name == "space-map-rework-pin-remove" then
    local p = game.players[e.player_index]
    local tags = el.tags or {}
    if p and p.valid and tags.pin_i then
      local list = storage.pinned_platforms and storage.pinned_platforms[p.index]
      if list and list[tags.pin_i] then
        local nm = list[tags.pin_i].name
        table.remove(list, tags.pin_i)
        p.print("[space-map-rework] Платформа «" .. (nm or "?") .. "» ОТКРЕПЛЕНА")
        pcall(destroy_pinned_follows, p)
      end
    end
  end
end)

script.on_event("space-map-rework-left-click", function(e)
  local p = game.players[e.player_index]
  if p and p.surface.name ~= SURFACE_NAME then return end
  local cp = e.cursor_position or (p and p.position)
  handle_planet_click(p, cp)
end)

script.on_event("space-map-rework-right-click", function(e)
  local p = game.players[e.player_index]
  if p and p.surface.name ~= SURFACE_NAME then return end
  local cp = e.cursor_position or (p and p.position)
  handle_planet_click(p, cp)
end)

reg_starmap_cmd({"starmap", "starmap-test"}, "Телепорт на звёздную карту", function(e)
  local p = game.players[e.player_index]
  if p then teleport_to_starmap(p, false) end
end)

reg_starmap_cmd({"starmap-rebuild", "starmap-test-rebuild"}, "Пересобрать систему", function(e)
  rebuild_star_system()
  -- граф маршрутов — принудительно: состав тел мог не измениться,
  -- а правила/эксклюзивные связи/прототипы — да (после обновления мода)
  if force_routes_rebuild then pcall(force_routes_rebuild) end
  local p = e.player_index and game.players[e.player_index] or nil
  if p then
    p.print("[space-map-rework] Пересобрано: " .. (#storage.planets) .. " тел")
  end
end)

reg_starmap_cmd({"starmap-debug", "starmap-test-debug"}, "Диагностика звездной карты", function(e)
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
    local d = prototypes.mod_data["space-map-rework-icons"].data
    if type(d) == "table" then for _ in pairs(d) do ic_n = ic_n + 1 end end
  end)
  say("[starmap-debug] icons mod-data: " .. ic_n .. (ok_i and "" or " ERROR reading mod-data"))

  local od_n = 0
  pcall(function()
    local d = prototypes.mod_data["space-map-rework-orbits"].data
    if type(d) == "table" then for _ in pairs(d) do od_n = od_n + 1 end end
  end)
  say("[starmap-debug] orbits mod-data: " .. od_n)

  local surf = game.surfaces[SURFACE_NAME]
  say("[starmap-debug] starmap surface: " .. (surf and "exists" or "MISSING"))

  -- валидация форм SpritePath на текущей сборке
  local test_name = planets_sample[1] or "nauvis"
  local forms = {
    "space-location/" .. test_name,
    "planet/" .. test_name,
    "entity/space-map-rework-marker-" .. test_name,
    "entity/space-map-rework-planet-marker",
    "item/satellite",
    "__space-age__/graphics/icons/starmap-planet-" .. test_name .. ".png",
  }
  local parts = {}
  for _, f in ipairs(forms) do
    local ok, v = pcall(function() return helpers.is_valid_sprite_path(f) end)
    table.insert(parts, f .. "=" .. (ok and tostring(v) or ("ERR:" .. tostring(v))))
  end
  say("[starmap-debug] sprite paths: " .. table.concat(parts, " ; "))

  -- припаркованные платформы по локациям (все силы)
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

reg_starmap_cmd({"starmap-back", "starmap-test-back"}, "Вернуться", function(e)
  local p = game.players[e.player_index]
  if p and storage.player_prev and storage.player_prev[p.index] then
    teleport_to_starmap(p, true)
  end
end)

-- /starmap-open — все планеты; /starmap-open <имя> — одну. Карта
-- планета->технология собрана в data-final-fixes.lua (mod-data).
reg_starmap_cmd({"starmap-open", "starmap-test-open"}, "Открыть планеты: /starmap-open — все; /starmap-open <имя> — одну", function(e)
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
        player.print("[space-map-rework] Открыто: " .. param .. " (технология " .. tech_name .. ")")
      else
        player.print("[space-map-rework] Не удалось открыть «" .. param .. "» — технология «" .. tech_name .. "» не найдена или уже исследована")
      end
    end
  else
    for _, tech_name in ipairs(data.techs) do
      research_tech(tech_name)
    end
    if player then
      player.print("[space-map-rework] Открыты все планеты. Технологий в карте: "
        .. #data.techs .. ", новых исследовано: " .. researched_count)
    end
    log("[space-map-rework] /starmap-open: force=" .. force.name .. ", techs=" .. #data.techs .. ", new=" .. researched_count)
  end
end)

pcall(function()
  script.on_event(defines.events.on_player_controller_changed, function(e)
    local p = game.players[e.player_index]
    if p then update_player_view_settings(p) end
  end)
end)
