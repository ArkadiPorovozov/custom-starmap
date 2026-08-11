-- data-final-fixes.lua
-- Маркеры планет с ванильным описанием + сохранение орбит (PlanetsLib) в mod-data для runtime.
-- ВНИМАНИЕ: запись файлов через io из data-стадии удалена - data-стадия не должна писать в файловую систему.
-- Орбиты передаются в control через прототип mod-data (prototypes.mod_data["custom-se-starmap-orbits"]).

local function truncate(s, limit)
  limit = limit or 180
  s = tostring(s)
  if #s > limit then return string.sub(s, 1, limit - 3) .. "..." end
  return s
end

local prop_labels = {
  ["solar-power"] = "Солнечная энергия в атмосфере",
  ["pressure"] = "Давление",
  ["gravity"] = "Гравитация",
  ["magnetic-field"] = "Магнитное поле",
  ["day-night-ratio"] = "Цикл дня и ночи",
  ["temperature"] = "Температура",
}

local function translate_prop_key(key)
  local lower = string.lower(key)
  if prop_labels[key] then return prop_labels[key] end
  if string.find(lower, "spire") or string.find(lower, "karn") then return "Энергопроводность шпиля Карны" end
  if string.find(lower, "radiation") then return "Фоновая радиация" end
  if string.find(lower, "gas") then return "Газовая насыщенность атмосферы" end
  if string.find(lower, "drone") then return "Использование энергии дронами" end
  if string.find(lower, "crystall") then return "Сопротивление кристаллизации" end
  if string.find(lower, "dust") and not string.find(lower, "asteroid") then return "Концентрация пыли" end
  if string.find(lower, "pollen") or (string.find(lower, "spore") and string.find(lower, "corros")) then return "Коррозия пыльцой" end
  if string.find(lower, "wind") then return "Скорость ветра" end
  if string.find(lower, "asteroid") then return "Плотность астероидов" end
  if string.find(lower, "rocket") then return "Части ракеты" end
  if string.find(lower, "evolution") then return "Фактор эволюции" end
  return key:gsub("-", " "):gsub("_", " ")
end

local function format_prop_value(key, value)
  if type(value) ~= "number" then return truncate(value, 100) end
  local lower = string.lower(key)
  if lower == "solar-power" or string.find(lower, "magnetic") then
    if value <= 5 then return string.format("%.0f %%", value * 100) end
    return string.format("%.0f %%", value)
  end
  if lower == "pressure" then return string.format("%.0f гПа", value) end
  if lower == "gravity" then return string.format("%.2f м/с²", value) end
  if lower == "day-night-ratio" then return string.format("%d минут", math.floor(value * 6 + 0.5)) end
  if lower == "temperature" then return string.format("%d K", math.floor(value)) end
  if string.find(lower, "radiation") then return string.format("%d Бк", value) end
  if string.find(lower, "gas") then return string.format("%d %%", value * 100) end
  if string.find(lower, "drone") then return "×" .. value end
  if string.find(lower, "crystall") or string.find(lower, "dust") then return string.format("%d %%", value) end
  if string.find(lower, "wind") then return string.format("%d км/ч", value) end
  if string.find(lower, "asteroid") then return string.format("%d ppb", value) end
  if string.find(lower, "rocket") then return "×" .. value end
  if string.find(lower, "evolution") then return string.format("%.4f", value) end
  if value < 10 and value ~= math.floor(value) then return string.format("%.2f", value) end
  return tostring(value)
end

local function collect_resources(p)
  local res = {}
  local ok, mgs = pcall(function() return p.map_gen_settings end)
  if not ok or not mgs then return res end
  if mgs.autoplace_controls then
    for name, _ in pairs(mgs.autoplace_controls) do
      if name ~= "water" and not string.find(name, "cliff") and name ~= "starting_area" then
        table.insert(res, name)
        if #res >= 12 then break end
      end
    end
  end
  if mgs.autoplace_settings and mgs.autoplace_settings.entity and mgs.autoplace_settings.entity.settings then
    for name, _ in pairs(mgs.autoplace_settings.entity.settings) do
      table.insert(res, name)
      if #res >= 12 then break end
    end
  end
  return res
end

-- Rich-тег иконки ресурса на data-стадии: item -> fluid -> entity, иначе текст.
-- [item=crude-oil] не существует -> в игре показывался "неизвестный ключ".
local function rich_tag_or_name(name)
  if data.raw.item and data.raw.item[name] then return "[item=" .. name .. "]" end
  if data.raw.fluid and data.raw.fluid[name] then return "[fluid=" .. name .. "]" end
  for _, t in ipairs({"resource", "tree", "fish", "simple-entity", "unit", "asteroid"}) do
    if data.raw[t] and data.raw[t][name] then return "[entity=" .. name .. "]" end
  end
  return name
end

local function build_localised_description(proto, planet_proto)
  local parts = {""}
  local function add_line(k, v)
    if v == nil or v == "" then return end
    table.insert(parts, {"", truncate(k, 80) .. ": ", truncate(v, 180), "\n"})
  end
  local function add_header(t)
    table.insert(parts, {"", "\n[font=default-bold]" .. truncate(t, 80) .. "[/font]\n"})
  end

  -- Ванильные surface_properties
  local sp = nil
  pcall(function()
    if planet_proto and planet_proto.surface_properties then
      sp = planet_proto.surface_properties
    elseif proto.surface_properties then
      sp = proto.surface_properties
    end
  end)
  if sp then
    for k, v in pairs(sp) do
      if type(k) == "string" then
        add_line(translate_prop_key(k), format_prop_value(k, v))
      end
    end
  end

  -- Солнечная энергия в космосе
  local ok_solar, solar = pcall(function() return proto.solar_power_in_space end)
  if ok_solar and solar then
    add_line("Солнечная энергия в космосе", format_prop_value("solar-power", solar / 100))
  end

  -- Ресурсы как иконки "Содержимое:"
  local all_res = {}
  for _, n in ipairs(collect_resources(proto)) do table.insert(all_res, n) end
  if planet_proto then
    for _, n in ipairs(collect_resources(planet_proto)) do table.insert(all_res, n) end
  end
  local seen, uniq_list = {}, {}
  for _, r in ipairs(all_res) do
    if not seen[r] then
      seen[r] = true
      table.insert(uniq_list, r)
      if #uniq_list >= 12 then break end
    end
  end
  if #uniq_list > 0 then
    add_header("Содержимое")
    local icons = {}
    for _, rname in ipairs(uniq_list) do
      table.insert(icons, rich_tag_or_name(rname))
    end
    -- Разбиваем на куски <180 символов, не режем иконки
    local line = table.concat(icons, " ")
    while #line > 0 do
      local chunk = string.sub(line, 1, 180)
      if #line > 180 then
        local last_space = chunk:match("^.*() ")
        if last_space then chunk = string.sub(line, 1, last_space - 1) end
      end
      table.insert(parts, {"", chunk, "\n"})
      line = string.sub(line, #chunk + 1)
      line = line:gsub("^%s+", "")
    end
  end

  -- Ванильное описание из прототипа
  local ok_d1, d1 = pcall(function() return proto.localised_description end)
  local ok_d2, d2 = false, nil
  if planet_proto then
    ok_d2, d2 = pcall(function() return planet_proto.localised_description end)
  end
  if ok_d1 and d1 then
    table.insert(parts, {"", "\n", d1, "\n"})
  elseif ok_d2 and d2 then
    table.insert(parts, {"", "\n", d2, "\n"})
  end

  return parts
end

-- Собираем все небесные тела (анемоны исключаем, как и раньше)
local space_locations = {}
if data.raw["space-location"] then
  for name, proto in pairs(data.raw["space-location"]) do
    if not string.find(string.lower(name), "anemone") then
      space_locations[name] = proto
    end
  end
end
if data.raw["planet"] then
  for name, proto in pairs(data.raw["planet"]) do
    if not string.find(string.lower(name), "anemone") then
      if not space_locations[name] then
        space_locations[name] = proto
      end
    end
  end
end

-- Размер маркера под размер планеты/луны.
-- Зеркало формулы из control/starsystem.lua. Значения — ЛИТЕРАЛЫ, как и
-- control/constants.lua (startup-настройки застревают в сохранении!).
-- Держать синхронно с constants.lua!
local MARKER_PLANET_SIZE_BASE = 0.6
local MARKER_PLANET_SIZE_BONUS = 0.5
local MARKER_SAT_SIZE_BONUS = 0.3
local MARKER_MOON_SIZE_SCALE = 0.5

local function star_like(n)
  local l = string.lower(n or "")
  for _, kw in ipairs({"star", "calidus", "kalidus", "sol", "sun"}) do
    if string.find(l, kw, 1, true) then return true end
  end
  return false
end

local function marker_half_size(name, proto)
  local mag = 1
  pcall(function() if proto.magnitude and proto.magnitude > 0 then mag = proto.magnitude end end)

  -- луна, если орбита указывает на другое тело (не звезду)
  local moon = false
  local ok, orb = pcall(function() return proto.orbit end)
  if ok and orb and orb.parent then
    local okp, pname = pcall(function() return orb.parent.name end)
    if okp and pname and pname ~= name and not star_like(pname) and space_locations[pname] then
      moon = true
    end
  end

  local size
  if moon then
    size = (MARKER_PLANET_SIZE_BASE * mag + MARKER_PLANET_SIZE_BONUS + MARKER_SAT_SIZE_BONUS) * MARKER_MOON_SIZE_SCALE
  else
    size = MARKER_PLANET_SIZE_BASE * mag + MARKER_PLANET_SIZE_BONUS
  end
  -- хитбокс ВПЛОТНУЮ к иконке (ещё уменьшен по запросу; позиция синхронна
  -- с иконкой каждый тик — см. move_markers в control/orbits.lua)
  return math.max(0.2, size) * 0.6 + 0.05
end

-- Маркеры: пустая картинка (иконка рисуется отдельным рендером в control),
-- иначе у маленьких планет появляется большая полупрозрачная дупликация.
for name, proto in pairs(space_locations) do
  local marker_name = "custom-se-marker-" .. name
  if not data.raw["simple-entity"][marker_name] then
    local base = table.deepcopy(data.raw["simple-entity"]["custom-se-planet-marker"])
    base.name = marker_name
    if proto.icons then
      base.icons = table.deepcopy(proto.icons)
      base.icon = nil
      base.icon_size = nil
    elseif proto.icon then
      base.icon = proto.icon
      base.icon_size = proto.icon_size or 64
      base.icons = nil
    end
    base.picture = {
      filename = "__core__/graphics/empty.png",
      width = 1,
      height = 1
    }
    base.localised_name = proto.localised_name or {"space-location-name." .. name}
    local planet_proto = data.raw["planet"] and data.raw["planet"][name] or nil
    base.localised_description = build_localised_description(proto, planet_proto)
    -- hitbox под реальный размер иконки планеты/луны
    local half = marker_half_size(name, proto)
    base.selection_box = {{-half, -half}, {half, half}}
    base.max_health = 10000000
    base.flags = {"placeable-off-grid", "not-blueprintable", "not-deconstructable", "not-flammable", "not-repairable"}
    base.selectable_in_game = true
    base.collision_mask = {layers = {}}
    data:extend({base})
  end
end

local count = 0
for _ in pairs(space_locations) do count = count + 1 end
log("[custom-se-starmap] markers " .. count .. " vanilla-like desc with icons, gray orbits, reduced scale")

-- === Орбиты PlanetsLib для runtime (привязка лун к родительской планете) ===
local orbits_for_runtime = {}
for _, type_name in ipairs({"planet", "space-location"}) do
  if data.raw[type_name] then
    for name, proto in pairs(data.raw[type_name]) do
      local ok, orbit = pcall(function() return proto.orbit end)
      if ok and orbit and orbit.parent then
        local ok_n, pname = pcall(function() return orbit.parent.name end)
        local ok_t, ptype = pcall(function() return orbit.parent.type end)
        if ok_n and pname then
          orbits_for_runtime[name] = {
            parent = pname,
            parent_type = (ok_t and ptype) or "planet",
            distance = orbit.distance,
            orientation = orbit.orientation
          }
        end
      end
    end
  end
end

data:extend({
  {
    type = "mod-data",
    name = "custom-se-starmap-orbits",
    data = orbits_for_runtime
  }
})

local orbit_count = 0
for _ in pairs(orbits_for_runtime) do orbit_count = orbit_count + 1 end
log("[custom-se-starmap] saved " .. orbit_count .. " orbits for runtime (PlanetsLib compat)")

-- === Поиск технологий открытия планет — сканируем data.raw (по запросу) ===
-- Карта открытия: имя локации -> имя технологии.
-- Ищем двумя способами: эффект unlock-space-location и префикс имени planet-discovery-*.
local discovery_map = {}
local discovery_techs = {}

for tech_name, tech in pairs(data.raw["technology"] or {}) do
  local found_location = nil
  if tech.effects then
    for _, effect in ipairs(tech.effects) do
      if effect.type == "unlock-space-location" and effect.space_location then
        found_location = effect.space_location
        break
      end
    end
  end
  if found_location then
    if not discovery_map[found_location] then
      discovery_map[found_location] = tech_name
      table.insert(discovery_techs, tech_name)
    end
  elseif string.find(tech_name, "^planet%-discovery%-") then
    local location = string.gsub(tech_name, "^planet%-discovery%-", "")
    if not discovery_map[location] then
      discovery_map[location] = tech_name
      table.insert(discovery_techs, tech_name)
    end
  end
end

data:extend({
  {
    type = "mod-data",
    name = "custom-se-starmap-discovery",
    data = {
      map = discovery_map,     -- [location_name] = tech_name
      techs = discovery_techs  -- список технологий открытия
    }
  }
})
log("[custom-se-starmap] discovery techs found in data.raw: " .. #discovery_techs)

-- === Иконки тел для runtime ===
-- В runtime LuaSpaceLocationPrototype НЕ отдаёт пути icon/starmap_icon,
-- поэтому собираем их здесь, в data-стадии, и отдаём через mod-data.
-- Сохраняем и размер иконки в пикселях — он нужен для подгона масштаба спрайта.
local function icon_info_of(proto)
  local ok, v = pcall(function() return proto.starmap_icon end)
  if ok and v and v ~= "" then
    local ok2, s = pcall(function() return proto.starmap_icon_size end)
    return {path = v, size = (ok2 and s) or 64}
  end
  ok, v = pcall(function() return proto.icon end)
  if ok and v and v ~= "" then
    local ok2, s = pcall(function() return proto.icon_size end)
    return {path = v, size = (ok2 and s) or 64}
  end
  ok, v = pcall(function()
    if proto.icons and proto.icons[1] then return proto.icons[1].icon end
    return nil
  end)
  if ok and v and v ~= "" then
    local ok2, s = pcall(function() return proto.icons[1].icon_size end)
    return {path = v, size = (ok2 and s) or 64}
  end
  return nil
end

local icons_for_runtime = {}
for _, type_name in ipairs({"planet", "space-location"}) do
  for name, proto in pairs(data.raw[type_name] or {}) do
    local info = icon_info_of(proto)
    if info then icons_for_runtime[name] = info end
  end
end

data:extend({
  {
    type = "mod-data",
    name = "custom-se-starmap-icons",
    data = icons_for_runtime
  }
})
local icon_count = 0
for _ in pairs(icons_for_runtime) do icon_count = icon_count + 1 end
log("[custom-se-starmap] saved " .. icon_count .. " icon paths for runtime")
