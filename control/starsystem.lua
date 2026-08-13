-- control/starsystem.lua
-- Построение звёздной системы: орбиты, спрайты, подписи, маркеры, платформы.
-- Все тела видимы всегда (привязки к исследованиям нет).

local GOLDEN_ANGLE = 2.3999632297286533

local STAR_KEYWORDS = {"star", "calidus", "kalidus", "sol", "sun"}

-- Раскладка орбитальных радиусов: сохраняет пропорции data-дистанций,
-- гарантирует минимальный зазор между соседями и потолок max_r.
-- ЗЕРКАЛО: data-final-fixes.lua (раскладка коннекшенов) — держать синхронно.
local function spread_radii(entries, start_min, max_r, gap_fn)
  local n = #entries
  if n == 0 then return end
  -- масштаб: каждая пара с разной data-дистанцией разъезжается >= gap
  local s = 0
  for i = 2, n do
    local d = entries[i].raw - entries[i - 1].raw
    if d > 1e-9 then s = math.max(s, gap_fn(i) / d) end
  end
  if s < 1 then s = 1 end  -- data-пропорции не сжимаются
  local spread = entries[n].raw - entries[1].raw
  -- первая орбита = raw (или start_min); масштабируется только разброс от неё
  local first = math.max(entries[1].raw, start_min)
  if spread > 1e-9 then
    local s_cap = (max_r - first) / spread
    if s_cap < s then
      if s_cap > 1e-9 then s = s_cap end
      if first + spread * s > max_r then
        first = math.max(start_min, max_r - spread * s)
      end
    end
  end
  for i = 1, n do
    entries[i].r = first + (entries[i].raw - entries[1].raw) * s
  end
  -- кумулятивный зазор + потолок max_r
  for i = 2, n do
    local need = entries[i - 1].r + gap_fn(i)
    if entries[i].r < need then entries[i].r = need end
  end
  for i = 1, n do
    if entries[i].r > max_r then entries[i].r = max_r end
  end
end

local function is_star_name(name)
  local l = string.lower(name or "")
  for _, kw in ipairs(STAR_KEYWORDS) do
    if string.find(l, "(^|[^%a])" .. kw .. "($|[^%a])") then return true end
  end
  return false
end

local function get_proto(name)
  -- API 2.1: prototypes.planet в runtime отсутствует;
  -- планеты — через game.planets[name].prototype.
  local ok, p = pcall(function()
    if game.planets and game.planets[name] then
      return game.planets[name].prototype
    end
    return nil
  end)
  if ok and p then return p end
  local ok2, p2 = pcall(function() return prototypes.space_location[name] end)
  if ok2 and p2 then return p2 end
  return nil
end

-- Привязка видимости к технологиям отсутствует. Карта открытия
-- (планета -> технология) собрана сканом data.raw.technology в
-- data-final-fixes.lua, передана через mod-data "space-map-rework-discovery";
-- используется командой /starmap-open.
function get_discovery_data()
  local out = {map = {}, techs = {}}
  local ok, md = pcall(function() return prototypes.mod_data["space-map-rework-discovery"] end)
  if ok and md then
    local ok_d, d = pcall(function() return md.data end)
    if ok_d and type(d) == "table" then
      if type(d.map) == "table" then out.map = d.map end
      if type(d.techs) == "table" then out.techs = d.techs end
    end
  end
  return out
end

-- Имена всех небесных тел (без звёзд и скрытых локаций)
local function collect_body_names()
  local names, seen = {}, {}

  local ok_p, err_p = pcall(function()
    for name, lua_planet in pairs(game.planets) do
      if not seen[name] and not is_star_name(name) then
        seen[name] = true
        table.insert(names, name)
      end
    end
  end)
  if not ok_p then log("[space-map-rework] ERROR iterating game.planets: " .. tostring(err_p)) end
  local planets_count = #names

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
  if not ok_l then log("[space-map-rework] ERROR iterating prototypes.space_location: " .. tostring(err_l)) end
  log("[space-map-rework] bodies: planets=" .. planets_count .. ", locations=" .. (#names - planets_count))

  table.sort(names)
  return names, seen
end

-- Орбиты: mod-data "space-map-rework-orbits" + опциональный control/generated_orbits.lua.
local function get_orbits()
  local orbits = {}
  local ok, md = pcall(function() return prototypes.mod_data["space-map-rework-orbits"] end)
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

-- Треугольник платформы (fallback без ванильного спрайта): основание — к
-- планете, остриё — наружу. Формат вершин draw_polygon (2.1): MapPosition
-- {x, y}; формат {target={...}} движком не принимается.
function platform_triangle_verts(center, ang, dist, len, halfw)
  local ux, uy = math.cos(ang), math.sin(ang)
  local vx, vy = -uy, ux
  local bx = center.x + ux * (dist - len * 0.5)
  local by = center.y + uy * (dist - len * 0.5)
  local tx = center.x + ux * (dist + len * 0.5)
  local ty = center.y + uy * (dist + len * 0.5)
  return {
    {x = bx + vx * halfw, y = by + vy * halfw},
    {x = bx - vx * halfw, y = by - vy * halfw},
    {x = tx, y = ty},
  }
end

-- Локализованное имя тела (заголовки окон и т.п.)
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
      r_destroy(p.ring_id)
      r_destroy(p.card_render_id)
      if p.platform_render_ids then
        for _, id in ipairs(p.platform_render_ids) do r_destroy(id) end
      end
      if p.platform_label_ids then
        for _, id in ipairs(p.platform_label_ids) do r_destroy(id) end
      end
    end
  end
  -- массовое удаление маркеров по именам (unit_number у simple-entity нет)
  local marker_names = {"space-map-rework-planet-marker", "space-map-rework-platform-marker"}
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

-- Кандидаты SpritePath иконки тела. В 2.1 сырые пути __mod__/....png не
-- являются SpritePath; валидны "type/name" и SpritePrototype.
local function icon_candidates(name)
  return {
    {path = "space-location/" .. name, size = 64},
    {path = "planet/" .. name, size = 64},
    {path = "entity/space-map-rework-marker-" .. name, size = 64},
    {path = "entity/space-map-rework-planet-marker", size = 64},
    {path = "item/satellite", size = 64},
  }
end

-- Плейсхолдер неисследованного тела: ванильная not-available (32x32, спрайт
-- с data-стадии); при недоступном спрайте — тёмный круг. Размер — доля
-- LOCKED_ICON_SCALE (constants.lua) от диаметра тела.
local function draw_locked_sprite(surface, pos, icon_radius_tiles)
  local k = LOCKED_ICON_SCALE or 0.5
  local scale = ((icon_radius_tiles * 2 * 32) / 32) * k
  local ok, obj = pcall(function()
    return rendering.draw_sprite{
      sprite = "space-map-rework-body-undiscovered",
      target = {x = pos.x, y = pos.y},
      surface = surface,
      x_scale = scale,
      y_scale = scale
    }
  end)
  if ok and obj then return obj.id end
  local ok2, dot = pcall(function()
    return rendering.draw_circle{
      color = {r = 0.25, g = 0.25, b = 0.25, a = 0.9},
      radius = icon_radius_tiles * k,
      filled = true,
      target = {x = pos.x, y = pos.y},
      surface = surface
    }
  end)
  if ok2 and dot then return dot.id end
  return nil
end

-- Кольцо вокруг исследованного тела (обводка; цвета/масштаб — PLANET_RING_*).
local function draw_body_ring(surface, body)
  local ok, obj = pcall(function()
    return rendering.draw_circle{
      color = PLANET_RING_COLOR,
      radius = ((body.icon_radius or 1) + (PLANET_RING_GAP or 0.12))
        * (PLANET_RING_SCALE or 1),
      width = PLANET_RING_WIDTH or 2,
      filled = false,
      target = {x = body.position.x, y = body.position.y},
      surface = surface
    }
  end)
  if ok and obj then return obj.id end
  return nil
end

local function set_ring_color(body_name, color)
  local b = storage.planets and storage.planet_by_name
    and storage.planet_by_name[body_name] or nil
  if not (b and b.ring_id) then return end
  local o = r_obj(b.ring_id)
  if o then pcall(function() o.color = color end) end
end

-- Hover-подсветка кольца: жёлтое у наведённого тела, белое у остальных.
-- Вызывается каждый тик из update_planet_info (gui.lua) с тем же body, что
-- даёт инфо-окно; состояние — по игрокам (жёлтое, пока наведён хоть один
-- игрок). После rebuild сбрасывается storage.body_ring_hover.
function starmap_update_hover_ring(player, body)
  storage.body_ring_hover = storage.body_ring_hover or {}
  local name = body and body.prototype_name or nil
  local prev = storage.body_ring_hover[player.index]
  if prev == name then return end
  storage.body_ring_hover[player.index] = name
  if prev then
    local still = false
    for _, n in pairs(storage.body_ring_hover) do
      if n == prev then still = true break end
    end
    if not still then set_ring_color(prev, PLANET_RING_COLOR) end
  end
  if name then set_ring_color(name, PLANET_RING_HOVER_COLOR) end
end

local sprite_fail_log_count = 0

-- Спрайт планеты: x_scale = (диаметр в тайлах * 32) / размер иконки, px.
local function draw_planet_sprite(surface, name, pos, icon_radius_tiles, angle)
  local errors = {}
  for _, cand in ipairs(icon_candidates(name)) do
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
  if sprite_fail_log_count < 5 then
    sprite_fail_log_count = sprite_fail_log_count + 1
    log("[space-map-rework] sprite FAIL for '" .. name .. "': " .. table.concat(errors, " | "))
  end
  -- fallback: белый круг
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

-- Rich-тег ресурса: item -> fluid -> entity; иначе — текстовое имя
-- ([item=crude-oil] не существует, [fluid=crude-oil] — существует).
function resource_rich_tag(name)
  local ok_i, has_i = pcall(function() return prototypes.item[name] ~= nil end)
  if ok_i and has_i then return "[item=" .. name .. "]" end
  local ok_f, has_f = pcall(function() return prototypes.fluid[name] ~= nil end)
  if ok_f and has_f then return "[fluid=" .. name .. "]" end
  local ok_e, has_e = pcall(function() return prototypes.entity[name] ~= nil end)
  if ok_e and has_e then return "[entity=" .. name .. "]" end
  return name
end

-- Текст карточки характеристик (SHIFT+I): все surface-property прототипы
-- (значение планеты, иначе default_value; включая кастомные из других модов)
-- + иконки содержимого. Возвращает LocalisedString (имена параметров —
-- вложенные таблицы из прототипов).

-- ЗЕРКАЛО форматирования значений surface-property: data-final-fixes.lua
-- (format_prop_value, data-стадия). Держать синхронно.
local CARD_MAX_LINES = 32
local CARD_MAX_ICONS = 24

-- как в data-final-fixes.lua: свойство выводится, если задано планетой,
-- либо входит в ванильную базовую пятёрку.
-- ЗЕРКАЛО: data-final-fixes.lua (CORE_SURFACE_PROPS) — держать синхронно.
local CORE_SURFACE_PROPS = {
  ["day-night-cycle"] = true,
  gravity = true,
  ["magnetic-field"] = true,
  pressure = true,
  ["solar-power"] = true,
}

local function format_surf_prop_value(key, value, is_time, unit_key)
  if type(value) ~= "number" then return tostring(value) end
  local lower = string.lower(key)
  if is_time or lower == "day-night-cycle" then return string.format("%d min", math.floor(value / 3600 + 0.5)) end
  -- разряды в длинных числах: 1 734 963 809
  local function group_digits(s)
    local sign = ""
    if s:sub(1, 1) == "-" then sign = "-"; s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    if s:sub(1, 1) == " " then s = s:sub(2) end
    return sign .. s
  end
  local function numstr(v)
    if v == 0 then return "0" end
    local av = math.abs(v)
    if v == math.floor(v) and av < 1e15 then
      if av >= 10000 then return group_digits(tostring(math.floor(v))) end
      return tostring(math.floor(v))
    end
    if av < 0.01 then return string.format("%.4f", v) end
    if av < 10 then return string.format("%.2f", v) end
    if av < 1000 then return string.format("%.1f", v) end
    return group_digits(string.format("%.0f", v))
  end
  -- ванильный юнит-ключ: шаблон получает значение как __1__
  if unit_key and unit_key ~= "" then
    return {"?", {unit_key, numstr(value)}, numstr(value)}
  end
  if lower == "solar-power" or string.find(lower, "magnetic") then
    if value <= 5 then return string.format("%.0f %%", value * 100) end
    return string.format("%.0f %%", value)
  end
  if lower == "pressure" then return string.format("%.0f hPa", value) end
  if lower == "gravity" then return string.format("%.2f m/s²", value) end
  if lower == "day-night-ratio" then return string.format("%d min", math.floor(value * 6 + 0.5)) end
  if lower == "temperature" then return string.format("%d K", math.floor(value)) end
  if string.find(lower, "radiation") then return string.format("%d Bq", value) end
  if string.find(lower, "gas") then return string.format("%d %%", value * 100) end
  if string.find(lower, "drone") or string.find(lower, "robot") then return "×" .. value end
  if string.find(lower, "crystall") or string.find(lower, "dust") or string.find(lower, "pollen") then return string.format("%d %%", value) end
  if string.find(lower, "wind") then return string.format("%d km/h", value) end
  if string.find(lower, "asteroid") then return string.format("%d ppb", value) end
  if string.find(lower, "rocket") then return "×" .. value end
  if string.find(lower, "evolution") then return string.format("%.4f", value) end
  return numstr(value)
end

-- Упаковка строк в LocalisedString: вложенные чанки (лимит 20 параметров
-- на уровень). Каждая строка — LocalisedString или строка.
local function card_assemble(lines)
  local chunks, cur = {}, {""}
  for _, ln in ipairs(lines) do
    cur[#cur + 1] = ln
    cur[#cur + 1] = "\n"
    if (#cur - 1) >= 16 then
      chunks[#chunks + 1] = cur
      cur = {""}
    end
  end
  if #cur > 1 then chunks[#chunks + 1] = cur end
  if #chunks == 0 then return "" end
  local parts = {""}
  for _, c in ipairs(chunks) do parts[#parts + 1] = c end
  return parts
end

function build_card_text(name)
  local proto = get_proto(name)
  if not proto then return name end
  local lines = {}

  -- параметры поверхности: все surface-property прототипы с дефолтами
  local ok_sp, sp = pcall(function() return proto.surface_properties end)
  if not (ok_sp and sp) then sp = nil end
  local ok_props, props = pcall(function() return prototypes.surface_property end)
  if ok_props and props then
    local list = {}
    for pname, pproto in pairs(props) do list[#list + 1] = {name = pname, proto = pproto} end
    table.sort(list, function(a, b)
      local oa, ob = "", ""
      pcall(function() oa = a.proto.order or "" end)
      pcall(function() ob = b.proto.order or "" end)
      if oa ~= ob then return oa < ob end
      return a.name < b.name
    end)
    for _, e in ipairs(list) do
      if #lines >= CARD_MAX_LINES then break end
      local v = nil
      if sp and sp[e.name] ~= nil then
        v = sp[e.name]
      elseif CORE_SURFACE_PROPS[e.name] then
        local ok_d, dv = pcall(function() return e.proto.default_value end)
        if ok_d then v = dv end
      end
      if v ~= nil then
        -- пустой localised_name ("" / {""}) — как отсутствующий
        local label = nil
        local ok_l, ln = pcall(function() return e.proto.localised_name end)
        if ok_l and ln then
          local empty = (type(ln) == "string" and ln == "")
            or (type(ln) == "table" and (ln[1] == nil or ln[1] == "") and #ln <= 1)
          if not empty then label = ln end
        end
        if not label then label = {"?", {"surface-property-name." .. e.name}, e.name} end
        local ok_t, it = pcall(function() return e.proto.is_time end)
        local ok_u, uk = pcall(function() return e.proto.localised_unit_key end)
        if not (ok_u and type(uk) == "string") then uk = nil end
        lines[#lines + 1] = {"", label, ": ",
          format_surf_prop_value(e.name, v, ok_t and it or false, uk)}
      end
    end
  end

  -- содержимое: rich-теги посчитаны на data-стадии (data-final-fixes.lua ->
  -- mod-data "space-map-rework-contents"); в runtime autoplace прототипов
  -- недоступен. ЗЕРКАЛО списка исключений построек — data-final-fixes.lua
  -- (EXCLUDED_PLAYER_ENTITY_TYPES); fallback ниже типы не проверяет
  -- (в ключах mgs построек не бывает).
  local card_icons = nil
  local ok_md, md_tags = pcall(function()
    local md = prototypes.mod_data["space-map-rework-contents"]
    if md and md.data then return md.data[name] end
    return nil
  end)
  if ok_md and type(md_tags) == "table" and #md_tags > 0 then
    card_icons = {}
    for i = 1, math.min(#md_tags, CARD_MAX_ICONS) do
      local tag = md_tags[i]
      if type(tag) == "string" then card_icons[#card_icons + 1] = tag end
    end
  end
  if not card_icons then
    -- fallback без mod-data: ключи map_gen_settings (autoplace_controls +
    -- autoplace_settings.entity; нормализация "_"→"-", хвост после
    -- последнего "_") + жидкости плиток
    local ok2, mgs = pcall(function() return proto.map_gen_settings end)
    if ok2 and mgs then
      local res_names, seen = {}, {}
      local function add_name(rname)
        if rname ~= "water" and not string.find(rname, "cliff") and rname ~= "starting_area" and not seen[rname] then
          seen[rname] = true
          res_names[#res_names + 1] = rname
        end
      end
      if mgs.autoplace_controls then
        for rname, _ in pairs(mgs.autoplace_controls) do add_name(rname) end
      end
      local ok3, ents = pcall(function()
        if mgs.autoplace_settings and mgs.autoplace_settings.entity then
          return mgs.autoplace_settings.entity.settings
        end
        return nil
      end)
      if ok3 and ents then
        for rname, _ in pairs(ents) do add_name(rname) end
      end
      -- добываемые жидкости из плиток (offshore-pump): tile.fluid
      local ok_t, tiles = pcall(function()
        if mgs.autoplace_settings and mgs.autoplace_settings.tile then
          return mgs.autoplace_settings.tile.settings
        end
        return nil
      end)
      if ok_t and tiles then
        for tname, _ in pairs(tiles) do
          local ok_f, f = pcall(function()
            local t = prototypes.tile[tname]
            return t and t.fluid or nil
          end)
          if ok_f and type(f) == "string" and not seen[f] then
            seen[f] = true
            res_names[#res_names + 1] = f
          end
        end
      end
      table.sort(res_names)
      local icons, n = {}, 0
      for _, rname in ipairs(res_names) do
        local cands = {rname, rname:gsub("_", "-")}
        local last = string.match(rname, "_(%w+)$")
        if last then cands[#cands + 1] = last end
        local tag = nil
        for _, c in ipairs(cands) do
          local t = resource_rich_tag(c)
          if string.sub(t, 1, 1) == "[" then tag = t break end
        end
        if tag then
          table.insert(icons, tag)
          n = n + 1
          if n >= CARD_MAX_ICONS then break end
        end
      end
      if #icons > 0 then card_icons = icons end
    end
  end
  if card_icons and #card_icons > 0 then
    table.insert(lines, table.concat(card_icons, " "))
  end

  if #lines == 0 then return name end
  return card_assemble(lines)
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

  -- === Открытость тела (исследование) ===
-- force.is_space_location_unlocked силы "player"; при недоступном API —
-- запасной путь: technologies[map[name]].researched из mod-data discovery;
-- тела без технологии считаются открытыми (nauvis и т.п.). Луна открыта,
-- если открыта она сама или родитель. Тело вне карты — без наследования.
-- Глобально: используется routes.lua (связи) и gui.lua (ПКМ/hover).
function starmap_body_unlocked(name)
  local force = game.forces["player"]
  if not force or not name then return true end
  local function unlocked_force(nm)
    local ok, v = pcall(function() return force.is_space_location_unlocked(nm) end)
    if ok and type(v) == "boolean" then return v end
    local ok_m, map = pcall(function()
      return prototypes.mod_data["space-map-rework-discovery"].data.map
    end)
    local tech = ok_m and map and map[nm] or nil
    if tech then
      local ok_t, r = pcall(function() return force.technologies[tech].researched end)
      if ok_t and type(r) == "boolean" then return r end
    end
    return true
  end
  local b = storage.planet_by_name and storage.planet_by_name[name] or nil
  if unlocked_force(name) then return true end
  if b and b.parent_name then return unlocked_force(b.parent_name) == true end
  return false
end

-- === Разделение тел на звёздные и луны ===
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
        proto = nil,          -- прототипы в storage не хранятся
        discovered = true,    -- видимость от исследований не зависит
      }

      if parent_name then
        table.insert(moon_bodies, body)
      else
        table.insert(star_bodies, body)
      end
    end
  end

  -- === Радиусы звёздных орбит ===
  table.sort(star_bodies, function(a, b) return (a.distance or math.huge) < (b.distance or math.huge) end)
  local rad_in = {}
  for i, b in ipairs(star_bodies) do
    if not b.distance then b.distance = 10 + i * 10 end
    rad_in[i] = {raw = math.max((b.distance + STAR_DISTANCE_BONUS) * STAR_DISTANCE_SCALE, MIN_ORBIT_RADIUS)}
  end
  spread_radii(rad_in, STAR_RADIUS + STAR_ORBIT_GAP + 2, MAX_ORBIT_RADIUS,
    function() return STAR_ORBIT_GAP end)
  for i, b in ipairs(star_bodies) do
    local r = rad_in[i].r
    b.orbit_radius = r

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
    -- Зазор между кольцами лун зависит от иконок обеих соседних лун.
    local mrad = {}
    local ring_gap = math.max(0.02, MOON_ORBIT_SCALE * 1.2)
    local inner_gap = math.max(0.05, MOON_ORBIT_SCALE * 2)    -- от края иконки родителя
    for i, m in ipairs(list) do
      if not m.distance then m.distance = 5 + i * 5 end

      local size = (PLANET_SIZE_BASE * m.magnitude + PLANET_SIZE_BONUS + SAT_SIZE_BONUS) * MOON_SIZE_SCALE
      m.icon_radius = math.max(0.4, size)

      if m.orientation then
        m.angle = (m.orientation % 1) * 2 * math.pi
      else
        m.angle = i * GOLDEN_ANGLE
      end

      mrad[i] = {raw = (m.distance + SAT_DISTANCE_BONUS) * SAT_DISTANCE_SCALE * MOON_ORBIT_SCALE}
    end
    spread_radii(mrad,
      math.max(SAT_MIN_RADIUS, parent_icon + (list[1] and list[1].icon_radius or 0) + inner_gap),
      SAT_MAX_RADIUS,
      function(i) return list[i - 1].icon_radius + list[i].icon_radius + ring_gap end)
    for i, m in ipairs(list) do
      local r = mrad[i].r
      m.orbit_radius = r

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

  -- === Рендер открытых тел ===
  for _, b in ipairs(storage.planets) do
    if b.discovered then
      local proto = get_proto(b.prototype_name)
      local is_moon = b.parent_name ~= nil

      -- орбита: лунная — вокруг родителя, звёздная — вокруг (0,0).
      -- draw_orbit=false в прототипе: кольцо не рисуется (иконка/подпись/
      -- маркер остаются); b.orbit_id остаётся nil (r_*-хелперы nil-safe).
      -- Луны: орбита рисуется всегда (флаг игнорируется).
      local draw_orbit_flag = true
      if proto and not is_moon then
        local ok_do, dov = pcall(function() return proto.draw_orbit end)
        if ok_do and dov == false then draw_orbit_flag = false end
      end
      if draw_orbit_flag then
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
      end

      -- иконка только после исследования (PLANET_DISCOVERY_GATED); иначе —
      -- плейсхолдер not-available без подписи имени (маркер hover остаётся)
      local unlocked = true
      if PLANET_DISCOVERY_GATED ~= false then
        unlocked = starmap_body_unlocked(b.prototype_name)
      end
      if unlocked then
        b.sprite_id = draw_planet_sprite(surface, b.prototype_name, b.position, b.icon_radius, b.angle)
        -- обводка исследованного тела (белая; жёлтая при наведении — gui.lua)
        b.ring_id = draw_body_ring(surface, b)

        -- подпись под иконкой
        if proto then
          local ok_t, tobj = pcall(function()
            return rendering.draw_text{
              text = proto.localised_name or {"space-location-name." .. b.prototype_name},
              surface = surface,
              target = {x = b.position.x, y = b.position.y + b.icon_radius + planet_name_gap(b.icon_radius)},
              color = {r = 1, g = 1, b = 1, a = 0.95},
              scale = 0.8,
              alignment = "center"
            }
          end)
          if ok_t and tobj then b.name_text_id = tobj.id end
        end
      else
        b.sprite_id = draw_locked_sprite(surface, b.position, b.icon_radius)
      end

      -- Маркер-сущность (hover/клик). Прототипы в storage не хранятся;
      -- сущность переобнаруживается по имени+позиции (unit_number у
      -- simple-entity отсутствует).
      local marker_name = "space-map-rework-marker-" .. b.prototype_name
      local ok_mp, mp = pcall(function() return prototypes.entity[marker_name] end)
      if not (ok_mp and mp) then marker_name = "space-map-rework-planet-marker" end
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

  -- восстановление карточек, если были включены
  if storage.info_visible then
    storage.info_visible = false
    if toggle_info_cards then toggle_info_cards(nil) end
  end

  -- hover-подсветка колец: рендеры пересозданы, состояния устарели
  storage.body_ring_hover = {}

  local discovered_count = 0
  for _, b in ipairs(storage.planets) do if b.discovered then discovered_count = discovered_count + 1 end end
  log("[space-map-rework] rebuilt: " .. #storage.planets .. " bodies, " .. discovered_count .. " discovered"
    .. " | MOON_ORBIT_SCALE=" .. tostring(MOON_ORBIT_SCALE)
    .. " MOON_SIZE_SCALE=" .. tostring(MOON_SIZE_SCALE)
    .. " STAR_ORBIT_GAP=" .. tostring(STAR_ORBIT_GAP))
end

-- === Значок платформ у планеты (ванильный спрайт; fallback — треугольник) ===
-- На тело — ОДИН значок (как в ванили): все стоячие платформы тела делят
-- одну позицию (PLATFORM_SLOT_START); при N>1 рядом бейдж «×N»; одна
-- маркер-сущность на тело. platform_slots хранит записи всех платформ с
-- одинаковым углом — нужны клику/пину/якорям окон.
function refresh_platform_marks()
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid or not storage.planets then return end

  -- сброс старых рендеров, подписей, слотов и маркер-сущностей платформ
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
    for _, e in ipairs(surface.find_entities_filtered{name = "space-map-rework-platform-marker"}) do
      if e.valid then pcall(function() e.destroy() end) end
    end
  end)

  -- платформы по локациям (все силы)
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
  -- стабильный порядок слотов: index, затем force, затем имя
  for _, list in pairs(plats_by_loc) do
    table.sort(list, function(a, b)
      if a.index ~= b.index then return a.index < b.index end
      if a.force ~= b.force then return a.force < b.force end
      return (a.name or "") < (b.name or "")
    end)
  end

  -- доступность ванильного спрайта
  local sprite_ok = false
  do
    -- ванильный лист stacked-states, первый кадр (спрайт с data-стадии)
    local ok, v = pcall(function() return helpers.is_valid_sprite_path("space-map-rework-platform-parked") end)
    sprite_ok = ok and v == true
  end

  -- Один значок на тело: позиция = PLATFORM_SLOT_START у орбиты.
  local drawn, first_err = 0, nil
  for _, p in ipairs(storage.planets) do
    local list = plats_by_loc[p.prototype_name]
    if p.discovered and list and #list > 0 and p.position then
      p.platform_render_ids = {}
      p.platform_label_ids = {}
      p.platform_slots = {}
      p.platform_sprite_mode = sprite_ok
      local dist = platform_slot_dist(p)
      local ang = PLATFORM_SLOT_START
      local ux, uy = math.cos(ang), math.sin(ang)
      local cx = p.position.x + ux * dist
      local cy = p.position.y + uy * dist
      -- записи платформ с общим углом (клик/пин/якоря окон)
      for i, plat in ipairs(list) do
        p.platform_slots[i] = {force = plat.force, index = plat.index, name = plat.name, angle = ang}
      end

      local ok, obj
      if sprite_ok then
        ok, obj = pcall(function()
          return rendering.draw_sprite{
            -- стоячие платформы: первый кадр листа stacked-states (54x54)
            sprite = "space-map-rework-platform-parked",
            target = {x = cx, y = cy},
            surface = surface,
            x_scale = (PLATFORM_SIZE * 32) / 54,
            y_scale = (PLATFORM_SIZE * 32) / 54,
            orientation = (ang / (2 * math.pi) + PLATFORM_SPRITE_ROTATION) % 1
          }
        end)
      else
        -- fallback: треугольник (draw_polygon = triangle strip, без filled)
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

      -- бейдж «×N» при нескольких платформах (позиция — как у подписей:
      -- за значком; следование за планетой — общий код orbits.lua)
      if #list > 1 then
        local lx = p.position.x + ux * (dist + PLATFORM_LABEL_GAP)
        local ly = p.position.y + uy * (dist + PLATFORM_LABEL_GAP)
        local ok_t, tobj = pcall(function()
          return rendering.draw_text{
            text = "×" .. #list,
            surface = surface,
            target = {x = lx, y = ly},
            color = {r = 0.85, g = 0.95, b = 1, a = 0.9},
            scale = 0.5,
            alignment = "center",
            orientation = 0
          }
        end)
        if ok_t and tobj then
          table.insert(p.platform_label_ids, tobj.id)
          r_bring_front(tobj.id)
        end
      end

      -- одна маркер-сущность на тело (hover -> список, ПКМ)
      pcall(function()
        surface.create_entity{
          name = "space-map-rework-platform-marker",
          position = {x = cx, y = cy},
          force = "neutral"
        }
      end)
    end
  end

  local parked_total = 0
  for _, lst in pairs(plats_by_loc) do parked_total = parked_total + #lst end
  log("[space-map-rework] platforms: parked=" .. parked_total
    .. ", icons drawn=" .. drawn
    .. ", mode=" .. (sprite_ok and "vanilla-sprite" or "triangle-fallback")
    .. (first_err and (" | ПЕРВАЯ ОШИБКА: " .. first_err) or ""))
end
