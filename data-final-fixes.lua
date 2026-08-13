-- data-final-fixes.lua
-- Маркеры планет с описаниями (localised_description), передача орбит/иконок/
-- карты технологий открытия в runtime через mod-data прототипы.
-- Запись файлов через io из data-стадии не используется.

local function truncate(s, limit)
  limit = limit or 180
  s = tostring(s)
  if #s > limit then return string.sub(s, 1, limit - 3) .. "..." end
  return s
end

-- ═══ Описание маркера планеты ═══
-- Состав localised_description маркера (порядок блоков; блоки разделяются
-- пустой строкой):
--   1) описание тела (localised_description прототипа или локаль
--      space-location-description./planet-description.);
--   2) параметры поверхности: заданные планетой surface_properties плюс
--      ванильная базовая пятёрка; значения — через localised_unit_key,
--      как в ванильном тултипе;
--   3) "Содержимое": иконки ВСЕХ прототипов сущностей с autoplace,
--      покрытых ключами map_gen_settings планеты (autoplace_controls +
--      autoplace_settings.entity.settings), плюс жидкости плиток;
--      исключаются типы построек игрока (ассемблеры, реакторы, генераторы,
--      электростолбы, буры, манипуляторы и т.д.) и hidden-прототипы;
--   4) солнечная энергия в космосе (solar_power_in_space, default 100).
-- Движок: <=20 параметров LocalisedString на уровень, глубина <=20,
-- строковый параметр <=200 байт UTF-8. Строки упаковываются в вложенные
-- группы <= LS_GROUP_SIZE параметров; значения параметров-строк — атомарные
-- (<= LS_MAX_BYTES).
-- Иконки "Содержимого" передаются в runtime через mod-data
-- "space-map-rework-contents" (control/starsystem.lua, build_card_text).

local LS_MAX_BYTES = 180
local LS_GROUP_SIZE = 16
local CONTENTS_MAX_ICONS = 40   -- потолок иконок в секции "Содержимое"
local UNIT_MIN = "min"

-- Показываются свойства, заданные самой планетой (surface_properties[name]),
-- плюс ванильная базовая пятёрка всегда (как в тултипе ванили). Свойства
-- других модов без значения у планеты не выводятся (иначе — строки ":0").
-- ЗЕРКАЛО: control/starsystem.lua (build_card_text) — держать синхронно.
local CORE_SURFACE_PROPS = {
  ["day-night-cycle"] = true,
  gravity = true,
  ["magnetic-field"] = true,
  pressure = true,
  ["solar-power"] = true,
}

-- Форматирование значений surface-property. Приоритет — ванильный
-- механизм единиц: {localised_unit_key (default surface-property-unit.<name>),
-- значение}; шаблон юнита получает значение как __1__. При отсутствии
-- шаблона в локали — число/эвристики. Единицы — нейтральные символы (СИ).
-- ЗЕРКАЛО: control/starsystem.lua (format_surf_prop_value, runtime) —
-- держать синхронно.
local function format_prop_value(key, value, is_time, unit_key)
  if type(value) ~= "number" then return truncate(value, 100) end
  local lower = string.lower(key)
  if is_time or lower == "day-night-cycle" then
    return string.format("%d " .. UNIT_MIN, math.floor(value / 3600 + 0.5))
  end
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
  if unit_key and unit_key ~= "" then
    return {"?", {unit_key, numstr(value)}, numstr(value)}
  end
  -- эвристики для свойств без юнит-ключа в локали
  if lower == "solar-power" or string.find(lower, "magnetic") then
    if value <= 5 then return string.format("%.0f %%", value * 100) end
    return string.format("%.0f %%", value)
  end
  if lower == "pressure" then return string.format("%.0f hPa", value) end
  if lower == "gravity" then return string.format("%.2f m/s²", value) end
  if lower == "day-night-ratio" then return string.format("%d " .. UNIT_MIN, math.floor(value * 6 + 0.5)) end
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

-- Имя параметра: localised_name прототипа (имена кастомных свойств
-- даёт мод-владелец) или локаль surface-property-name.<name>.
-- Пустой localised_name ("" / {""}) считается отсутствующим — иначе
-- строка свойства выходит без имени (ёмкое «: <значение>»).
local function ls_is_empty(ln)
  if type(ln) == "string" then return ln == "" end
  if type(ln) == "table" then
    return (ln[1] == nil or ln[1] == "") and #ln <= 1
  end
  return true
end
local function prop_label_ls(pproto, name)
  local ok, ln = pcall(function() return pproto.localised_name end)
  if ok and not ls_is_empty(ln) then return ln end
  return {"?", {"surface-property-name." .. name}, name}
end

-- Строки параметров поверхности (по одному LocalisedString на строку).
local function property_lines(proto, planet_proto)
  local lines = {}
  local sp = nil
  pcall(function()
    if planet_proto and planet_proto.surface_properties then
      sp = planet_proto.surface_properties
    elseif proto.surface_properties then
      sp = proto.surface_properties
    end
  end)
  local list = {}
  for pname, pproto in pairs(data.raw["surface-property"] or {}) do
    list[#list + 1] = {name = pname, proto = pproto}
  end
  table.sort(list, function(a, b)
    local oa, ob = a.proto.order or "", b.proto.order or ""
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)
  for _, e in ipairs(list) do
    local v = nil
    if sp and sp[e.name] ~= nil then
      v = sp[e.name]
    elseif CORE_SURFACE_PROPS[e.name] then
      local ok_d, dv = pcall(function() return e.proto.default_value end)
      if ok_d then v = dv end
    end
    if v ~= nil then
      local ok_t, it = pcall(function() return e.proto.is_time end)
      local ok_u, uk = pcall(function() return e.proto.localised_unit_key end)
      if not (ok_u and type(uk) == "string") then uk = nil end
      lines[#lines + 1] = {"", prop_label_ls(e.proto, e.name), ": ",
        format_prop_value(e.name, v, ok_t and it or false, uk)}
    end
  end
  return lines
end

-- ═══ Сбор секции "Содержимое" ═══
-- Кандидаты — все прототипы сущностей data.raw с autoplace (т.е. реально
-- генерируемые картой). Сущность покрыта ключом map_gen_settings планеты,
-- если ключ равен имени сущности или её autoplace.control; сравнение —
-- с нормализацией "_"→"-" и по хвосту после последнего "_"/"-"
-- (в space-age ключи планетарные: "vulcanus_coal" против прототипа "coal",
-- "tungsten_ore" против "tungsten-ore").

-- Типы построек игрока — исключаются из "Содержимого" (ассемблеры,
-- реакторы, генераторы, электростолбы, буры, манипуляторы и т.д.).
-- ЗЕРКАЛО: control/starsystem.lua (build_card_text fallback) — держать
-- синхронно.
local EXCLUDED_PLAYER_ENTITY_TYPES = {
  ["assembling-machine"] = true, ["rocket-silo"] = true, ["furnace"] = true,
  ["boiler"] = true, ["generator"] = true, ["burner-generator"] = true,
  ["fusion-reactor"] = true, ["fusion-generator"] = true,
  ["reactor"] = true, ["solar-panel"] = true, ["accumulator"] = true,
  ["electric-pole"] = true, ["mining-drill"] = true, ["inserter"] = true,
  ["agricultural-tower"] = true, ["heating-tower"] = true,
  ["offshore-pump"] = true, ["pump"] = true, ["pipe"] = true,
  ["pipe-to-ground"] = true, ["storage-tank"] = true,
  ["container"] = true, ["logistic-container"] = true,
  ["linked-container"] = true, ["infinity-container"] = true,
  ["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true,
  ["lane-splitter"] = true, ["loader"] = true, ["loader-1x1"] = true,
  ["linked-belt"] = true, ["infinity-pipe"] = true,
  ["roboport"] = true, ["beacon"] = true, ["lab"] = true, ["radar"] = true,
  ["lamp"] = true,
  ["ammo-turret"] = true, ["electric-turret"] = true,
  ["fluid-turret"] = true, ["artillery-turret"] = true,
  ["wall"] = true, ["gate"] = true,
  ["lightning-rod"] = true, ["lightning-attractor"] = true,
  ["straight-rail"] = true, ["curved-rail"] = true, ["half-diagonal-rail"] = true,
  ["curved-rail-a"] = true, ["curved-rail-b"] = true,
  ["rail-ramp"] = true, ["rail-support"] = true, ["elevated-straight-rail"] = true,
  ["elevated-curved-rail-a"] = true, ["elevated-curved-rail-b"] = true,
  ["elevated-half-diagonal-rail"] = true, ["rail-remnants"] = true,
  ["train-stop"] = true, ["rail-signal"] = true, ["rail-chain-signal"] = true,
  ["locomotive"] = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true,
  ["artillery-wagon"] = true,
  ["car"] = true, ["spider-vehicle"] = true, ["character"] = true,
  ["construction-robot"] = true, ["logistic-robot"] = true,
  ["constant-combinator"] = true, ["arithmetic-combinator"] = true,
  ["decider-combinator"] = true, ["selector-combinator"] = true,
  ["programmable-speaker"] = true, ["display-panel"] = true,
  ["power-switch"] = true,
  ["electric-energy-interface"] = true, ["heat-interface"] = true,
  ["heat-pipe"] = true,
  ["space-platform-hub"] = true, ["cargo-bay"] = true,
  ["asteroid-collector"] = true, ["thruster"] = true,
  ["cargo-landing-pad"] = true, ["player-port"] = true,
  ["tree-plant"] = true,
}

-- Корзина порядка вывода по типу сущности: ресурсы -> флора -> угрозы.
-- Прочие типы (cliff и т.п.) — в среднюю группу.
local ENTITY_BUCKET = {
  resource = "resource",
  tree = "flora",
  fish = "flora",
  plant = "flora",
  ["simple-entity"] = "flora",
  ["simple-entity-with-force"] = "flora",
  ["simple-entity-with-owner"] = "flora",
  cliff = "flora",
  unit = "threat",
  ["unit-spawner"] = "threat",
  turret = "threat",
  ["spider-unit"] = "threat",
  ["segmented-unit"] = "threat",
  segment = "threat",
  asteroid = "resource",
}

-- flags содержит "hidden"
local function proto_is_hidden(p)
  local f = p.flags
  if type(f) == "table" then
    for _, fl in ipairs(f) do if fl == "hidden" then return true end end
  end
  return false
end

-- Ключ иконки для дедупликации: путь icon (или icons[1].icon).
local function icon_key_of(p)
  if type(p.icon) == "string" then return p.icon end
  if type(p.icons) == "table" and p.icons[1] and type(p.icons[1].icon) == "string" then
    return p.icons[1].icon
  end
  return nil
end

-- Все сущности data.raw с autoplace, кроме построек игрока и hidden.
-- Кэшируется: список {name, type, control, icon}.
local autoplace_entity_cache = nil
local function autoplace_entity_list()
  if autoplace_entity_cache then return autoplace_entity_cache end
  autoplace_entity_cache = {}
  for etype, bucket in pairs(data.raw) do
    if type(bucket) == "table" and not EXCLUDED_PLAYER_ENTITY_TYPES[etype] then
      for ename, p in pairs(bucket) do
        if type(p) == "table" and p.type == etype and p.autoplace ~= nil
           and not proto_is_hidden(p) then
          autoplace_entity_cache[#autoplace_entity_cache + 1] = {
            name = ename, type = etype,
            control = p.autoplace.control,
            icon = icon_key_of(p)
          }
        end
      end
    end
  end
  return autoplace_entity_cache
end

-- Индекс прототипов по имени (первый встречный; иконки коллизий совпадают).
local proto_name_cache = nil
local function proto_by_name(name)
  if not proto_name_cache then
    proto_name_cache = {}
    for etype, bucket in pairs(data.raw) do
      if type(bucket) == "table" then
        for n, p in pairs(bucket) do
          if type(p) == "table" and p.type == etype and not proto_name_cache[n] then
            proto_name_cache[n] = p
          end
        end
      end
    end
  end
  return proto_name_cache[name]
end

-- map_gen_settings прототипа -> корзины resource/flora/threat:
-- [имя прототипа] = ключ иконки (false, если путь не найден).
local function collect_classified(p, acc)
  local ok, mgs = pcall(function() return p.map_gen_settings end)
  if not ok or not mgs then return end
  -- ключи покрытия: autoplace_controls + autoplace_settings.entity.settings
  local keys = {}
  local function add_key(k)
    if type(k) ~= "string" then return end
    keys[k] = true
    local norm = string.gsub(k, "_", "-")
    keys[norm] = true
    local t1 = string.match(k, "_([%w]+)$")
    if t1 then
      keys[t1] = true
      keys[string.gsub(t1, "_", "-")] = true
    end
    local t2 = string.match(norm, "%-([%w]+)$")
    if t2 then keys[t2] = true end
  end
  if mgs.autoplace_controls then
    for k, _ in pairs(mgs.autoplace_controls) do add_key(k) end
  end
  if mgs.autoplace_settings and mgs.autoplace_settings.entity
     and mgs.autoplace_settings.entity.settings then
    for k, _ in pairs(mgs.autoplace_settings.entity.settings) do add_key(k) end
  end
  for _, e in ipairs(autoplace_entity_list()) do
    if keys[e.name] or (e.control ~= nil and keys[e.control]) then
      local slot = acc[ENTITY_BUCKET[e.type] or "flora"]
      if slot[e.name] == nil then slot[e.name] = e.icon or false end
    end
  end
  -- добываемые жидкости из плиток (offshore-pump): tile.fluid
  -- (вода на воде, лава на vulcanus, oil-ocean на fulgora,
  -- ammoniacal-solution на aquilo и т.п.)
  local ok_tset, tiles = pcall(function()
    if mgs.autoplace_settings and mgs.autoplace_settings.tile then
      return mgs.autoplace_settings.tile.settings
    end
    return nil
  end)
  if ok_tset and tiles then
    for tname, _ in pairs(tiles) do
      local ok_f, f = pcall(function()
        local t = data.raw.tile and data.raw.tile[tname]
        return t and t.fluid or nil
      end)
      if ok_f and type(f) == "string" and data.raw.fluid and data.raw.fluid[f] then
        acc.resource[f] = icon_key_of(data.raw.fluid[f]) or false
      end
    end
  end
  -- территориальные враги (демолишеры): задаются без autoplace
  local ok_ts, ts = pcall(function() return mgs.territory_settings end)
  if ok_ts and ts and ts.units then
    for _, uname in ipairs(ts.units) do
      if type(uname) == "string" then
        local up = proto_by_name(uname)
        if up then acc.threat[uname] = icon_key_of(up) or false end
      end
    end
  end
end

-- Rich-тег: item -> fluid -> entity (любой тип). Иначе — имя текстом
-- (не попадёт в вывод: contents_tags пропускает не-теги).
local function rich_tag_or_name(name)
  if data.raw.item and data.raw.item[name] then return "[item=" .. name .. "]" end
  if data.raw.fluid and data.raw.fluid[name] then return "[fluid=" .. name .. "]" end
  if proto_by_name(name) then return "[entity=" .. name .. "]" end
  return name
end

-- Список rich-тегов секции "Содержимое": корзины в порядке
-- resource -> flora -> threat, внутри — сортировка по имени; по одной иконке
-- на прототип. Дедупликация по тегу и по ключу иконки (варианты с одной
-- картинкой — одна иконка). Потолок CONTENTS_MAX_ICONS.
local function contents_tags(acc)
  local tags, seen_tag, seen_icon = {}, {}, {}
  for _, bucket in ipairs({"resource", "flora", "threat"}) do
    local keys = {}
    for n in pairs(acc[bucket]) do keys[#keys + 1] = n end
    table.sort(keys)
    for _, n in ipairs(keys) do
      if #tags >= CONTENTS_MAX_ICONS then return tags end
      local tag = rich_tag_or_name(n)
      local ik = acc[bucket][n]
      -- [entity=...] у сущности без иконки движком рисуется текстом
      -- "Unknown key" — такие прототипы пропускаются (у item/fluid иконка
      -- всегда есть)
      if string.sub(tag, 1, 8) == "[entity=" and type(ik) ~= "string" then tag = nil end
      if tag and string.sub(tag, 1, 1) == "[" and not seen_tag[tag] then
        if type(ik) ~= "string" then ik = tag end
        if not seen_icon[ik] then
          seen_tag[tag] = true
          seen_icon[ik] = true
          tags[#tags + 1] = tag
        end
      end
    end
  end
  return tags
end

-- Теги -> строки (упаковка пробелами <= LS_MAX_BYTES на строку).
local function contents_lines(tags)
  local lines = {}
  local cur, curlen = {}, 0
  for _, tag in ipairs(tags) do
    if curlen + #tag + 1 > LS_MAX_BYTES - 2 and #cur > 0 then
      lines[#lines + 1] = table.concat(cur, " ")
      cur, curlen = {}, 0
    end
    cur[#cur + 1] = tag
    curlen = curlen + #tag + 1
  end
  if #cur > 0 then lines[#lines + 1] = table.concat(cur, " ") end
  return lines
end

-- Теги "Содержимого" по имени тела (кэш; источник mod-data для runtime).
local contents_by_name = {}
local function contents_tags_for(name, proto, planet_proto)
  if contents_by_name[name] then return contents_by_name[name] end
  local acc = {resource = {}, flora = {}, threat = {}}
  collect_classified(proto, acc)
  if planet_proto then collect_classified(planet_proto, acc) end
  local tags = contents_tags(acc)
  contents_by_name[name] = tags
  return tags
end

-- Упаковка строк в LocalisedString: вложенные группы <= LS_GROUP_SIZE
-- параметров (лимит движка 20 на уровень, с запасом на ключ/обёртки).
local function assemble_lines(lines)
  local cur = lines
  while #cur > 19 do
    local nxt, grp = {}, {""}
    for _, ln in ipairs(cur) do
      grp[#grp + 1] = ln
      if (#grp - 1) >= LS_GROUP_SIZE then
        nxt[#nxt + 1] = grp
        grp = {""}
      end
    end
    if #grp > 1 then nxt[#nxt + 1] = grp end
    cur = nxt
  end
  local parts = {""}
  for _, ln in ipairs(cur) do parts[#parts + 1] = ln end
  return parts
end

-- Описание тела: localised_description прототипа, иначе локаль-конвенция
-- (space-location-description./planet-description.); fallback — пустая строка.
local function body_description_ls(name, proto, planet_proto)
  local ok2, d2 = pcall(function() return proto.localised_description end)
  if ok2 and d2 then return d2 end
  if planet_proto then
    local ok1, d1 = pcall(function() return planet_proto.localised_description end)
    if ok1 and d1 then return d1 end
  end
  return {"?", {"space-location-description." .. name}, {"planet-description." .. name}, ""}
end

-- Добавление "\n" в конец строки: строки-параметры склеиваются движком
-- без разделителя. Строковые значения конкатенируются, LS — копия + параметр.
local function with_nl(ln)
  if type(ln) == "string" then return ln .. "\n" end
  local t = {}
  for i = 1, #ln do t[i] = ln[i] end
  t[#t + 1] = "\n"
  return t
end

local function build_localised_description(name, proto, planet_proto)
  local lines = {}
  -- блоки разделяются пустой строкой (без линии-разделителя)
  local function add_block(block_lines)
    if #block_lines == 0 then return end
    if #lines > 0 then lines[#lines + 1] = "" end
    for _, l in ipairs(block_lines) do lines[#lines + 1] = l end
  end

  -- 1) описание тела — наверху
  add_block({{"", body_description_ls(name, proto, planet_proto)}})

  -- 2) параметры поверхности (все surface-property, заданные планетой + базовые)
  add_block(property_lines(proto, planet_proto))

  -- 3) Содержимое: иконки всех генерируемых прототипов (кроме построек)
  local ctags = contents_tags_for(name, proto, planet_proto)
  local cl = contents_lines(ctags)
  if #cl > 0 then
    local block = {{"", "[font=default-bold]", {"space-map-rework.contents"}, "[/font]"}}
    for _, ln in ipairs(cl) do block[#block + 1] = ln end
    add_block(block)
  end

  -- 4) солнечная энергия в космосе (default 100%)
  local solar = 100
  local ok_s, s = pcall(function() return proto.solar_power_in_space end)
  if ok_s and type(s) == "number" then solar = s end
  add_block({{"", {"space-map-rework.solar-in-space"}, ": ",
    string.format("%.0f %%", solar)}})

  -- каждая строка завершается переносом (иначе движок клеит сплошным текстом)
  for i, ln in ipairs(lines) do lines[i] = with_nl(ln) end
  return assemble_lines(lines)
end

-- Все небесные тела (имена с "anemone" исключаются)
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
-- ЗЕРКАЛО формулы control/starsystem.lua; значения — литералы, как в
-- control/constants.lua (startup-настройки фиксируются в сохранении).
-- Держать синхронно с constants.lua.
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

  -- луна: орбита указывает на другое тело (не звезду)
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
  -- хитбокс вплотную к иконке; позиция синхронна с иконкой (move_markers)
  return math.max(0.2, size) * 0.6 + 0.05
end

-- Маркеры: пустая picture (иконка рисуется рендером в control).
for name, proto in pairs(space_locations) do
  local marker_name = "space-map-rework-marker-" .. name
  if not data.raw["simple-entity"][marker_name] then
    local base = table.deepcopy(data.raw["simple-entity"]["space-map-rework-planet-marker"])
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
    base.localised_description = build_localised_description(name, proto, planet_proto)
    -- хитбокс под размер иконки планеты/луны
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
log("[space-map-rework] markers " .. count .. " desc: all surface-properties + contents icons")

-- === Орбиты для runtime (привязка лун к родителям; совместимость PlanetsLib) ===
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
    name = "space-map-rework-orbits",
    data = orbits_for_runtime
  }
})

local orbit_count = 0
for _ in pairs(orbits_for_runtime) do orbit_count = orbit_count + 1 end
log("[space-map-rework] saved " .. orbit_count .. " orbits for runtime (PlanetsLib compat)")

-- === Карта технологий открытия планет (скан data.raw) ===
-- [название локации] = технология: эффект unlock-space-location
-- или префикс имени planet-discovery-*.
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
    name = "space-map-rework-discovery",
    data = {
      map = discovery_map,     -- [location_name] = tech_name
      techs = discovery_techs  -- список технологий открытия
    }
  }
})
log("[space-map-rework] discovery techs found in data.raw: " .. #discovery_techs)

-- === Иконки тел для runtime ===
-- В runtime пути icon/starmap_icon прототипов недоступны; собираются здесь
-- и передаются через mod-data (включая размер иконки для масштаба спрайта).
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
    name = "space-map-rework-icons",
    data = icons_for_runtime
  }
})
local icon_count = 0
for _ in pairs(icons_for_runtime) do icon_count = icon_count + 1 end
log("[space-map-rework] saved " .. icon_count .. " icon paths for runtime")

-- === Иконки "Содержимого" для runtime ===
-- Теги посчитаны на data-стадии (contents_tags_for; кэш contents_by_name
-- уже заполнен циклом маркеров). В runtime autoplace прототипов недоступен.
-- Потребитель: control/starsystem.lua (build_card_text).
local contents_for_runtime = {}
for name in pairs(space_locations) do
  local ctags = contents_by_name[name]
  if ctags and #ctags > 0 then contents_for_runtime[name] = ctags end
end

data:extend({
  {
    type = "mod-data",
    name = "space-map-rework-contents",
    data = contents_for_runtime
  }
})
local contents_count = 0
for _ in pairs(contents_for_runtime) do contents_count = contents_count + 1 end
log("[space-map-rework] saved contents icons for " .. contents_count .. " bodies")

-- ============================================================================
-- === ПОЛНАЯ ЗАМЕНА space-connection ===
-- Все существующие коннекшены удаляются, вместо них создаются свои
-- (правила — зеркало control/routes.lua):
--   * звёздные планеты — к CONN_NEIGHBOR_DEPTH соседям в каждую сторону
--     по радиусу орбиты;
--   * луны — к планете-родителю;
--   * space-location — одна связь к крайней планете внутри её орбиты;
--   * эксклюзивные (connections-exclusive.lua) — поверх, без дублей.
-- Длина = расстояние между телами на карте x CONN_KM_PER_UNIT.
--
-- В runtime прототипы коннекшенов read-only (from/to/length), создания через
-- script нет — вся замена только здесь, в data-стадии. Записываемы только
-- platform.space_connection и platform.distance у конкретной платформы.
--
-- Формулы — ЗЕРКАЛО control/starsystem.lua (литералы; держать синхронно
-- с control/constants.lua): стартовые позиции и длины должны совпадать
-- с runtime-картой.
-- ============================================================================

local CONN_STAR_RADIUS = 7          -- STAR_RADIUS
local CONN_STAR_ORBIT_GAP = 4       -- STAR_ORBIT_GAP
local CONN_STAR_DISTANCE_SCALE = 1  -- STAR_DISTANCE_SCALE
local CONN_STAR_DISTANCE_BONUS = 10 -- STAR_DISTANCE_BONUS
local CONN_MIN_ORBIT_RADIUS = 0     -- MIN_ORBIT_RADIUS
local CONN_MAX_ORBIT_RADIUS = 400   -- MAX_ORBIT_RADIUS
local CONN_SAT_DISTANCE_SCALE = 1   -- SAT_DISTANCE_SCALE
local CONN_SAT_DISTANCE_BONUS = 0   -- SAT_DISTANCE_BONUS
local CONN_SAT_MAX_RADIUS = 60      -- SAT_MAX_RADIUS
local CONN_MOON_ORBIT_SCALE = 0.15  -- MOON_ORBIT_SCALE
local CONN_PLANET_SIZE_BASE = 0.6   -- PLANET_SIZE_BASE
local CONN_PLANET_SIZE_BONUS = 0.5  -- PLANET_SIZE_BONUS
local CONN_SAT_SIZE_BONUS = 0.3     -- SAT_SIZE_BONUS
local CONN_MOON_SIZE_SCALE = 0.5    -- MOON_SIZE_SCALE
local CONN_KM_PER_UNIT = 1000       -- пересчёт тайлов карты в км
local CONN_MIN_LENGTH = 100         -- минимальная длина коннекшена
local CONN_GOLDEN_ANGLE = 2.3999632297286533

-- ЗЕРКАЛО spread_radii из control/starsystem.lua. Держать синхронно.
local function conn_spread_radii(entries, start_min, max_r, gap_fn)
  local n = #entries
  if n == 0 then return end
  local s = 0
  for i = 2, n do
    local d = entries[i].raw - entries[i - 1].raw
    if d > 1e-9 then s = math.max(s, gap_fn(i) / d) end
  end
  if s < 1 then s = 1 end
  local spread = entries[n].raw - entries[1].raw
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
  for i = 2, n do
    local need = entries[i - 1].r + gap_fn(i)
    if entries[i].r < need then entries[i].r = need end
  end
  for i = 1, n do
    if entries[i].r > max_r then entries[i].r = max_r end
  end
end

local function conn_collect_bodies()
  local bodies = {}
  for _, tn in ipairs({"planet", "space-location"}) do
    for name, proto in pairs(data.raw[tn] or {}) do
      if not bodies[name]
         and not star_like(name)
         and not string.find(string.lower(name), "anemone")
         and proto.hidden ~= true
      then
        local orb = nil
        pcall(function() orb = proto.orbit end)
        local parent = nil
        if orb and orb.parent then
          local okp, pn = pcall(function() return orb.parent.name end)
          if okp then parent = pn end
        end
        local dist = nil
        if orb and orb.distance and orb.distance > 0 then dist = orb.distance end
        if (not dist) and proto.distance and proto.distance > 0 then dist = proto.distance end
        local orient = nil
        if orb and orb.orientation then orient = orb.orientation end
        if not orient then orient = proto.orientation end
        local mag = 1
        pcall(function() if proto.magnitude and proto.magnitude > 0 then mag = proto.magnitude end end)
        bodies[name] = {
          name = name, parent = parent, dist = dist, orient = orient, mag = mag,
          moon = false, is_loc = (tn == "space-location")
        }
      end
    end
  end
  -- луна = орбита вокруг другого не-звёздного тела набора
  for _, info in pairs(bodies) do
    if info.parent and info.parent ~= info.name
       and not star_like(info.parent) and bodies[info.parent] then
      info.moon = true
    end
  end
  return bodies
end

local function conn_layout(bodies)
  -- стартовые позиции звёздных тел (зеркало rebuild_star_system)
  local star_list = {}
  for _, info in pairs(bodies) do
    if not info.moon then table.insert(star_list, info) end
  end
  table.sort(star_list, function(a, b) return (a.dist or math.huge) < (b.dist or math.huge) end)
  local srad = {}
  for i, bd in ipairs(star_list) do
    if not bd.dist then bd.dist = 10 + i * 10 end
    srad[i] = {raw = math.max((bd.dist + CONN_STAR_DISTANCE_BONUS) * CONN_STAR_DISTANCE_SCALE, CONN_MIN_ORBIT_RADIUS)}
  end
  conn_spread_radii(srad, CONN_STAR_RADIUS + CONN_STAR_ORBIT_GAP + 2, CONN_MAX_ORBIT_RADIUS,
    function() return CONN_STAR_ORBIT_GAP end)
  for i, bd in ipairs(star_list) do
    local r = srad[i].r
    bd.radius = r
    bd.icon = math.max(0.5, CONN_PLANET_SIZE_BASE * bd.mag + CONN_PLANET_SIZE_BONUS)
    bd.angle = (bd.orient and (bd.orient % 1) * 2 * math.pi) or (i * CONN_GOLDEN_ANGLE)
    bd.x = math.cos(bd.angle) * r
    bd.y = math.sin(bd.angle) * r
  end
  -- луны вокруг родителей (зеркало лунного блока)
  local by_parent = {}
  for _, info in pairs(bodies) do
    if info.moon then
      by_parent[info.parent] = by_parent[info.parent] or {}
      table.insert(by_parent[info.parent], info)
    end
  end
  for parent_name, list in pairs(by_parent) do
    table.sort(list, function(a, b) return (a.dist or math.huge) < (b.dist or math.huge) end)
    local parent = bodies[parent_name]
    local parent_icon = (parent and parent.icon) or 1.5
    local px = parent and parent.x or 0
    local py = parent and parent.y or 0
    local mrad = {}
    local ring_gap = math.max(0.02, CONN_MOON_ORBIT_SCALE * 1.2)
    local inner_gap = math.max(0.05, CONN_MOON_ORBIT_SCALE * 2)
    for i, m in ipairs(list) do
      if not m.dist then m.dist = 5 + i * 5 end
      m.icon = math.max(0.4, (CONN_PLANET_SIZE_BASE * m.mag + CONN_PLANET_SIZE_BONUS + CONN_SAT_SIZE_BONUS) * CONN_MOON_SIZE_SCALE)
      m.angle = (m.orient and (m.orient % 1) * 2 * math.pi) or (i * CONN_GOLDEN_ANGLE)
      mrad[i] = {raw = (m.dist + CONN_SAT_DISTANCE_BONUS) * CONN_SAT_DISTANCE_SCALE * CONN_MOON_ORBIT_SCALE}
    end
    conn_spread_radii(mrad,
      math.max(0, parent_icon + (list[1] and list[1].icon or 0) + inner_gap),
      CONN_SAT_MAX_RADIUS,
      function(i) return list[i - 1].icon + list[i].icon + ring_gap end)
    for i, m in ipairs(list) do
      local r = mrad[i].r
      m.radius = r
      m.x = px + math.cos(m.angle) * r
      m.y = py + math.sin(m.angle) * r
    end
  end
  return star_list, by_parent
end

-- Иконка конца коннекшена: у модовых планет может быть задан только icons
-- (без icon), иначе загрузка падает с 'Key "icon" not found'.
local function conn_endpoint_icon(proto)
  if not proto then return nil end
  if proto.icon and proto.icon ~= "" then
    return {path = proto.icon, size = proto.icon_size or 64}
  end
  if proto.icons then
    for _, layer in ipairs(proto.icons) do
      if layer.icon and layer.icon ~= "" then
        return {path = layer.icon, size = layer.icon_size or 64}
      end
    end
  end
  return nil
end

local function conn_find_location_proto(name)
  if data.raw["space-location"] and data.raw["space-location"][name] then
    return data.raw["space-location"][name]
  end
  if data.raw["planet"] and data.raw["planet"][name] then
    return data.raw["planet"][name]
  end
  return nil
end

-- Иконки коннекшена (схема space-age, устойчивая к отсутствию icon)
local function conn_build_icons(a_name, b_name)
  local icons = {{icon = "__space-age__/graphics/icons/planet-route.png"}}
  local fi = conn_endpoint_icon(conn_find_location_proto(a_name))
  local ti = conn_endpoint_icon(conn_find_location_proto(b_name))
  if fi then
    table.insert(icons, {icon = fi.path, icon_size = fi.size, scale = 0.333 * (64 / fi.size), shift = {-6, -6}})
  end
  if ti then
    table.insert(icons, {icon = ti.path, icon_size = ti.size, scale = 0.333 * (64 / ti.size), shift = {6, 6}})
  end
  return icons
end

do -- === замена коннекшенов ===
  -- ЗЕРКАЛО правил control/routes.lua:
  --   * звёздные планеты: по CONN_NEIGHBOR_DEPTH соседей в каждую сторону;
  --   * space-location: одна связь к крайней свободной планете внутри орбиты;
  --     локация со связью location<->location (ачивка/эксклюзив) пропускается;
  --   * эксклюзивные связи: только connections-exclusive.lua.
  local CONN_NEIGHBOR_DEPTH = 2     -- ROUTE_NEIGHBOR_DEPTH (зеркало)

  local EXC_OK, EXC = pcall(require, "connections-exclusive")
  if not (EXC_OK and type(EXC) == "table") then EXC = {} end

  local bodies = conn_collect_bodies()
  local star_list, by_parent = conn_layout(bodies)

  -- Запасные asteroid_spawn_definitions: копия с первого найденного
  -- коннекшена (иначе на маршрутах не спавнятся астероиды).
  -- Нормализация spawn_points коннекшенов: валидация прототипа 2.1 требует
  -- строго возрастающих distance в каждой записи (записи без числового
  -- distance выбрасываются, остальные сортируются, равные схлопываются;
  -- probability >= 0, speed > 0). Короткая форма записи {asteroid, {points}}
  -- предварительно приводится к длинной — для неё поле spawn_points в
  -- data.raw отсутствует. Записи без asteroid или с опустевшим массивом
  -- точек выбрасываются целиком. Применяется и к таблице ванильного
  -- генератора (ниже), и к fallback-копии чужого коннекшена.
  local function conn_sanitize_spawn_defs(defs)
    if type(defs) ~= "table" then return defs end
    -- чистка одного массива точек: без числового distance выбрасываются,
    -- остальные сортируются, равные distance схлопываются (оставляется
    -- первая) — валидация требует строгого возрастания.
    local function clean_points(pts)
      if type(pts) ~= "table" then return nil end
      local clean = {}
      for _, pt in ipairs(pts) do
        -- NaN/inf в distance ломает сортировку и валидацию; probability/speed
        -- клампятся (speed > 0, probability >= 0 — валидация движка)
        if type(pt) == "table" and type(pt.distance) == "number"
           and pt.distance == pt.distance
           and pt.distance ~= math.huge and pt.distance ~= -math.huge then
          if type(pt.probability) ~= "number" or pt.probability ~= pt.probability
             or pt.probability < 0 then pt.probability = 0 end
          if type(pt.speed) ~= "number" or pt.speed ~= pt.speed
             or pt.speed <= 0 then pt.speed = 1 end
          table.insert(clean, pt)
        end
      end
      table.sort(clean, function(x, y) return x.distance < y.distance end)
      local out, last = {}, nil
      for _, pt in ipairs(clean) do
        if last == nil or pt.distance > last then
          table.insert(out, pt)
          last = pt.distance
        end
      end
      return out
    end
    local comp = {}
    for _, def in ipairs(defs) do
      if type(def) == "table" then
        -- короткая форма записи {asteroid, {points}} (ванильная): поле
        -- spawn_points в data.raw отсутствует; приводится к длинной,
        -- иначе порядок distance сортировкой не покрывался
        if def.spawn_points == nil and type(def[2]) == "table" then
          if def.asteroid == nil and def[1] ~= nil then
            def.asteroid = def[1]
          end
          def.spawn_points = def[2]
          def[1], def[2] = nil, nil
        end
        def.spawn_points = clean_points(def.spawn_points)
        -- битые/опустевшие записи выбрасываются: пустой spawn_points или
        -- отсутствующий asteroid невалидны
        if def.asteroid ~= nil and def.spawn_points ~= nil
           and #def.spawn_points > 0 then
          table.insert(comp, def)
        end
      end
    end
    return comp
  end

  -- asteroid_spawn_definitions генерируются ванильным хелпером space-age
  -- (иначе на маршрутах не спавнятся астероиды). Раньше таблица копировалась
  -- с первого попавшегося чужого коннекшена: содержимое зависело от порядка
  -- загрузки модов и версии ribbonia (её обновление сломало унаследованные
  -- таблицы).
  local kept_spawn_defs = nil
  local ok_au, asteroid_util = pcall(require,
    "__space-age__.prototypes.planet.asteroid-spawn-definitions")
  if ok_au and type(asteroid_util) == "table"
     and type(asteroid_util.spawn_definitions) == "function" then
    local route = asteroid_util.vulcanus_gleba or asteroid_util.nauvis_gleba
    local ok_sd, sd = pcall(asteroid_util.spawn_definitions, route)
    if ok_sd and type(sd) == "table" and #sd > 0 then
      kept_spawn_defs = conn_sanitize_spawn_defs(table.deepcopy(sd))
    end
  end
  if not kept_spawn_defs then
    -- fallback: копия первого найденного коннекшена с нормализацией
    for _, c in pairs(data.raw["space-connection"] or {}) do
      if c.asteroid_spawn_definitions then
        kept_spawn_defs = conn_sanitize_spawn_defs(table.deepcopy(c.asteroid_spawn_definitions))
        break
      end
    end
  end

  -- Коннекшены, на которые ссылаются прототипы (tracked_connection у
  -- ачивок вида space-connection-distance-traveled-achievement), не
  -- удаляются: иначе загрузка падает 'assignID ... does not exist'.
  local keep_connections = {}
  for _, tbl in pairs(data.raw) do
    if type(tbl) == "table" then
      for _, proto in pairs(tbl) do
        if type(proto) == "table" and proto.tracked_connection then
          keep_connections[proto.tracked_connection] = true
        end
      end
    end
  end
  local kept_conns = {}
  for name, c in pairs(data.raw["space-connection"] or {}) do
    if keep_connections[name] then
      table.insert(kept_conns, c)
    end
  end
  data.raw["space-connection"] = {}
  for _, c in ipairs(kept_conns) do
    -- страховка: spawn_points сохранённых коннекшенов нормализуются тем же
    -- проходом (чужие моды могли оставить нестрого возрастающие distance)
    if c.asteroid_spawn_definitions then
      c.asteroid_spawn_definitions = conn_sanitize_spawn_defs(c.asteroid_spawn_definitions)
    end
    data.raw["space-connection"][c.name] = c
  end
  -- пары сохранённых коннекшенов: авто-дубли не создаются
  local kept_pairs = {}
  for _, c in ipairs(kept_conns) do
    local lo, hi = tostring(c.from), tostring(c.to)
    if hi < lo then lo, hi = hi, lo end
    kept_pairs[lo .. "|" .. hi] = true
  end

  -- локации со связью location<->location (ачивка/эксклюзив)
  local loc_linked = {}
  local function mark_loc_pair(f, t)
    local fb, tb = bodies[f], bodies[t]
    if fb and tb and fb.is_loc and tb.is_loc then
      loc_linked[f] = true
      loc_linked[t] = true
    end
  end
  for _, c in ipairs(kept_conns) do mark_loc_pair(tostring(c.from), tostring(c.to)) end
  for _, ec in ipairs(EXC) do
    if type(ec) == "table" then mark_loc_pair(ec.from, ec.to) end
  end

  local star_planets, locations = {}, {}
  for _, bd in ipairs(star_list) do
    if bd.is_loc then table.insert(locations, bd) else table.insert(star_planets, bd) end
  end

  -- === Эксклюзивные коннекшены: создаются первыми, пары блокируются ===
  local new_conns = {}
  local exclusive_count = 0
  for _, ec in ipairs(EXC) do
    if type(ec) == "table" and ec.from and ec.to
       and conn_find_location_proto(ec.from) and conn_find_location_proto(ec.to) then
      local fa, ta = tostring(ec.from), tostring(ec.to)
      local lo, hi = fa, ta
      if hi < lo then lo, hi = hi, lo end
      kept_pairs[lo .. "|" .. hi] = true
      local a, b = bodies[ec.from], bodies[ec.to]
      local len = tonumber(ec.length)
      if not (len and len > 0) then
        if a and b and a.x and b.x then
          local dx, dy = a.x - b.x, a.y - b.y
          len = math.sqrt(dx * dx + dy * dy) * CONN_KM_PER_UNIT
        else
          len = 15000
        end
      end
      local conn = {
        type = "space-connection",
        name = "space-map-rework-xconn-" .. lo .. "-" .. hi,
        subgroup = "planet-connections",
        from = fa,
        to = ta,
        order = "test-x-" .. lo,
        length = math.max(CONN_MIN_LENGTH, math.floor(len + 0.5)),
        icons = conn_build_icons(ec.from, ec.to),
      }
      if kept_spawn_defs then
        conn.asteroid_spawn_definitions = table.deepcopy(kept_spawn_defs)
      end
      table.insert(new_conns, conn)
      exclusive_count = exclusive_count + 1
    else
      log("[space-map-rework] xconn: ВНИМАНИЕ, запись пропущена (нет from/to"
        .. " или неизвестное тело — сверь имена): from=" .. tostring(ec and ec.from)
        .. ", to=" .. tostring(ec and ec.to))
    end
  end

  -- === Авто-рёбра ===
  local edges = {}
  local edge_have = {}
  local function add_auto(a, b)
    if not (a and b and a.x and b.x) then return end
    local lo, hi = a.name, b.name
    if hi < lo then lo, hi = hi, lo end
    local key = lo .. "|" .. hi
    if edge_have[key] or kept_pairs[key] then return end
    edge_have[key] = true
    table.insert(edges, {a, b})
  end

  -- планеты: DEPTH соседей в каждую сторону
  for i = 1, #star_planets do
    for d = 1, CONN_NEIGHBOR_DEPTH do
      if star_planets[i + d] then add_auto(star_planets[i], star_planets[i + d]) end
    end
  end
  -- луны -> к родителю
  for parent_name, list in pairs(by_parent) do
    local parent = bodies[parent_name]
    if parent then
      for _, m in ipairs(list) do add_auto(m, parent) end
    end
  end
  -- space-location: shattered-planet к планетам не подключается
  local CONN_SHATTERED_NAME = "shattered-planet"  -- ROUTE_SHATTERED_NAME (зеркало)
  -- есть ли у локации связь с планетой (авто/сохранённая/эксклюзивная)
  local function loc_has_planet_link(lname)
    for _, pair in ipairs(edges) do
      local a, b = pair[1], pair[2]
      if (a.name == lname and not b.is_loc) or (b.name == lname and not a.is_loc) then return true end
    end
    for pair_key in pairs(kept_pairs) do
      local f, t = string.match(pair_key, "^(.-)|(.+)$")
      local fb, tb = bodies[f], bodies[t]
      if (f == lname and tb and not tb.is_loc) or (t == lname and fb and not fb.is_loc) then return true end
    end
    return false
  end
  -- проход 1: крайняя свободная планета внутри орбиты локации
  local planet_taken = {}
  for _, loc in ipairs(locations) do
    if loc.name ~= CONN_SHATTERED_NAME and not loc_linked[loc.name] then
      local lr = loc.radius or 0
      local best = nil
      for _, p in ipairs(star_planets) do
        local pr = p.radius or 0
        if pr < lr and not planet_taken[p.name] then
          if not best or pr > (best.radius or 0) then best = p end
        end
      end
      if best then
        planet_taken[best.name] = true
        add_auto(loc, best)
      end
    end
  end
  -- проход 2: связи всё ещё нет -> ближайшая по радиусу планета
  for _, loc in ipairs(locations) do
    if loc.name ~= CONN_SHATTERED_NAME and not loc_has_planet_link(loc.name) then
      local lr = loc.radius or 0
      local best, bd = nil, nil
      for _, p in ipairs(star_planets) do
        local d = math.abs((p.radius or 0) - lr)
        if not bd or d < bd then bd, best = d, p end
      end
      if best then add_auto(loc, best) end
    end
  end

  -- === создание авто-коннекшенов ===
  for idx, pair in ipairs(edges) do
    local a, b = pair[1], pair[2]
    local lo, hi = a.name, b.name
    if hi < lo then lo, hi = hi, lo end
    local dx, dy = a.x - b.x, a.y - b.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local len = math.max(CONN_MIN_LENGTH, math.floor(dist * CONN_KM_PER_UNIT + 0.5))
    local conn = {
      type = "space-connection",
      name = "space-map-rework-route-" .. lo .. "-" .. hi,
      subgroup = "planet-connections",
      from = a.name,
      to = b.name,
      order = "test-" .. string.format("%03d", idx),
      length = len,
      -- icons обязательны в 2.1: автозаполнение space-age работает только
      -- при наличии поля icon у обоих концов
      icons = conn_build_icons(a.name, b.name),
    }
    if kept_spawn_defs then
      conn.asteroid_spawn_definitions = table.deepcopy(kept_spawn_defs)
    end
    table.insert(new_conns, conn)
  end
  if #new_conns > 0 then
    data:extend(new_conns)
  end
  log(string.format("[space-map-rework] space-connections: ванильные ОБНУЛЕНЫ, назначены свои: %d (планеты depth=%d + луны + локации по 1 соседу; эксклюзивных ручных: %d)%s",
    #new_conns, CONN_NEIGHBOR_DEPTH, exclusive_count,
    (#kept_conns > 0) and (", сохранено " .. #kept_conns .. " с ачивками") or ""))
end
