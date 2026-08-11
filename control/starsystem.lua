-- control/starsystem.lua
-- Построение звёздной системы: орбиты, спрайты, подписи, маркеры, платформы.
-- Открытие планет по исследованию: тело и его орбита рисуются ТОЛЬКО после
-- исследования технологии planet-discovery-<name> (у кого-то из сил).
-- Чёрные "cover"-круги удалены полностью - они и давали огромные тёмные диски.

local GOLDEN_ANGLE = 2.3999632297286533

local STAR_KEYWORDS = {"star", "calidus", "kalidus", "sol", "sun"}

local function is_star_name(name)
  local l = string.lower(name or "")
  for _, kw in ipairs(STAR_KEYWORDS) do
    if string.find(l, kw, 1, true) then return true end
  end
  return false
end

local function get_proto(name)
  -- ВАЖНО (2.1): в runtime НЕТ prototypes.planet!
  -- Планеты доступны только через game.planets -> LuaPlanet.prototype
  local ok, p = pcall(function()
    if game.planets and game.planets[name] then
      return game.planets[name].prototype
    end
    return nil
  end)
  if ok and p then return p end
  -- Космические локации (край системы и т.п.)
  local ok2, p2 = pcall(function() return prototypes.space_location[name] end)
  if ok2 and p2 then return p2 end
  return nil
end

-- ВНИМАНИЕ: привязка видимости к технологиям УБРАНА по запросу.
-- Все планеты видны всегда. Технологии открытия используются только командой /starmap-open.

-- Карта открытия планет: собрана сканом data.raw.technology в data-final-fixes.lua
-- и передана в рантайм через mod-data "custom-se-starmap-discovery".
function get_discovery_data()
  local out = {map = {}, techs = {}}
  local ok, md = pcall(function() return prototypes.mod_data["custom-se-starmap-discovery"] end)
  if ok and md then
    local ok_d, d = pcall(function() return md.data end)
    if ok_d and type(d) == "table" then
      if type(d.map) == "table" then out.map = d.map end
      if type(d.techs) == "table" then out.techs = d.techs end
    end
  end
  return out
end

-- Имена всех небесных тел (без звёзд и скрытых)
local function collect_body_names()
  local names, seen = {}, {}

  -- 1) Планеты: ТОЛЬКО через game.planets (prototypes.planet в runtime не существует)
  local ok_p, err_p = pcall(function()
    for name, lua_planet in pairs(game.planets) do
      if not seen[name] and not is_star_name(name) then
        seen[name] = true
        table.insert(names, name)
      end
    end
  end)
  if not ok_p then log("[custom-se-starmap] ERROR iterating game.planets: " .. tostring(err_p)) end
  local planets_count = #names

  -- 2) Космические локации (solar-system-edge и подобные)
  local ok_l, err_l = pcall(function()
    for name, proto in pairs(prototypes.space_location) do
      if not seen[name] and not is_star_name(name) then
        local hidden = false
        pcall(function() hidden = proto.hidden == true end)
        if not hidden then
          seen[name] = true
          table.insert(names, name)
        end
      end
    end
  end)
  if not ok_l then log("[custom-se-starmap] ERROR iterating prototypes.space_location: " .. tostring(err_l)) end
  log("[custom-se-starmap] bodies: planets=" .. planets_count .. ", locations=" .. (#names - planets_count))

  table.sort(names)
  return names, seen
end

-- Орбиты PlanetsLib из mod-data (+ опциональный файл control/generated_orbits.lua)
local function get_orbits()
  local orbits = {}
  local ok, md = pcall(function() return prototypes.mod_data["custom-se-starmap-orbits"] end)
  if ok and md then
    local ok_d, d = pcall(function() return md.data end)
    if ok_d and type(d) == "table" then
      for k, v in pairs(d) do orbits[k] = v end
    end
  end
  local ok_f, file_orbits = pcall(require, "control.generated_orbits")
  if ok_f and type(file_orbits) == "table" then
    for k, v in pairs(file_orbits) do
      if not orbits[k] then orbits[k] = v end
    end
  end
  return orbits
end

-- Треугольник платформы: ТУПОЙ угол (широкое основание) к планете,
-- остриё смотрит ОТ планеты (наружу орбиты).
-- Формат vertices у draw_polygon (2.x): массив ScriptRenderVertexTarget {target = {x, y}}.
function platform_triangle_verts(center, ang, dist, len, halfw)
  local ux, uy = math.cos(ang), math.sin(ang)
  local vx, vy = -uy, ux
  -- основание ближе к планете, остриё дальше
  local bx = center.x + ux * (dist - len * 0.5)
  local by = center.y + uy * (dist - len * 0.5)
  local tx = center.x + ux * (dist + len * 0.5)
  local ty = center.y + uy * (dist + len * 0.5)
  return {
    {target = {x = bx + vx * halfw, y = by + vy * halfw}},
    {target = {x = bx - vx * halfw, y = by - vy * halfw}},
    {target = {x = tx, y = ty}},
  }
end

-- Локализованное имя небесного тела (подпись камеры платформы и т.п.)
function starmap_body_localised_name(name)
  local proto = get_proto(name)
  if proto then
    local ok, ln = pcall(function() return proto.localised_name end)
    if ok and ln then return ln end
  end
  return {"space-location-name." .. name}
end

local function destroy_star_system(surface)
  if storage.planets then
    for _, p in ipairs(storage.planets) do
      r_destroy(p.orbit_id)
      r_destroy(p.sprite_id)
      r_destroy(p.name_text_id)
      r_destroy(p.card_render_id)
      if p.platform_render_ids then
        for _, id in ipairs(p.platform_render_ids) do r_destroy(id) end
      end
      if p.platform_label_ids then
        for _, id in ipairs(p.platform_label_ids) do r_destroy(id) end
      end
    end
  end
  -- Маркеры удаляем массово по именам (unit_number у simple-entity нет)
  local marker_names = {"custom-se-planet-marker", "custom-se-platform-marker"}
  for _, p in ipairs(storage.planets or {}) do
    if p.marker_name then table.insert(marker_names, p.marker_name) end
  end
  pcall(function()
    for _, e in ipairs(surface.find_entities_filtered{name = marker_names}) do
      if e.valid then pcall(function() e.destroy() end) end
    end
  end)
  if storage.star_render_ids then
    for _, id in ipairs(storage.star_render_ids) do r_destroy(id) end
  end
  storage.star_render_ids = nil
end

local function draw_sun(surface)
  storage.star_render_ids = {}
  -- свечение
  local ok1, glow = pcall(function()
    return rendering.draw_circle{
      color = {r = 1, g = 0.8, b = 0.3, a = 0.35},
      radius = STAR_RADIUS,
      filled = true,
      target = {x = 0, y = 0},
      surface = surface
    }
  end)
  if ok1 and glow then
    table.insert(storage.star_render_ids, glow.id)
    r_move_back(glow.id)
  end
  -- ядро
  local ok2, core = pcall(function()
    return rendering.draw_circle{
      color = {r = 1, g = 0.93, b = 0.55, a = 1},
      radius = STAR_RADIUS * 0.75,
      filled = true,
      target = {x = 0, y = 0},
      surface = surface
    }
  end)
  if ok2 and core then table.insert(storage.star_render_ids, core.id) end
end

-- Кандидаты SpritePath для иконки тела.
-- ВАЖНО (2.1): SpritePath НЕ принимает "сырые" пути __mod__/graphics/....png!
-- Валидные формы: "type/name" (item/..., entity/..., space-location/...) или SpritePrototype.
-- Поэтому иконки берём через:
--   1) "space-location/<name>"  — иконка локации/планеты (нативно)
--   2) "planet/<name>"          — на случай отдельного типа
--   3) "entity/custom-se-marker-<name>" — иконка маркера, скопирована из прототипа в data-стадии
--   4) "item/satellite"         — запасной вариант
local function icon_candidates(name)
  return {
    {path = "space-location/" .. name, size = 64},
    {path = "planet/" .. name, size = 64},
    {path = "entity/custom-se-marker-" .. name, size = 64},
    {path = "entity/custom-se-planet-marker", size = 64},
    {path = "item/satellite", size = 64},
  }
end

local sprite_fail_log_count = 0

-- Спрайт планеты: иконка, ПОДОГНАННАЯ под масштаб планеты.
-- x_scale = (желаемый диаметр в тайлах * 32) / размер иконки в пикселях
local function draw_planet_sprite(surface, name, pos, icon_radius_tiles, angle)
  local errors = {}
  for _, cand in ipairs(icon_candidates(name)) do
    -- проверка валидности SpritePath без исключений
    local valid = true
    local ok_v, v = pcall(function() return helpers.is_valid_sprite_path(cand.path) end)
    if ok_v then valid = (v == true) end
    if valid then
      local px = cand.size or 64
      local scale = (icon_radius_tiles * 2 * 32) / px
      local ok, obj = pcall(function()
        return rendering.draw_sprite{
          sprite = cand.path,
          target = {x = pos.x, y = pos.y},
          surface = surface,
          x_scale = scale,
          y_scale = scale,
          orientation = (angle / (2 * math.pi)) % 1
        }
      end)
      if ok and obj then return obj.id end
      table.insert(errors, cand.path .. " => draw error: " .. tostring(obj))
    else
      table.insert(errors, cand.path .. " => invalid SpritePath")
    end
  end
  -- логируем первые неудачи, чтобы была диагностика
  if sprite_fail_log_count < 5 then
    sprite_fail_log_count = sprite_fail_log_count + 1
    log("[custom-se-starmap] sprite FAIL for '" .. name .. "': " .. table.concat(errors, " | "))
  end
  local ok, dot = pcall(function()
    return rendering.draw_circle{
      color = {r = 1, g = 1, b = 1, a = 0.9},
      radius = icon_radius_tiles,
      filled = true,
      target = {x = pos.x, y = pos.y},
      surface = surface
    }
  end)
  if ok and dot then return dot.id end
  return nil
end

-- Rich-тег иконки ресурса: item -> fluid -> entity, иначе — обычный текст.
-- Иначе на карточках для нефти/бримстоуна и т.п. лезет "неизвестный ключ":
-- [item=crude-oil] не существует, а [fluid=crude-oil] / [entity=...] — есть.
function resource_rich_tag(name)
  local ok_i, has_i = pcall(function() return prototypes.item[name] ~= nil end)
  if ok_i and has_i then return "[item=" .. name .. "]" end
  local ok_f, has_f = pcall(function() return prototypes.fluid[name] ~= nil end)
  if ok_f and has_f then return "[fluid=" .. name .. "]" end
  local ok_e, has_e = pcall(function() return prototypes.entity[name] ~= nil end)
  if ok_e and has_e then return "[entity=" .. name .. "]" end
  return name
end

-- Текст карточки характеристик (SHIFT+I)
local CARD_LABELS = {
  ["solar-power"] = "Солнце",
  ["pressure"] = "Давление",
  ["gravity"] = "Гравитация",
  ["magnetic-field"] = "Магн. поле",
  ["day-night-ratio"] = "День/ночь",
  ["temperature"] = "Температура",
}

function build_card_text(name)
  local proto = get_proto(name)
  if not proto then return name end
  local out = {}

  local ok, sp = pcall(function() return proto.surface_properties end)
  if ok and sp then
    local keys = {}
    for k, _ in pairs(sp) do
      if type(k) == "string" then table.insert(keys, k) end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = sp[k]
      if type(v) == "number" then
        local label = CARD_LABELS[k] or k:gsub("-", " ")
        local val
        if k == "pressure" then val = string.format("%.0f гПа", v)
        elseif k == "gravity" then val = string.format("%.1f м/с²", v)
        elseif k == "solar-power" then val = string.format("%.0f%%", v <= 5 and v * 100 or v)
        elseif k == "temperature" then val = string.format("%d K", math.floor(v))
        elseif math.abs(v) < 10 and v ~= math.floor(v) then val = string.format("%.2f", v)
        else val = tostring(v) end
        table.insert(out, label .. ": " .. val)
        if #out >= 8 then break end
      end
    end
  end

  local ok2, mgs = pcall(function() return proto.map_gen_settings end)
  if ok2 and mgs then
    -- ресурсы: из autoplace_controls + автоплейсменты сущностей (fluid/entity aware)
    local res_names, seen = {}, {}
    if mgs.autoplace_controls then
      for rname, _ in pairs(mgs.autoplace_controls) do
        if rname ~= "water" and not string.find(rname, "cliff") and rname ~= "starting_area" and not seen[rname] then
          seen[rname] = true
          table.insert(res_names, rname)
        end
      end
    end
    local ok3, ents = pcall(function()
      if mgs.autoplace_settings and mgs.autoplace_settings.entity then
        return mgs.autoplace_settings.entity.settings
      end
      return nil
    end)
    if ok3 and ents then
      for rname, _ in pairs(ents) do
        if not seen[rname] then
          seen[rname] = true
          table.insert(res_names, rname)
        end
      end
    end
    table.sort(res_names)
    local icons, n = {}, 0
    for _, rname in ipairs(res_names) do
      table.insert(icons, resource_rich_tag(rname))
      n = n + 1
      if n >= 14 then break end
    end
    if #icons > 0 then
      table.insert(out, table.concat(icons, " "))
    end
  end

  if #out == 0 then return name end
  return table.concat(out, "\n")
end

function rebuild_star_system()
  local surface = get_or_create_surface()
  if not surface or not surface.valid then return end

  destroy_star_system(surface)
  storage.planets = {}
  storage.planet_by_name = {}

  local orbits = get_orbits()
  local names, name_set = collect_body_names()
  sprite_fail_log_count = 0

  -- === Разделяем тела на звёздные и луны ===
  local star_bodies, moon_bodies = {}, {}
  for _, name in ipairs(names) do
    local proto = get_proto(name)
    if proto then
      local od = orbits[name]
      local parent_name, parent_type = nil, nil
      if od and od.parent and od.parent ~= name
         and not is_star_name(od.parent) and name_set[od.parent] then
        parent_name = od.parent
        parent_type = od.parent_type
      end

      local raw_od, raw_pd, dist = -1, -1, nil
      if od and od.distance then raw_od = od.distance end
      pcall(function() if proto.distance then raw_pd = proto.distance end end)
      if raw_od > 0 then
        dist = raw_od
      elseif raw_pd > 0 then
        dist = raw_pd
      end

      local orient = nil
      if od and od.orientation then orient = od.orientation end
      if not orient then pcall(function() orient = proto.orientation end) end

      local mag = 1
      pcall(function() if proto.magnitude and proto.magnitude > 0 then mag = proto.magnitude end end)

      local body = {
        name = name,
        prototype_name = name,
        parent_name = parent_name,
        parent_type = parent_type,
        raw_orbit_dist = raw_od,
        raw_proto_dist = raw_pd,
        distance = dist,      -- финализируется ниже, если nil
        magnitude = mag,
        orientation = orient, -- 0..1 или nil
        proto = nil,          -- прототипы в storage нельзя - не храним
        discovered = true,    -- видимость не зависит от исследований
      }

      if parent_name then
        table.insert(moon_bodies, body)
      else
        table.insert(star_bodies, body)
      end
    end
  end

  -- === Радиусы звёздных орбит (сортировка по дистанции + разрыв STAR_ORBIT_GAP) ===
  table.sort(star_bodies, function(a, b) return (a.distance or math.huge) < (b.distance or math.huge) end)
  local prev_r = STAR_RADIUS + STAR_ORBIT_GAP + 2
  for i, b in ipairs(star_bodies) do
    if not b.distance then b.distance = 10 + i * 10 end
    local r = (b.distance + STAR_DISTANCE_BONUS) * STAR_DISTANCE_SCALE
    r = math.max(r, MIN_ORBIT_RADIUS)
    r = math.max(r, prev_r + STAR_ORBIT_GAP)
    r = math.min(r, MAX_ORBIT_RADIUS)
    b.orbit_radius = r
    prev_r = r

    if b.orientation then
      b.angle = (b.orientation % 1) * 2 * math.pi
    else
      b.angle = i * GOLDEN_ANGLE
    end

    local size = PLANET_SIZE_BASE * b.magnitude + PLANET_SIZE_BONUS
    b.icon_radius = math.max(0.5, size)
    b.position = {x = math.cos(b.angle) * r, y = math.sin(b.angle) * r}

    table.insert(storage.planets, b)
    storage.planet_by_name[b.name] = b
  end

  -- === Радиусы лун (по каждому родителю отдельно) ===
  local by_parent = {}
  for _, m in ipairs(moon_bodies) do
    by_parent[m.parent_name] = by_parent[m.parent_name] or {}
    table.insert(by_parent[m.parent_name], m)
  end
  for parent_name, list in pairs(by_parent) do
    table.sort(list, function(a, b) return (a.distance or math.huge) < (b.distance or math.huge) end)
    local parent = storage.planet_by_name[parent_name]
    local parent_icon = (parent and parent.icon_radius) or 1.5
    local prev_r = nil
    local prev_icon = 0
    for i, m in ipairs(list) do
      if not m.distance then m.distance = 5 + i * 5 end

      -- Размер луны считаем ДО радиуса: «пол» орбиты зависит от иконок
      -- Множитель размера лун: меньше 1 — луны меньше планет
      local size = (PLANET_SIZE_BASE * m.magnitude + PLANET_SIZE_BONUS + SAT_SIZE_BONUS) * MOON_SIZE_SCALE
      m.icon_radius = math.max(0.4, size)

      if m.orientation then
        m.angle = (m.orientation % 1) * 2 * math.pi
      else
        m.angle = i * GOLDEN_ANGLE
      end

      -- Множитель орбит лун. Зазоры ("пол") тоже масштабируются множителем,
      -- иначе при малых радиусах множитель ВООБЩЕ не влиял на результат.
      local r = (m.distance + SAT_DISTANCE_BONUS) * SAT_DISTANCE_SCALE * MOON_ORBIT_SCALE
      local inner_gap = math.max(0.05, MOON_ORBIT_SCALE * 2)   -- 0.15 -> зазор 0.3 от края иконки
      local floor_r = math.max(SAT_MIN_RADIUS, parent_icon + m.icon_radius + inner_gap)
      if prev_r then
        local ring_gap = math.max(0.02, MOON_ORBIT_SCALE * 1.2) -- 0.15 -> 0.18 между кольцами лун
        floor_r = math.max(floor_r, prev_r + prev_icon + m.icon_radius + ring_gap)
      end
      r = math.max(r, floor_r)
      r = math.min(r, SAT_MAX_RADIUS)
      m.orbit_radius = r
      prev_r = r
      prev_icon = m.icon_radius

      local px, py = 0, 0
      if parent and parent.position then px, py = parent.position.x, parent.position.y end
      m.position = {
        x = px + math.cos(m.angle) * r,
        y = py + math.sin(m.angle) * r
      }

      table.insert(storage.planets, m)
      storage.planet_by_name[m.name] = m
    end
  end

  -- === Рендер: только открытые тела ===
  for _, b in ipairs(storage.planets) do
    if b.discovered then
      local proto = get_proto(b.prototype_name)
      local is_moon = b.parent_name ~= nil

      -- Орбита (серая у звёздных, голубая у лун)
      local orbit_target = {x = 0, y = 0}
      if is_moon and storage.planet_by_name[b.parent_name] then
        orbit_target = storage.planet_by_name[b.parent_name].position
      end
      local ok_o, orbit_obj = pcall(function()
        return rendering.draw_circle{
          color = is_moon and MOON_ORBIT_COLOR or ORBIT_COLOR,
          radius = b.orbit_radius,
          width = is_moon and MOON_ORBIT_WIDTH or ORBIT_WIDTH,
          filled = false,
          target = {x = orbit_target.x, y = orbit_target.y},
          surface = surface,
          draw_on_ground = true
        }
      end)
      if ok_o and orbit_obj then
        b.orbit_id = orbit_obj.id
        r_move_back(b.orbit_id)
      end

      -- Спрайт планеты (НИКАКИХ cover-кругов!) — не зависит от наличия прототипа
      b.sprite_id = draw_planet_sprite(surface, b.prototype_name, b.position, b.icon_radius, b.angle)

      -- Подпись (нужен прототип для localised_name)
      if proto then
        local ok_t, tobj = pcall(function()
          return rendering.draw_text{
            text = proto.localised_name or {"space-location-name." .. b.prototype_name},
            surface = surface,
            target = {x = b.position.x, y = b.position.y - (b.icon_radius + 1.2)},
            color = {r = 1, g = 1, b = 1, a = 0.95},
            scale = 0.8,
            alignment = "center"
          }
        end)
        if ok_t and tobj then b.name_text_id = tobj.id end
      end

      -- Маркер-сущность для наведения/клика.
      -- ВАЖНО: у simple-entity НЕТ unit_number, а LuaEntity нельзя хранить в storage.
      -- Запоминаем только ИМЯ маркера; саму сущность ищем по имени+позиции при движении.
      local marker_name = "custom-se-marker-" .. b.prototype_name
      local ok_mp, mp = pcall(function() return prototypes.entity[marker_name] end)
      if not (ok_mp and mp) then marker_name = "custom-se-planet-marker" end
      local ok_e, ent = pcall(function()
        return surface.create_entity{name = marker_name, position = {x = b.position.x, y = b.position.y}, force = "neutral"}
      end)
      if ok_e and ent and ent.valid then
        b.marker_name = marker_name
      end
    end
  end

  -- === Солнце ===
  draw_sun(surface)

  -- === Платформы на орбитах ===
  refresh_platform_marks()

  -- Восстановить карточки, если были включены
  if storage.info_visible then
    storage.info_visible = false
    if toggle_info_cards then toggle_info_cards(nil) end
  end

  local discovered_count = 0
  for _, b in ipairs(storage.planets) do if b.discovered then discovered_count = discovered_count + 1 end end
  log("[custom-se-starmap] rebuilt: " .. #storage.planets .. " bodies, " .. discovered_count .. " discovered"
    .. " | MOON_ORBIT_SCALE=" .. tostring(MOON_ORBIT_SCALE)
    .. " MOON_SIZE_SCALE=" .. tostring(MOON_SIZE_SCALE)
    .. " STAR_ORBIT_GAP=" .. tostring(STAR_ORBIT_GAP))
end

-- === Маркеры платформ вокруг планет (спрайт из ванильного листа, fallback — треугольник) ===
-- Распределение: платформы ЗАНИМАЮТ СЛОТЫ ПОСЛЕДОВАТЕЛЬНО (а не равномерно по кругу).
-- Порядок — по index платформы (~время создания): слот №0 строго сверху планеты,
-- новые платформы добавляются в хвост, стоящие на месте не перетасовываются.
-- Каждый маркер — кликабельная сущность: наведение показывает камеру платформы.
function refresh_platform_marks()
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid or not storage.planets then return end

  -- снести старые рендеры, подписи, слоты и маркер-сущности платформ
  for _, p in ipairs(storage.planets) do
    if p.platform_render_ids then
      for _, id in ipairs(p.platform_render_ids) do r_destroy(id) end
    end
    if p.platform_label_ids then
      for _, id in ipairs(p.platform_label_ids) do r_destroy(id) end
    end
    p.platform_render_ids = nil
    p.platform_label_ids = nil
    p.platform_angles = nil
    p.platform_slots = nil
    p.platform_sprite_mode = nil
  end
  pcall(function()
    for _, e in ipairs(surface.find_entities_filtered{name = "custom-se-platform-marker"}) do
      if e.valid then pcall(function() e.destroy() end) end
    end
  end)

  -- собрать платформы по локациям (по всем силам), со стабильным порядком
  local plats_by_loc = {}
  for _, force in pairs(game.forces) do
    if force and force.valid then
      local ok, plats = pcall(function() return force.platforms end)
      if ok and plats then
        for _, platform in pairs(plats) do
          local ok_l, loc = pcall(function()
            if not platform.valid then return nil end
            return platform.space_location
          end)
          if ok_l and loc and loc.name then
            local idx = 0
            pcall(function() idx = platform.index or 0 end)
            local ok_n, pname = pcall(function() return platform.name end)
            plats_by_loc[loc.name] = plats_by_loc[loc.name] or {}
            table.insert(plats_by_loc[loc.name], {
              force = force.name,
              index = idx,
              name = (ok_n and pname and pname ~= "") and pname or "platform"
            })
          end
        end
      end
    end
  end
  -- стабильный порядок слотов: сначала старые платформы (меньший index)
  for _, list in pairs(plats_by_loc) do
    table.sort(list, function(a, b)
      if a.index ~= b.index then return a.index < b.index end
      if a.force ~= b.force then return a.force < b.force end
      return (a.name or "") < (b.name or "")
    end)
  end

  -- ванильный спрайт платформы доступен?
  local sprite_ok = false
  do
    local ok, v = pcall(function() return helpers.is_valid_sprite_path("custom-se-starmap-platform-1") end)
    sprite_ok = ok and v == true
  end

  -- слоты: №0 сверху (PLATFORM_SLOT_START), далее по часовой с шагом
  -- PLATFORM_SLOT_ARC тайлов по дуге окружности радиуса dist
  local drawn, first_err = 0, nil
  for _, p in ipairs(storage.planets) do
    local list = plats_by_loc[p.prototype_name]
    if p.discovered and list and #list > 0 and p.position then
      p.platform_render_ids = {}
      p.platform_label_ids = {}
      p.platform_slots = {}
      p.platform_sprite_mode = sprite_ok
      local dist = (p.icon_radius or 1) + PLATFORM_GAP
      local step = PLATFORM_SLOT_ARC / math.max(dist, 0.5)
      for i, plat in ipairs(list) do
        local ang = PLATFORM_SLOT_START + (i - 1) * step
        local ux, uy = math.cos(ang), math.sin(ang)
        local cx = p.position.x + ux * dist
        local cy = p.position.y + uy * dist
        -- слот запоминаем (только storage-safe данные!) — нужен для камеры и клика
        p.platform_slots[i] = {force = plat.force, index = plat.index, name = plat.name, angle = ang}

        local ok, obj
        if sprite_ok then
          ok, obj = pcall(function()
            return rendering.draw_sprite{
              sprite = "custom-se-starmap-platform-" .. ((i - 1) % 3 + 1),
              target = {x = cx, y = cy},
              surface = surface,
              x_scale = (PLATFORM_SIZE * 32) / 54,
              y_scale = (PLATFORM_SIZE * 32) / 54,
              -- "тупым углом к планете": поворот = радиальный угол + смещение
              orientation = (ang / (2 * math.pi) + PLATFORM_SPRITE_ROTATION) % 1
            }
          end)
        else
          -- fallback: залитый треугольник тупой стороной к планете
          -- (draw_polygon = triangle strip, без filled!)
          local verts = platform_triangle_verts(p.position, ang, dist, PLATFORM_SIZE, PLATFORM_HALF_WIDTH)
          ok, obj = pcall(function()
            return rendering.draw_polygon{
              color = PLATFORM_COLOR,
              vertices = verts,
              surface = surface
            }
          end)
        end
        if ok and obj then
          table.insert(p.platform_render_ids, obj.id)
          r_bring_front(obj.id)
          drawn = drawn + 1
        elseif not first_err then
          first_err = tostring(obj)
        end

        -- подпись с названием платформы, повёрнутая по касательной к орбите
        local lx = p.position.x + ux * (dist + PLATFORM_LABEL_GAP)
        local ly = p.position.y + uy * (dist + PLATFORM_LABEL_GAP)
        local ok_t, tobj = pcall(function()
          return rendering.draw_text{
            text = plat.name,
            surface = surface,
            target = {x = lx, y = ly},
            color = {r = 0.85, g = 0.95, b = 1, a = 0.9},
            scale = 0.45,
            alignment = "center",
            orientation = ((ang / (2 * math.pi)) + 0.25) % 1 -- под углом орбиты
          }
        end)
        if ok_t and tobj then
          table.insert(p.platform_label_ids, tobj.id)
          r_bring_front(tobj.id)
        end

        -- кликабельная маркер-сущность для наведения (камера) и ПКМ
        pcall(function()
          surface.create_entity{
            name = "custom-se-platform-marker",
            position = {x = cx, y = cy},
            force = "neutral"
          }
        end)
      end
    end
  end

  local parked_total = 0
  for _, lst in pairs(plats_by_loc) do parked_total = parked_total + #lst end
  log("[custom-se-starmap] platforms: parked=" .. parked_total
    .. ", markers drawn=" .. drawn
    .. ", mode=" .. (sprite_ok and "vanilla-sprite" or "triangle-fallback")
    .. (first_err and (" | ПЕРВАЯ ОШИБКА: " .. first_err) or ""))
end
