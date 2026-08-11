
факторио 2.1.14

# Кастомная Звездная Карта (SE Style) для Factorio 2.1 + Space Age

Этот мод представляет собой **первый этап** разработки мода в стиле **Space Exploration (SE)** на движке **Factorio 2.1 + Space Age (SA)**.

В соответствии с вашей задачей, на текущем этапе мод:
1. **Отключает стандартную (ванильную) космическую карту** Space Age, чтобы игрок не мог открыть ванильный Starmap.
2. **Заменяет ванильную кнопку «Космическая карта»** в верхнем левом меню своей собственной кнопкой (важно: не создаётся вторая лишняя кнопка рядом, а ванильная отключается, и на её место встаёт кастомная).
3. **Реализует кастомное GUI звездной системы** («поверхность с планетами: только иконки и звезда»), отображающее центральное светило, планеты на орбитах и статус орбитальных платформ (без возможности уничтожения).

---

## 📂 Структура файлов мода

```text
custom-starmap/
├── info.json                      # Метаданные мода (зависимости от base >= 2.0.0 и space-age >= 2.0.0)
├── data.lua                       # Регистрация Shortcut (кнопки в быстрой панели) и Custom Input (горячей клавиши)
├── data-final-fixes.lua           # Настройка скрытия ванильных space-location с ванильной карты (опционально)
├── control.lua                    # Отключение ванильной карты, создание заменяющей кнопки и обработка событий
├── scripts/
│   ├── star_system_data.lua       # Конфигурация звездной системы (Калидус, Наувис, Вулканус, Глеба и др.)
│   └── starmap_gui.lua            # Реализация кастомного интерфейса (GUI) с картой и панелью информации
└── locale/
    ├── ru/
    │   └── locale.cfg             # Русская локализация
    └── en/
        └── locale.cfg             # Английская локализация
```

---

## 🛠️ Как устроено отключение ванильной карты и замена кнопки

В **Factorio 2.1** разработчики (Bilka) добавили специальный API для управления доступностью ванильной космической карты:
- Метод `player.disable_space_map()` в `control.lua`: полностью запрещает игроку открытие стандартного ванильного Starmap и скрывает ванильную кнопку в левом верхнем углу (а также в удаленном виде / Remote View).
- В `data-final-fixes.lua` предусмотрен флаг `HIDE_VANILLA_STARMAP_LOCATIONS` (по умолчанию `false`, чтобы не ломать выбор планеты в окне ракеты до реализации полной логистической навигации SE). Если установить его в `true`, все ванильные прототипы `space-location` получат свойство `hidden = true` и полностью исчезнут из ванильного звездного интерфейса.
- Вместо ванильной кнопки мод создаёт в `player.gui.top` собственную кнопку `custom_starmap_top_btn` (★ Космическая карта — Звездная система). Нажатие на неё (или использование шортката в панели шорткатов / комбинации клавиш `SHIFT + M`) открывает **кастомное GUI**.

---

## 🎨 Особенности кастомного GUI

Окно кастомной карты (`custom_se_starmap_frame`) построено с использованием стандартных визуальных стилей Factorio и содержит две основные области:

1. **Левая область — Поверхность звездной системы (Карта):**
   - **Центральная звезда (`Калидус / Sol`)**: отображается в центре в виде большой интерактивной иконки.
   - **Орбитальная сетка планет**: вокруг звезды расположены иконки всех небесных тел (`Наувис`, `Вулканус`, `Глеба`, `Фулгора`, `Аквило`, астероидный пояс, а также пример кастомной планеты `Анемоне`).
   - Для каждой планеты отображается подпись и статус орбиты: **«Орбита: платформа»** (что соответствует концепции орбитальной платформы без разрушения).
   - Если иконка какого-либо мода отсутствует в сборке, GUI автоматически использует fallback-спрайты (`item/satellite`), предотвращая любые вылеты (crash).

2. **Правая область — Информационная панель и управление:**
   - При клике на любую планету или звезду панель динамически обновляется.
   - Отображает: тип объекта, расстояние от звезды (в а.е.), статус орбитальной платформы (`«Орбита через платформу (без разрушения)»`) и подробное описание.
   - Содержит кнопки-заготовки для будущего перехода к поверхности планеты или орбитальной платформе (`«Перейти к поверхности»`, `«Открыть орбитальную платформу»`).

---

## 🚀 Как установить и проверить в игре

1. Скопируйте папку `custom-starmap` в вашу директорию модов Factorio:
   - **Windows:** `%appdata%\Factorio\mods\`
   - **Linux:** `~/.factorio/mods/`
2. Запустите Factorio 2.0 / 2.1 с включенным модом **Space Age** (`space-age`).
3. В игре обратите внимание на верхнюю левую панель:
   - Ванильная кнопка космической карты отключена.
   - На её месте отображается новая кнопка мода **«★ Космическая карта»**.
4. Нажмите на кнопку (или нажмите `SHIFT + M`), чтобы открыть кастомное меню звездной системы.

---

## 🔮 Дальнейшие шаги разработки (План интеграции в стиле SE)

Для превращения этого GUI в полноценный глобальный мод наподобие **Space Exploration**:
1. **Генерация поверхностей планет:** в `control.lua` при первом нажатии «Перейти к поверхности» использовать `game.create_surface(planet_id, custom_map_gen_settings)`, подключая кастомные шумы (`noise-expression`) и параметры генераторной сетки.
2. **Орбитальные платформы без разрушения:** создавать для каждой планеты фиксированную космическую платформу (`LuaSpacePlatform`) с отключенным уроном от астероидов или защитным куполом (через скрипт или настройки прототипа), которая служит постоянной «Орбитой» планеты.
3. **Синхронизация с ракетным силосом:** перехватывать событие отправки ракеты и направлять капсулу на выбранную в кастомном GUI поверхность/орбиту.



-- settings.lua - общие настройки масштаба, размера, дистанций орбит, скорости
data:extend({
  -- Масштаб орбит
  {
    type = "double-setting",
    name = "custom-se-starmap-star-scale",
    setting_type = "startup",
    default_value = 1.0,
    minimum_value = 0.1,
    maximum_value = 30,
    order = "a1",
    localised_name = "Масштаб орбит от звезды (radius = (distance+bonus)*scale)",
    localised_description = "Множитель для дистанции от звезды. Если дистанция это радиус, ставь 1."
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-sat-scale",
    setting_type = "startup",
    default_value = 1.0,
    minimum_value = 0.1,
    maximum_value = 30,
    order = "a2",
    localised_name = "Масштаб орбит спутников",
    localised_description = "Множитель для дистанции луны от родителя"
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-distance-bonus",
    setting_type = "startup",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 100,
    order = "a3",
    localised_name = "Бонус к дистанции общий (+N)",
    localised_description = "Старый общий бонус, оставлен для совместимости. Используй раздельные ниже если нужно."
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-star-distance-bonus",
    setting_type = "startup",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 100,
    order = "a3-b",
    localised_name = "Бонус к дистанции звездных орбит (+N) отдельно",
    localised_description = "Прибавляется только к орбитам вокруг звезды. Отдельная настройка чтобы уменьшить дальность."
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-sat-distance-bonus",
    setting_type = "startup",
    default_value = 5,
    minimum_value = 0,
    maximum_value = 100,
    order = "a3-c",
    localised_name = "Бонус к дистанции лун (+N) отдельно",
    localised_description = "Прибавляется только к орбитам лун вокруг родителя"
  },
  -- Размер иконок
  {
    type = "double-setting",
    name = "custom-se-starmap-planet-size",
    setting_type = "startup",
    default_value = 0.92,
    minimum_value = 0.1,
    maximum_value = 5,
    order = "b1",
    localised_name = "Базовый размер иконок планет",
    localised_description = "Базовый размер + magnitude зависимость"
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-planet-size-bonus",
    setting_type = "startup",
    default_value = 0.5,
    minimum_value = 0,
    maximum_value = 3,
    order = "b2",
    localised_name = "Бонус к размеру планет (+0.5)",
    localised_description = "Добавляется ко всем размерам планет"
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-sat-size-bonus",
    setting_type = "startup",
    default_value = 0.3,
    minimum_value = 0,
    maximum_value = 3,
    order = "b3",
    localised_name = "Бонус к размеру спутников",
    localised_description = "Доп. размер для лун"
  },
  -- Минимальное расстояние между орбитами
  {
    type = "double-setting",
    name = "custom-se-starmap-min-orbit-gap",
    setting_type = "startup",
    default_value = 3,
    minimum_value = 0,
    maximum_value = 20,
    order = "c1",
    localised_name = "Мин. расстояние между орбитами звездных планет",
    localised_description = "Кроме лун"
  },
  -- Скорости вращения отдельно
  {
    type = "double-setting",
    name = "custom-se-starmap-star-orbit-speed",
    setting_type = "startup",
    default_value = 0.00006,
    minimum_value = 0,
    maximum_value = 0.01,
    order = "d1",
    localised_name = "Скорость вращения планет вокруг звезды",
    localised_description = "Угловая скорость rad/tick"
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-moon-orbit-speed",
    setting_type = "startup",
    default_value = 0.0003,
    minimum_value = 0,
    maximum_value = 0.02,
    order = "d2",
    localised_name = "Скорость вращения лун вокруг родителя",
    localised_description = "Отдельная скорость для спутников"
  },
  -- Радиусы орбит отдельно (чтобы уменьшить дальность)
  {
    type = "int-setting",
    name = "custom-se-starmap-max-star-orbit",
    setting_type = "startup",
    default_value = 400,
    minimum_value = 50,
    maximum_value = 1000,
    order = "e1",
    localised_name = "Макс радиус орбиты звезды",
    localised_description = "Чтобы орбиты не улетали далеко"
  },
  {
    type = "int-setting",
    name = "custom-se-starmap-max-moon-orbit",
    setting_type = "startup",
    default_value = 60,
    minimum_value = 5,
    maximum_value = 200,
    order = "e2",
    localised_name = "Макс радиус орбиты луны",
    localised_description = "Макс радиус луны вокруг родителя"
  },
  {
    type = "int-setting",
    name = "custom-se-starmap-sun-size",
    setting_type = "startup",
    default_value = 7,
    minimum_value = 1,
    maximum_value = 50,
    order = "f1",
    localised_name = "Размер солнца (Калидус)",
    localised_description = "Радиус жёлтого шара в центре"
  }
})


-- data.lua - базовые прототипы для SE-style starmap
-- Factorio 2.1.14, SA
-- Только хотбар скрывается, без лишних кнопок, поверхность 1000x1000, empty-space без автокоррекции

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

-- Базовый маркер планеты - невидим, неуязвим, для наведения
-- render_layer НЕ задаём намеренно
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
    selection_box = {{-1.4, -1.4}, {1.4, 1.4}},
    collision_mask = {layers = {}},
    selectable_in_game = true,
    max_health = 10000000,
    picture = {
      filename = "__core__/graphics/empty.png",
      width = 1,
      height = 1
    },
    -- используем гарантированно существующую иконку
    icon = "__core__/graphics/empty.png",
    icon_size = 1,
    subgroup = "other",
    order = "z-custom-se-marker"
  }
})

local base_marker = data.raw["simple-entity"]["custom-se-planet-marker"]
if base_marker then
  base_marker.render_layer = nil
  base_marker.selectable_in_game = true
end

-- Тайл космоса без автокоррекции для заливки поверхности
-- Требование: 100% empty-space с отключенной автокоррекцией
if data.raw.tile["empty-space"] then
  local empty = table.deepcopy(data.raw.tile["empty-space"])
  empty.name = "custom-se-empty-space-no-correct"
  empty.autoplace = nil
  empty.next_direction = nil
  empty.transition_merges_with_tile = nil
  empty.decorative_removal_probability = 1
  empty.allowed_neighbors = nil
  data:extend({empty})
end

-- Спрайт солнца НЕ создаём как отдельный файл, используем ванильный utility/starmap_star
-- (data.raw['utility-sprites']['default'].starmap_star) — официальная текстура солнца SA
-- В control.lua рендер: sprite="utility/starmap_star" (Калидус Sol)


-- data-final-fixes.lua
-- Полное ванильное описание как на фото, серые орбиты в control, масштаб по data, прозрачный прототип

local function truncate(s, limit)
  limit = limit or 180
  s = tostring(s)
  if #s > limit then return string.sub(s,1,limit-3).."..." end
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
  if string.find(lower, "wind") then return "Скорость верта" end
  if string.find(lower, "asteroid") then return "Asteroid Density" end
  if string.find(lower, "rocket") then return "Rocket parts" end
  if string.find(lower, "evolution") then return "Фактор эволюции" end
  return key:gsub("-", " "):gsub("_"," ")
end

local function format_prop_value(key, value)
  if type(value) ~= "number" then return truncate(value, 100) end
  local lower = string.lower(key)
  if lower=="solar-power" or string.find(lower,"magnetic") then
    if value <=5 then return string.format("%.0f %%", value*100) end
    return string.format("%.0f %%", value)
  end
  if lower=="pressure" then return string.format("%.0f гПа", value) end
  if lower=="gravity" then return string.format("%.2f м/с²", value) end
  if lower=="day-night-ratio" then return string.format("%d минут", math.floor(value*6+0.5)) end
  if lower=="temperature" then return string.format("%d K", math.floor(value)) end
  if string.find(lower,"radiation") then return string.format("%d Бк", value) end
  if string.find(lower,"gas") then return string.format("%d %%", value*100) end
  if string.find(lower,"drone") then return "×"..value end
  if string.find(lower,"crystall") or string.find(lower,"dust") then return string.format("%d %%", value) end
  if string.find(lower,"wind") then return string.format("%d км/ч", value) end
  if string.find(lower,"asteroid") then return string.format("%d ppb", value) end
  if string.find(lower,"rocket") then return "×"..value end
  if string.find(lower,"evolution") then return string.format("%.4f", value) end
  if value<10 and value~=math.floor(value) then return string.format("%.2f", value) end
  return tostring(value)
end

local function build_localised_description(proto, planet_proto)
  local parts = {""}
  local function add_line(k,v)
    if v==nil or v=="" then return end
    -- каждый токен <200
    local kk = truncate(k, 80)
    local vv = truncate(v, 180)
    table.insert(parts, { "", kk..": ", vv, "\n" })
  end
  local function add_header(t)
    table.insert(parts, { "", "\n[font=default-bold]"..truncate(t,80).."[/font]\n" })
  end

  -- Ванильные surface_properties как на фото
  local sp = nil
  if planet_proto and planet_proto.surface_properties then sp=planet_proto.surface_properties
  elseif proto.surface_properties then sp=proto.surface_properties end

  if sp then
    for k,v in pairs(sp) do
      if type(k)=="string" then
        add_line(translate_prop_key(k), format_prop_value(k,v))
      end
    end
  end
  if proto.gravity then add_line("Гравитация", format_prop_value("gravity", proto.gravity)) end
  if proto.pressure then add_line("Давление", format_prop_value("pressure", proto.pressure)) end

  -- Ресурсы как иконки "Содержимое:" как на фото
  local function collect_resources(p)
    local res={}
    if not p or not p.map_gen_settings then return res end
    local mgs=p.map_gen_settings
    if mgs.autoplace_controls then
      for name,_ in pairs(mgs.autoplace_controls) do
        if name~="water" and not string.find(name,"cliff") and name~="starting_area" then table.insert(res,name) if #res>=12 then break end end
      end
    end
    if mgs.autoplace_settings and mgs.autoplace_settings.entity and mgs.autoplace_settings.entity.settings then
      for name,_ in pairs(mgs.autoplace_settings.entity.settings) do table.insert(res,name) if #res>=12 then break end end
    end
    return res
  end
  local all_res={}
  for _,n in ipairs(collect_resources(proto)) do table.insert(all_res,n) end
  for _,n in ipairs(collect_resources(planet_proto)) do table.insert(all_res,n) end
  local uniq, uniq_list = {}, {}
  for _,r in ipairs(all_res) do if not uniq[r] then uniq[r]=true table.insert(uniq_list,r) if #uniq_list>=12 then break end end end
  if #uniq_list>0 then
    add_header("Содержимое")
    -- иконки как на фото: показываем как [item=...] — в локал айдее это рич-текст
    local icons={}
    for _,rname in ipairs(uniq_list) do
      table.insert(icons, "[item="..rname.."]")
    end
    -- Разбиваем на куски <180 символов
    local line = table.concat(icons, " ")
    -- если длиннее 180, режем на несколько строк
    while #line>0 do
      local chunk = string.sub(line,1,180)
      -- найдём последний пробел чтобы не резать иконку
      if #line>180 then
        local last_space = chunk:match("^.*() ")
        if last_space then chunk = string.sub(line,1,last_space-1) end
      end
      table.insert(parts, { "", chunk, "\n" })
      line = string.sub(line, #chunk+1)
      line = line:gsub("^%s+","")
    end
  end

  if proto.solar_power_in_space then
    add_line("Солнечная энергия в космосе", format_prop_value("solar-power", proto.solar_power_in_space/100))
    -- solar_power_in_space в прототипе обычно в ваттах? Для красоты показываем как %
    -- но используем уже готовый формат
  end

  -- Ванильное описание из прототипа как короткий ключ
  if proto.localised_description then
    table.insert(parts, { "", "\n", proto.localised_description, "\n" })
  elseif planet_proto and planet_proto.localised_description then
    table.insert(parts, { "", "\n", planet_proto.localised_description, "\n" })
  end

  return parts
end

local space_locations={}
if data.raw["space-location"] then
  for name,proto in pairs(data.raw["space-location"]) do
    if not string.find(string.lower(name),"anemone") then space_locations[name]=proto end
  end
end
if data.raw["planet"] then
  for name,proto in pairs(data.raw["planet"]) do
    if not string.find(string.lower(name),"anemone") then
      if not space_locations[name] then space_locations[name]=proto end
    end
  end
end

for name,proto in pairs(space_locations) do
  local marker_name="custom-se-marker-"..name
  if not data.raw["simple-entity"][marker_name] then
    local base
    if data.raw["simple-entity"]["custom-se-planet-marker"] then
      base=table.deepcopy(data.raw["simple-entity"]["custom-se-planet-marker"])
    else
      base={
        type="simple-entity",
        name="custom-se-planet-marker",
        flags={"placeable-off-grid","not-blueprintable","not-deconstructable"},
        collision_box={{-0.1,-0.1},{0.1,0.1}},
        selection_box={{-1.4,-1.4},{1.4,1.4}},
        collision_mask={layers={}},
        picture={filename="__core__/graphics/empty.png", width=1, height=1}
      }
    end
    base.name=marker_name
    -- Иконка для тултипа берётся из прототипа, но картинка сущности должна быть пустой чтобы не было дубликата "большая полупрозрачная копия" у маленьких планет
    if proto.icons then
      base.icons=table.deepcopy(proto.icons)
      base.icon=nil
      base.icon_size=nil
    elseif proto.icon then
      base.icon=proto.icon
      base.icon_size=proto.icon_size or 64
      base.icons=nil
    end
    base.picture={
      filename="__core__/graphics/empty.png",
      width=1, height=1
    }
    base.localised_name=proto.localised_name or {"space-location-name."..name}
    local planet_proto=data.raw["planet"] and data.raw["planet"][name] or nil
    base.localised_description=build_localised_description(proto, planet_proto)
    base.render_layer=nil
    base.max_health=10000000
    base.flags={"placeable-off-grid","not-blueprintable","not-deconstructable","not-flammable","not-repairable"}
    base.selectable_in_game=true
    base.collision_mask={layers={}}
    base.hidden=false
    data:extend({base})
  end
end

local count=0 for _ in pairs(space_locations) do count=count+1 end
log("[custom-se-starmap] markers "..count.." vanilla-like desc with icons, gray orbits, reduced scale")

-- === Сохраняем орбиты PlanetsLib для runtime (чтобы видеть привязку к другой планете) ===
-- Собираем все orbit данные из data.raw (они уже есть благодаря PlanetsLib.ensure_all_locations_have_orbits)
local orbits_for_runtime = {}
for type_name in pairs({["planet"]=true, ["space-location"]=true}) do
  if data.raw[type_name] then
    for name, proto in pairs(data.raw[type_name]) do
      if proto.orbit and proto.orbit.parent and proto.orbit.parent.name then
        orbits_for_runtime[name] = {
          parent = proto.orbit.parent.name,
          parent_type = proto.orbit.parent.type,
          distance = proto.orbit.distance,
          orientation = proto.orbit.orientation
        }
      end
    end
  end
end
-- Сохраняем в mod-data чтобы control.lua мог прочитать через prototypes.mod-data
data:extend{
  {
    type = "mod-data",
    name = "custom-se-starmap-orbits",
    data = orbits_for_runtime
  }
}
log("[custom-se-starmap] saved "..(function() local c=0 for _ in pairs(orbits_for_runtime) do c=c+1 end return c end)().." orbits for runtime (PlanetsLib compat)")

-- Дополнительно пытаемся записать файл control/generated_orbits.lua для прямого require в control (более надёжный способ)
local function write_orbit_file(orbits)
  local content = "-- Auto-generated orbits from data-final-fixes\nreturn {\n"
  for name, d in pairs(orbits) do
    content = content .. string.format("  [\"%s\"] = {parent=\"%s\", parent_type=\"%s\", distance=%s, orientation=%s},\n",
      name, d.parent, d.parent_type or "planet", tostring(d.distance), tostring(d.orientation))
  end
  content = content .. "}\n"
  -- Попытка записи в несколько возможных путей
  local paths = {
    "__custom-se-starmap__/control/generated_orbits.lua",
    "control/generated_orbits.lua",
    "__custom-se-starmap__/control/generated_orbits.lua"
  }
  for _, p in ipairs(paths) do
    local ok, err = pcall(function()
      local f = io.open(p, "w")
      if f then f:write(content) f:close() return true end
      return false
    end)
    if ok then log("[custom-se-starmap] wrote orbit file to "..p) break end
  end
end
pcall(write_orbit_file, orbits_for_runtime)

-- === Общие настройки масштаба и размера планет (settings.lua будет читать) ===
-- Создаём дефолтные настройки если их нет (для совместимости)


-- control.lua - почти пустой, логика разделена на модули control/
-- Factorio 2.1.14 + SA, фикс is_valid: в 2.1 нет rendering.is_valid, только LuaRenderObject.valid

require("control.constants")
require("control.rendering")
require("control.surface")
require("control.starsystem")
require("control.orbits")
require("control.player")
require("control.gui")
require("control.events")

log("[custom-se-starmap] control.lua loaded (modular) - yellow sun, transparent orbits, icon on top, no immortal label, vanilla desc")


-- control/constants.lua
local function get_setting(name, default)
  local ok, val = pcall(function() return settings.startup[name].value end)
  if ok and val ~= nil then return val end
  return default
end

SURFACE_NAME = "custom-se-starmap-surface"
MAP_LIMIT = 500

-- Скорости отдельно
ORBITAL_SPEED = get_setting("custom-se-starmap-star-orbit-speed", 0.0003)
MOON_ORBITAL_SPEED = get_setting("custom-se-starmap-moon-orbit-speed", 0.0009)

ORBIT_COLOR = {r=0.75, g=0.75, b=0.75, a=0.65} -- серые жирные для звезд
MOON_ORBIT_COLOR = {r=0.40, g=0.75, b=1.0, a=0.58} -- голубая для лун по ТЗ другой цвет

ORBIT_WIDTH = 4
MOON_ORBIT_WIDTH = 2

STAR_RADIUS = get_setting("custom-se-starmap-sun-size", 7)
MIN_ORBIT_RADIUS = 0
MAX_ORBIT_RADIUS = get_setting("custom-se-starmap-max-star-orbit", 400)
SAT_MIN_RADIUS = 0
SAT_MAX_RADIUS = get_setting("custom-se-starmap-max-moon-orbit", 60)

STAR_DISTANCE_SCALE = get_setting("custom-se-starmap-star-scale", 1)
SAT_DISTANCE_SCALE = get_setting("custom-se-starmap-sat-scale", 1)

-- Бонус к дистанции отдельно
DISTANCE_BONUS = get_setting("custom-se-starmap-distance-bonus", 10) -- старый общий
STAR_DISTANCE_BONUS = get_setting("custom-se-starmap-star-distance-bonus", DISTANCE_BONUS)
SAT_DISTANCE_BONUS = get_setting("custom-se-starmap-sat-distance-bonus", 0)

PLANET_SIZE_BASE = get_setting("custom-se-starmap-planet-size", 0.6)
PLANET_SIZE_BONUS = get_setting("custom-se-starmap-planet-size-bonus", 0.5)
SAT_SIZE_BONUS = get_setting("custom-se-starmap-sat-size-bonus", 0.3)
MIN_ORBIT_GAP = get_setting("custom-se-starmap-min-orbit-gap", 3)



-- control/events.lua
-- Регистрация всех событий, чтобы control.lua был почти пустым

script.on_init(function()
  storage.planets = {}
  storage.star = {}
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

script.on_event(defines.events.on_tick, function(e)
  if e.tick % 2 == 0 then update_orbits() end
  if e.tick % 30 == 0 then
    for _, p in pairs(game.players) do update_player_view_settings(p) end
  end
  -- всегда прогружать поверхность как радаром по ТЗ
  if e.tick % 180 == 0 then
    local surf = game.surfaces[SURFACE_NAME]
    if surf then
      pcall(function() chart_surface_as_radar(surf) end)
    end
  end
end)

-- Привязка к исследованиям: если исследована планета, перерисовываем орбиты
script.on_event(defines.events.on_research_finished, function(e)
  rebuild_star_system()
end)
script.on_event(defines.events.on_research_reversed, function(e)
  rebuild_star_system()
end)
script.on_event(defines.events.on_technology_effects_reset, function(e)
  rebuild_star_system()
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
  local cp = e.cursor_position or (p and p.position)
  if p and p.surface.name ~= SURFACE_NAME then return end
  handle_planet_click(p, cp)
end)

script.on_event("custom-se-right-click", function(e)
  local p = game.players[e.player_index]
  local cp = e.cursor_position or (p and p.position)
  if p and p.surface.name ~= SURFACE_NAME then return end
  handle_planet_click(p, cp)
end)

commands.add_command("starmap", "Телепорт на SE-карту", function(e)
  local p = game.players[e.player_index]
  if p then teleport_to_starmap(p, false) end
end)

commands.add_command("starmap-rebuild", "Пересобрать систему", function(e)
  rebuild_star_system()
  local p = e.player_index and game.players[e.player_index] or nil
  if p then p.print("[custom-se-starmap] Пересобрано: "..(#storage.planets).." тел") end
end)

commands.add_command("starmap-back", "Вернуться", function(e)
  local p = game.players[e.player_index]
  if p and storage.player_prev and storage.player_prev[p.index] then teleport_to_starmap(p, true) end
end)

if defines.events.on_player_controller_changed then
  script.on_event(defines.events.on_player_controller_changed, function(e)
    local p = game.players[e.player_index]
    if p then update_player_view_settings(p) end
  end)
end


-- Auto-generated by data-final-fixes.lua, contains PlanetsLib orbits
-- Format: [planet_name] = {parent="nauvis", parent_type="planet", distance=1.6, orientation=0.75}
return {
  -- Example:
  -- ["muluna"] = {parent="nauvis", parent_type="planet", distance=1.6, orientation=0.75},
  -- ["cerys"] = {parent="fulgora", parent_type="planet", distance=1.39, orientation=0.45},
}


-- control/gui.lua
-- Карточки характеристик SHIFT+I, умное позиционирование слева/справа от звезды, и клик ЛКМ → Remote View

function toggle_info_cards(player)
  local surface = game.surfaces[SURFACE_NAME]
  if not surface then return end
  storage.info_visible = not storage.info_visible
  if storage.info_visible then
    for _, planet in ipairs(storage.planets) do
      r_destroy(planet.card_render_id)
      local x = planet.position.x
      local y = planet.position.y
      local offset_x = (x>=0) and 5 or -5
      local align = (x>=0) and "left" or "right"
      local card_text = build_card_text(planet.prototype_name)
      local card_id = rendering.draw_text{
        text=card_text, surface=surface, target={x+offset_x,y},
        color={r=0.92,g=0.92,b=0.92,a=0.9}, scale=0.68, alignment=align
      }
      planet.card_render_id = card_id
      planet.last_side = (x>=0) and "right" or "left"
      r_bring_front(card_id)
    end
    if player then player.print("[custom-se-starmap] Карточки (условия+ресурсы): ВКЛ") end
  else
    for _, planet in ipairs(storage.planets) do
      r_destroy(planet.card_render_id)
      planet.card_render_id = nil
      planet.last_side = nil
    end
    if player then player.print("[custom-se-starmap] Карточки: ВЫКЛ") end
  end
end

function handle_planet_click(player, cursor_pos)
  if not player or not storage.planets then return end
  local surface = game.surfaces[SURFACE_NAME]
  if not surface then return end
  if player.surface.name ~= SURFACE_NAME then
    if not (player.physical_surface and player.physical_surface.name == SURFACE_NAME) then return end
  end
  local selected = player.selected
  local target_planet = nil
  if selected and selected.valid then
    for _, planet in ipairs(storage.planets) do
      if planet.entity and planet.entity.valid then
        if planet.entity == selected or planet.entity.unit_number == selected.unit_number then target_planet = planet break end
      end
      if string.find(selected.name or "", planet.prototype_name) then target_planet = planet break end
    end
  end
  if not target_planet and cursor_pos then
    local cx = cursor_pos.x or cursor_pos[1]
    local cy = cursor_pos.y or cursor_pos[2]
    local best = 3.0
    for _, planet in ipairs(storage.planets) do
      local dx = planet.position.x - cx
      local dy = planet.position.y - cy
      local d = math.sqrt(dx*dx+dy*dy)
      if d < best then best = d target_planet = planet end
    end
  end
  if not target_planet then
    local px = player.position.x
    local py = player.position.y
    local best = 4.0
    for _, planet in ipairs(storage.planets) do
      local dx = planet.position.x - px
      local dy = planet.position.y - py
      local d = math.sqrt(dx*dx+dy*dy)
      if d < best then best = d target_planet = planet end
    end
  end
  if not target_planet then return end
  local planet_name = target_planet.prototype_name
  local target_surface = nil
  local found = false
  if game.planets and game.planets[planet_name] then
    local lp = game.planets[planet_name]
    if lp.surface and lp.surface.valid then target_surface = lp.surface found = true
    else local ok, surf = pcall(function() return lp.create_surface() end) if ok and surf then target_surface = surf found = true end end
  end
  if not found and game.surfaces[planet_name] and game.surfaces[planet_name].valid then target_surface = game.surfaces[planet_name] found = true end
  if not found and (planet_name == "solar-system-edge" or planet_name == "shattered-planet") then
    player.print("[custom-se-starmap] "..planet_name.." — без поверхности")
    local nauvis = game.surfaces["nauvis"] target_surface = nauvis found = (nauvis ~= nil)
  end
  if found and target_surface then
    player.game_view_settings.show_quickbar = true
    player.set_controller{type=defines.controllers.remote, surface=target_surface, position={0,0}}
    player.print("[custom-se-starmap] Remote View → "..planet_name)
  else player.print("[custom-se-starmap] Нет поверхности для "..planet_name) end
end

-- control/orbits.lua
-- Медленное вращение, иконки поворачиваются, спутники PlanetsLib вращаются вокруг родителя, иконка всегда над серой жирной орбитой

function update_orbits()
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not storage.planets then return end
  for _, planet in ipairs(storage.planets) do
    local speed = planet.parent_name and (MOON_ORBITAL_SPEED or ORBITAL_SPEED*5) or ORBITAL_SPEED
    planet.angle = planet.angle + speed
    if planet.angle > math.pi*2 then planet.angle = planet.angle - math.pi*2 end

    local x, y
    if planet.parent_name then
      local parent = storage.planet_by_name and storage.planet_by_name[planet.parent_name]
      if parent and parent.position then
        if r_valid(planet.orbit_id) then
          r_set_target(planet.orbit_id, {x=parent.position.x, y=parent.position.y})
          r_move_back(planet.orbit_id)
        end
        x = parent.position.x + math.cos(planet.angle) * planet.orbit_radius
        y = parent.position.y + math.sin(planet.angle) * planet.orbit_radius
      else
        x = math.cos(planet.angle) * planet.orbit_radius
        y = math.sin(planet.angle) * planet.orbit_radius
      end
    else
      x = math.cos(planet.angle) * planet.orbit_radius
      y = math.sin(planet.angle) * planet.orbit_radius
    end
    planet.position = {x=x, y=y}

    r_set_target(planet.sprite_id, {x=x, y=y})
    r_set_target(planet.cover_id, {x=x, y=y})
    r_set_target(planet.name_text_id, {x=x, y=y-1.8})
    if r_valid(planet.sprite_id) then
      pcall(function() planet.sprite_id.orientation = planet.angle / (2*math.pi) end)
    end
    if planet.entity and planet.entity.valid then planet.entity.teleport({x,y}) end

    if planet.card_render_id and r_valid(planet.card_render_id) then
      local offset_x = (x>=0) and 4 or -4
      local current_side = (x>=0) and "right" or "left"
      if planet.last_side and planet.last_side ~= current_side then
        r_destroy(planet.card_render_id)
        local align = (current_side=="right") and "left" or "right"
        local card_text = build_card_text(planet.prototype_name)
        local new_id = rendering.draw_text{
          text=card_text, surface=surface, target={x+offset_x,y},
          color={r=0.92,g=0.92,b=0.92,a=1}, scale=0.6, alignment=align
        }
        planet.card_render_id = new_id
        r_bring_front(new_id)
      else
        r_set_target(planet.card_render_id, {x=x+offset_x, y=y})
      end
      planet.last_side = current_side
    end

    r_move_back(planet.orbit_id)
    r_bring_front(planet.cover_id)
    r_bring_front(planet.sprite_id)
    r_bring_front(planet.name_text_id)
    if planet.card_render_id then r_bring_front(planet.card_render_id) end
  end
end


-- control/player.lua
-- Скрытие только хотбара, телепорт, дебаг показаний

function update_player_view_settings(player)
  if not player or not player.valid then return end
  local is_on_starmap = false
  if player.controller_type == defines.controllers.character then
    if player.surface and player.surface.name == SURFACE_NAME then is_on_starmap = true end
  elseif player.controller_type == defines.controllers.remote or player.controller_type == defines.controllers.god then
    if player.physical_surface and player.physical_surface.name == SURFACE_NAME then is_on_starmap = false
    else if player.surface and player.surface.name == SURFACE_NAME then is_on_starmap = true end end
  end
  if is_on_starmap then player.game_view_settings.show_quickbar = false
  else if player.game_view_settings.show_quickbar == false then player.game_view_settings.show_quickbar = true end end
end

function teleport_to_starmap(player, return_if_already)
  if not player or not player.valid then return end
  local surface = get_or_create_surface()
  if not surface then return end
  if not storage.planets or #storage.planets == 0 then rebuild_star_system() end
  storage.player_prev = storage.player_prev or {}
  if player.surface.name == SURFACE_NAME and return_if_already then
    local prev = storage.player_prev[player.index]
    if prev and prev.surface and game.surfaces[prev.surface] then
      if player.controller_type == defines.controllers.character and player.character then
        player.teleport(prev.position, game.surfaces[prev.surface])
      else
        player.set_controller{type=defines.controllers.character, character=player.character}
        if player.character then player.teleport(prev.position, game.surfaces[prev.surface]) end
      end
      player.print({"", "[custom-se-starmap] Возврат на ", prev.surface})
      update_player_view_settings(player) return
    else
      local nauvis = game.surfaces["nauvis"]
      if nauvis then player.teleport({0,0}, nauvis) player.print("[custom-se-starmap] Возврат на Nauvis") end
      update_player_view_settings(player) return
    end
  end
  storage.player_prev[player.index] = {surface=player.surface.name, position={x=player.position.x, y=player.position.y}}
  if player.controller_type == defines.controllers.remote then
    if player.exit_remote_view then player.exit_remote_view() end
    if player.character and player.character.valid then
      player.set_controller{type=defines.controllers.character, character=player.character}
      player.teleport({0,0}, surface)
    else player.set_controller{type=defines.controllers.remote, surface=surface, position={0,0}} end
  else
    if player.controller_type == defines.controllers.god or player.controller_type == defines.controllers.editor then player.teleport({0,0}, surface)
    else if player.character and player.character.valid then player.teleport({0,0}, surface)
    else player.set_controller{type=defines.controllers.remote, surface=surface, position={0,0}} end end
  end
  player.game_view_settings.show_quickbar = false
  player.print("[custom-se-starmap] Калидус Sol — SHIFT+M возврат, SHIFT+I инфо, ПКМ → Remote View")
  -- ДЕБАГ по просьбе: выводим показания планет и расстояния + привязка к объекту
  if storage.planets then
    player.print("[DEBUG] Всего тел: "..#storage.planets.." | STAR_SCALE="..tostring(STAR_DISTANCE_SCALE).." SAT_SCALE="..tostring(SAT_DISTANCE_SCALE).." radius=distance*scale")
    for i, pl in ipairs(storage.planets) do
      local raw_od = pl.raw_orbit_dist or -1
      local raw_pd = pl.raw_proto_dist or -1
      local ptype = pl.parent_type or "star"
      if not pl.parent_name then ptype="star" end
      player.print(string.format("[%d] %s | dist=%.3f (raw_orbit=%.3f raw_proto=%.3f) radius=%.1f parent=%s<%s> mag=%.2f ang=%.2f",
        i, pl.name, pl.distance or 0, raw_od, raw_pd, pl.orbit_radius or 0, pl.parent_name or "star", ptype, pl.magnitude or 0, pl.angle or 0))
      if i>=40 then
        player.print("... и ещё "..(#storage.planets-40).." тел")
        break
      end
    end
  end
end


-- control/rendering.lua
-- Хелперы Factorio 2.1 без rendering.is_valid

function r_valid(obj)
  if not obj then return false end
  local ok, v = pcall(function() return obj.valid end)
  if ok then return v == true end
  return false
end

function r_destroy(obj)
  if not obj or not r_valid(obj) then return end
  local ok1 = pcall(function() obj:destroy() end)
  if not ok1 then pcall(function() obj.destroy(obj) end) end
end

function r_set_target(obj, pos)
  if not r_valid(obj) then return end
  pcall(function() obj.target = pos end)
end

function r_bring_front(obj)
  if not r_valid(obj) then return end
  pcall(function() obj:bring_to_front() end)
  pcall(function() obj.bring_to_front(obj) end)
end

function r_move_back(obj)
  if not r_valid(obj) then return end
  pcall(function() obj:move_to_back() end)
  pcall(function() obj.move_to_back(obj) end)
end


-- control/surface.lua
-- 1000x1000 empty-space, out-of-map, всегда прогружена как радаром

function get_or_create_surface()
  local surface = game.surfaces[SURFACE_NAME]
  if surface then return surface end

  local mgs = {
    width = 1000, height = 1000,
    default_enable_all_autoplace_controls = false,
    autoplace_controls = {},
    autoplace_settings = { tile={settings={}}, entity={settings={}}, decorative={settings={}} },
    property_expression_names = { cliffiness="0", cliff_elevation="0" },
    cliff_settings = { cliff_elevation_0=0, cliff_elevation_interval=0, richness=0 },
    starting_area="none", peaceful_mode=true, seed=123456
  }

  surface = game.create_surface(SURFACE_NAME, mgs)
  if surface then
    surface.freeze_daytime=true
    surface.daytime=0.5 -- вечный день по ТЗ
    surface.brightness_visual_weights={r=1,g=1,b=1}
    surface.min_brightness=1.0 -- ярко как днём
    surface.show_clouds=false
  end
  -- сразу зачартить и прогрузить чанки как радаром
  if surface then chart_surface_as_radar(surface) end
  return surface
end

function chart_surface_as_radar(surface)
  if not surface or not surface.valid then return end
  -- Запросить генерацию всех чанков в пределах MAP_LIMIT
  -- 1000 тайлов = ~32 чанка в каждую сторону (500/32≈15.6)
  local chunk_radius = math.ceil(MAP_LIMIT / 32) + 1
  for cx=-chunk_radius, chunk_radius do
    for cy=-chunk_radius, chunk_radius do
      local pos = {x=cx*32, y=cy*32}
      if not surface.is_chunk_generated({cx,cy}) then
        surface.request_to_generate_chunks(pos, 0)
      end
    end
  end
  -- Форсируем генерацию
  pcall(function() surface.force_generate_chunk_requests() end)

  -- Чарт как радаром для всех сил
  for _, force in pairs(game.forces) do
    if force and force.valid then
      pcall(function()
        force.chart(surface, {{-MAP_LIMIT, -MAP_LIMIT}, {MAP_LIMIT, MAP_LIMIT}})
      end)
    end
  end
  log("[custom-se-starmap] surface charted as radar")
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
  for x=area.left_top.x, area.right_bottom.x-1 do
    for y=area.left_top.y, area.right_bottom.y-1 do
      if x < -MAP_LIMIT or x >= MAP_LIMIT or y < -MAP_LIMIT or y >= MAP_LIMIT then
        table.insert(tiles, {name="out-of-map", position={x,y}}) need=true
      else
        local ct = surface.get_tile(x, y)
        if ct.name ~= "empty-space" then
          local tn="empty-space"
          if custom_tile_exists then tn="custom-se-empty-space-no-correct" end
          table.insert(tiles, {name=tn, position={x,y}}) need=true
        end
      end
    end
  end
  if need and #tiles>0 then surface.set_tiles(tiles,false,false) end
  -- всегда держать зачартненным
  if event.tick and event.tick % 300 == 0 then
    chart_surface_as_radar(surface)
  end
  if surface then
    local ents=surface.find_entities_filtered({area=area})
    for _,e in ipairs(ents) do
      if e.valid and e.name~="custom-se-planet-marker" and not string.find(e.name,"^custom%-se%-marker%-") then e.destroy() end
    end
    surface.destroy_decoratives({area=area})
  end
end


