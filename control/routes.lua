-- control/routes.lua [space-map-rework]
-- Тестовый модуль маршрутов:
--  1) Автопланировка связей:
--       * луна — к планете-родителю (прямая);
--       * звёздные планеты — к ROUTE_NEIGHBOR_DEPTH соседям в каждую сторону
--         по радиусу орбиты (луны/локации в цепочке не участвуют);
--       * space-location — одна связь к крайней планете внутри её орбиты;
--         локация со связью location<->location (ачивка/эксклюзив) пропускается;
--       * эксклюзивные связи — только connections-exclusive.lua;
--       * ванильные связи игнорируются.
--  2) Динамическая отрисовка путей. Геометрия — от центра до центра тел;
--     концы в отступе иконок не отрисовываются (route_subpath_points выдаёт
--     видимую середину тем же пулом сегментов). Звёздные связи — дуга
--     (квадратичный Безье, выпуклость от солнца) с динамическим изгибом
--     (доля хорды растёт с расстоянием, ROUTE_ARC_BULGE_MIN..MAX до хорды
--     ROUTE_ARC_BULGE_REF); лунные — прямые. При входе дуги в запретную зону
--     солнца (STAR_RADIUS + ROUTE_SUN_PADDING) изгиб непрерывно растёт до
--     обхода (смена формы без скачков — иначе маркер телепортируется вместе
--     с путём). Сторона дуги — гистерезис в storage.route_geom по ключу связи.
--     Параллельные пути разводятся на полосы (ROUTE_LANE_SPREAD), у концов
--     смещение сходит к 0. Линия — пул draw_line-сегментов (ширина в px).
--  3) Подписей длин на карте нет. Шкала прогресса на линии — только у связи
--     с наведённой платформой (storage.hover_probe + TRAVEL_MARKER_CAPTURE).
--     Полный пересчёт каждый тик: квантованный кэш давал рывки, удалён.
--  4) Маркеры летящих платформ. API 2.x: platform.distance — доля [0,1]
--     (0 = connection.from). Позиция = route_point_at(pts, clipA +
--     (total-clipA-clipB) * frac). Нос спрайта — по знаку изменения frac.

local TWO_PI = 2 * math.pi

-- ограничение числа логируемых ошибок рендера путей
local route_err_count = 0

-- нормализация угла в (-pi, pi]
local function wrap_pi(a)
  a = a % TWO_PI
  if a > math.pi then a = a - TWO_PI end
  if a <= -math.pi then a = a + TWO_PI end
  return a
end

-- полная длина ломаной
local function route_points_length(pts)
  local total = 0
  for i = 2, #pts do
    total = total + math.sqrt((pts[i].x - pts[i-1].x)^2 + (pts[i].y - pts[i-1].y)^2)
  end
  return total
end

-- Канонический ключ связи: порядок имён нормализуется, чтобы линия связи
-- и путь платформы строились идентично.
local function route_pair_key(a_name, b_name)
  local sa, sb = tostring(a_name), tostring(b_name)
  if sa < sb then return sa .. "|" .. sb end
  return sb .. "|" .. sa
end

-- Детерминированный хэш ключа связи -> полоса маршрута (lane), тайлы.
local function route_lane_for(key)
  if not key then return 0 end
  local h = 5381
  for i = 1, #key do h = (h * 33 + string.byte(key, i)) % 16777216 end
  return ((h % 4) - 1.5) * (ROUTE_LANE_SPREAD or 0.35)
end

-- Маршрут A->B: ровно ROUTE_SEGMENTS+1 точек. straight=true — прямая
-- (лунные связи), иначе дуга (квадратичный Безье, сторона от солнца) с
-- динамическим изгибом и непрерывным обходом зоны солнца
-- (Rs = STAR_RADIUS + ROUTE_SUN_PADDING).
-- Возвращает: точки, полную длину (центр-до-центра), длины обрезки концов
-- clipA/clipB вдоль дуги. geom_key (необяз.) — гистерезис стороны и полоса.
local function route_path_points(ax, ay, bx, by, straight, geom_key, rad_a, rad_b)
  local nseg = ROUTE_SEGMENTS or 48
  local dx, dy = bx - ax, by - ay
  local chord = math.sqrt(dx * dx + dy * dy)
  if chord < 1e-6 then
    local pts = {}
    for _ = 0, nseg do pts[#pts + 1] = {x = ax, y = ay} end
    return pts, 0, 0, 0
  end

  -- Обрезка концов: clipA/clipB = DIAMETER_K * icon_radius + PAD вдоль дуги.
  -- Геометрия при этом — от центра до центра.
  local clipA, clipB = 0, 0
  if rad_a or rad_b then
    local diam_k = ROUTE_ENDPOINT_DIAMETER_K or 2
    local pad = ROUTE_ENDPOINT_PAD or 0.15
    clipA = (rad_a or 0) * diam_k + pad
    clipB = (rad_b or 0) * diam_k + pad
  end
  -- тела почти вплотную: остаток делится пропорционально
  local function clamp_clips(total)
    local ca, cb = clipA, clipB
    local max_clip = total * 0.9
    if ca + cb > max_clip and ca + cb > 0 then
      local k = max_clip / (ca + cb)
      ca = ca * k
      cb = cb * k
    end
    return ca, cb
  end

  -- прямая: те же nseg+1 точек
  if straight then
    local pts = {}
    for i = 0, nseg do
      local f = i / nseg
      pts[#pts + 1] = {x = ax + dx * f, y = ay + dy * f}
    end
    local ca, cb = clamp_clips(chord)
    return pts, chord, ca, cb
  end

  local ux, uy = dx / chord, dy / chord
  local nx, ny = -uy, ux                              -- нормаль хорды
  local mx, my = (ax + bx) * 0.5, (ay + by) * 0.5     -- середина хорды
  local dot = mx * nx + my * ny                       -- >0: нормаль от солнца

  -- Гистерезис стороны дуги: вне мёртвой зоны |dot| — геометрически от
  -- солнца, внутри — прошлая сторона (per-связь в storage), иначе дуга
  -- переключается при почти-диаметральной хорде и маркер телепортируется.
  local geom = nil
  if geom_key then
    storage.route_geom = storage.route_geom or {}
    geom = storage.route_geom[geom_key]
    if not geom then geom = {}; storage.route_geom[geom_key] = geom end
  end
  local side
  if math.abs(dot) > chord * 0.08 then
    side = (dot >= 0) and 1 or -1
  elseif geom and geom.side then
    side = geom.side                                   -- гистерезис
  else
    side = (route_lane_for(geom_key) >= 0) and 1 or -1 -- первый раз: по ключу
  end
  if geom then geom.side = side end

  -- Динамический изгиб: доля хорды линейно от MIN до MAX на длине REF.
  local Rs = (STAR_RADIUS or 7) + (ROUTE_SUN_PADDING or 2)
  local rA = math.sqrt(ax * ax + ay * ay)
  local rB = math.sqrt(bx * bx + by * by)
  local df = chord / (ROUTE_ARC_BULGE_REF or 60)
  if df > 1 then df = 1 end
  local bmin = ROUTE_ARC_BULGE_MIN or 0.10
  local bmax = ROUTE_ARC_BULGE_MAX or 0.35
  local bulge = chord * (bmin + (bmax - bmin) * df)
  local bulge_cap = chord * (ROUTE_MAX_BULGE or 3)

  -- Полосы параллельных путей: смещение вдоль нормали × side, у концов — 0.
  -- Применяется до солвера зазора солнца (иначе полоса могла бы вернуть
  -- обогнувшую дугу в зону).
  local lane = route_lane_for(geom_key)
  local lane_dirx, lane_diry = nx * side, ny * side
  local ramp_t = ROUTE_LANE_RAMP or 0.18

  local pts = {}
  local function build(bl)
    local cpx, cpy = mx + nx * side * bl, my + ny * side * bl
    for i = 0, nseg do
      local tt = i / nseg
      local u = 1 - tt
      local px = u * u * ax + 2 * u * tt * cpx + tt * tt * bx
      local py = u * u * ay + 2 * u * tt * cpy + tt * tt * by
      if lane ~= 0 and i > 0 and i < nseg then
        local ramp = math.min(tt, 1 - tt) / ramp_t
        if ramp > 1 then ramp = 1 end
        -- синусный разгон полосы (без видимого излома у концов)
        ramp = math.sin(ramp * math.pi * 0.5)
        local off = lane * ramp
        px = px + lane_dirx * off
        py = py + lane_diry * off
      end
      pts[i + 1] = {x = px, y = py}
    end
  end
  build(bulge)
  if rA > Rs and rB > Rs then
    local function min_sun_dist()
      local d2min = math.huge
      for i = 2, nseg do
        local p = pts[i]
        local d2 = p.x * p.x + p.y * p.y
        if d2 < d2min then d2min = d2 end
      end
      return math.sqrt(d2min)
    end
    -- Подъём только при реальном нарушении зазора (на пороге factor=1 —
    -- непрерывное включение).
    if min_sun_dist() < Rs * 1.02 then
      -- затухающий мультипликативный шаг, фиксированное число проходов
      -- (ранний break давал межтиковые осцилляции -> дрожание дуги)
      for _ = 1, (ROUTE_CLEAR_ITERS or 8) do
        local dmin = min_sun_dist()
        local factor = (Rs * 1.02) / math.max(dmin, 0.2)
        bulge = bulge * math.sqrt(factor)
        if bulge > bulge_cap then bulge = bulge_cap end
        build(bulge)
      end
    end
  end

  local total = route_points_length(pts)
  local ca, cb = clamp_clips(total)
  return pts, total, ca, cb
end

-- Точка на пути на длине s от начала + единичная касательная.
local function route_point_at(pts, s)
  local px, py = pts[1].x, pts[1].y
  local dx, dy = 1, 0
  local acc = 0
  for i = 2, #pts do
    local nx, ny = pts[i].x, pts[i].y
    local seg = math.sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
    if seg > 1e-9 then
      local ux, uy = (nx - px) / seg, (ny - py) / seg
      if acc + seg >= s then
        local f = (s - acc) / seg
        return px + (nx - px) * f, py + (ny - py) * f, ux, uy
      end
      acc = acc + seg
      dx, dy = ux, uy
    end
    px, py = nx, ny
  end
  return px, py, dx, dy
end

-- Видимый кусок пути [s0, s1] (по длине дуги), ровно nseg+1 точек.
local function route_subpath_points(pts, s0, s1, nseg)
  if s1 < s0 then s1 = s0 end
  local span = s1 - s0
  local out = {}
  local acc = 0
  local idx = 1
  local px, py = pts[1].x, pts[1].y
  for k = 0, nseg do
    local target = s0 + span * (k / nseg)
    -- #pts-1, не #pts: при вырожденном пути idx не должен выйти за конец
    while idx < (#pts - 1) do
      local nx, ny = pts[idx + 1].x, pts[idx + 1].y
      local seg = math.sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
      if seg > 1e-9 and acc + seg >= target then break end
      acc = acc + seg
      px, py = nx, ny
      idx = idx + 1
    end
    local nx, ny = pts[idx + 1].x, pts[idx + 1].y
    local seg = math.sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
    local f = 0
    if seg > 1e-9 then
      f = (target - acc) / seg
      if f < 0 then f = 0 elseif f > 1 then f = 1 end
    end
    out[k + 1] = {x = px + (nx - px) * f, y = py + (ny - py) * f}
  end
  return out
end

-- --- Инициализация/очистка рендера ---

-- Линия маршрута = массив id draw_line-сегментов. Числовой id — устаревший
-- формат (один полигон) — удаляется.
local function route_destroy_line(slot)
  if not slot or not slot.line then return end
  if type(slot.line) == "table" then
    for _, id in ipairs(slot.line) do r_destroy(id) end
  else
    r_destroy(slot.line)
  end
  slot.line = nil
end

local function route_destroy_renders(slot)
  if not slot then return end
  route_destroy_line(slot)
  r_destroy(slot.label)
  slot.label = nil
end

-- Ближайшая живая сущность travel-маркера к точке (ближайшая, не первая:
-- на пересекающихся путях иначе находится чужая сущность).
local function route_find_marker_entity(surface, pos, radius)
  local ok_f, found = pcall(function()
    return surface.find_entities_filtered{
      name = TRAVEL_MARKER_NAME,
      position = pos,
      radius = radius
    }
  end)
  if not (ok_f and found) then return nil end
  local best, best_d2 = nil, nil
  for _, e in ipairs(found) do
    if e.valid then
      local ddx, ddy = e.position.x - pos.x, e.position.y - pos.y
      local d2 = ddx * ddx + ddy * ddy
      if not best_d2 or d2 < best_d2 then best_d2, best = d2, e end
    end
  end
  return best
end

-- Пул сегментов фиксированного размера: создание недостающих, обновление
-- from/to/width/color каждый тик. seg_color_fn (необяз.) — цвет сегмента
-- (шкала прогресса); nil -> базовый цвет.
local function route_sync_line(surface, slot, pts, color, width, seg_color_fn)
  local need = #pts - 1
  local line = slot.line
  if type(line) ~= "table" or #line ~= need then
    route_destroy_line(slot)
    line = {}
    slot.line = line
  end
  for i = 1, need do
    local seg_color = color
    if seg_color_fn then seg_color = seg_color_fn(i) or color end
    local seg = r_obj(line[i])
    if seg then
      seg.from = {x = pts[i].x, y = pts[i].y}
      seg.to = {x = pts[i + 1].x, y = pts[i + 1].y}
      seg.width = width
      seg.color = seg_color
    else
      local ok, obj = pcall(function()
        return rendering.draw_line{
          color = seg_color,
          width = width,
          from = {x = pts[i].x, y = pts[i].y},
          to = {x = pts[i + 1].x, y = pts[i + 1].y},
          surface = surface,
          draw_on_ground = true
        }
      end)
      if ok and obj then
        line[i] = obj.id
      elseif route_err_count < 10 then
        route_err_count = route_err_count + 1
        log("[space-map-rework] route line seg FAIL: " .. tostring(obj))
      end
    end
  end
end

-- --- Граф связей ---

-- Сигнатура состава системы (меняется при rebuild) -> граф перестраивается
local function routes_signature()
  local parts = {}
  for _, b in ipairs(storage.planets or {}) do
    parts[#parts + 1] = (b.name or "?") .. "@" .. (b.parent_name or "-")
  end
  return table.concat(parts, ";")
end

-- space-location (solar-system-edge, shattered-planet) или планета?
local function route_is_location(name)
  return not (game.planets and game.planets[name] ~= nil)
end

-- --- Фильтр связей по исследованности ---

-- Значение переключателя: runtime-global настройка, иначе литерал
-- CONN_DISCOVERED_ONLY из constants.lua (зеркало).
local function conn_discovered_only()
  local ok, v = pcall(function()
    return settings.global["space-map-rework-conn-discovered-only"].value
  end)
  if ok and type(v) == "boolean" then return v end
  return CONN_DISCOVERED_ONLY ~= false
end

-- Открытость тела — общий helper starmap_body_unlocked из
-- control/starsystem.lua (НЕ дублировать реализацию здесь): сила "player",
-- is_space_location_unlocked -> fallback tech mod-data; луна наследует
-- родителя; без технологии — открыто.
local function conn_body_unlocked(by_name, name)
  return starmap_body_unlocked(name)
end

-- Автопланировка связей (правила — см. ROUTE_NEIGHBOR_DEPTH в constants.lua).
function rebuild_routes()
  storage.route_edges = {}
  if storage.route_renders then
    for _, slot in ipairs(storage.route_renders) do route_destroy_renders(slot) end
  end
  storage.route_renders = {}
  storage.route_geom = {}

  local seen_pairs = {}
  local bodies_by_name = storage.planet_by_name or {}
  local function add_edge(a_name, b_name, moon)
    if not a_name or not b_name or a_name == b_name then return end
    local lo, hi = a_name, b_name
    if hi < lo then lo, hi = hi, lo end
    local key = lo .. "|" .. hi
    if seen_pairs[key] then return end
    seen_pairs[key] = true
    if not bodies_by_name[a_name] or not bodies_by_name[b_name] then
      log("[space-map-rework] routes: пропуск связи (нет тела на карте): "
        .. tostring(a_name) .. " <-> " .. tostring(b_name))
      return
    end
    -- фильтр исследованности: оба конца должны быть открыты (переключатель)
    if conn_discovered_only()
       and (not conn_body_unlocked(bodies_by_name, a_name)
            or not conn_body_unlocked(bodies_by_name, b_name)) then
      return
    end
    table.insert(storage.route_edges, {a = a_name, b = b_name, moon = moon and true or false})
  end

  local star_planets, locations = {}, {}
  for _, b in ipairs(storage.planets or {}) do
    if b.parent_name then
      add_edge(b.name, b.parent_name, true)
    elseif route_is_location(b.name) then
      table.insert(locations, b)
    elseif b.orbit_radius then
      table.insert(star_planets, b)
    end
  end
  table.sort(star_planets, function(x, y) return (x.orbit_radius or 0) < (y.orbit_radius or 0) end)
  table.sort(locations, function(x, y) return (x.orbit_radius or 0) < (y.orbit_radius or 0) end)

  -- планеты: DEPTH соседей в каждую сторону
  local depth = ROUTE_NEIGHBOR_DEPTH or 2
  for i = 1, #star_planets do
    for d = 1, depth do
      if star_planets[i + d] then
        add_edge(star_planets[i].name, star_planets[i + d].name, false)
      end
    end
  end

  -- Локации с существующей связью location<->location (ванильные прототипы,
  -- кроме авто space-map-rework-route-*/space-map-rework-xconn-*, + эксклюзивный файл).
  local loc_linked = {}
  local function mark_loc_pair(f, t)
    if f and t and route_is_location(f) and route_is_location(t) then
      loc_linked[f] = true
      loc_linked[t] = true
    end
  end
  pcall(function()
    for _, c in pairs(prototypes.space_connection) do
      local nm = c.name or ""
      if not string.find(nm, "^space%-map%-rework%-route%-")
         and not string.find(nm, "^space%-map%-rework%-xconn%-") then
        mark_loc_pair(c.from and c.from.name, c.to and c.to.name)
      end
    end
  end)
  for _, ec in ipairs(EXCLUSIVE_CONNECTIONS or {}) do
    mark_loc_pair(ec.from, ec.to)
  end

  -- Локации, проход 1: крайняя свободная планета внутри орбиты локации.
  local planet_taken = {}
  for _, loc in ipairs(locations) do
    if not loc_linked[loc.name] then
      local lr = loc.orbit_radius or 0
      local best = nil
      for _, p in ipairs(star_planets) do
        local pr = p.orbit_radius or 0
        if pr < lr and not planet_taken[p.name] then
          if not best or pr > (best.orbit_radius or 0) then best = p end
        end
      end
      if best then
        planet_taken[best.name] = true
        add_edge(loc.name, best.name, false)
      end
    end
  end
  -- Локации, проход 2: связи всё ещё нет -> ближайшая по радиусу планета.
  -- shattered-planet к планетам не подключается (только граница системы;
  -- потерянную связь восстановить в connections-exclusive.lua).
  local SHATTERED = ROUTE_SHATTERED_NAME or "shattered-planet"
  for _, loc in ipairs(locations) do
    if loc.name ~= SHATTERED then
      local has_planet_link = false
      for _, e in ipairs(storage.route_edges) do
        local other = nil
        if e.a == loc.name then other = e.b
        elseif e.b == loc.name then other = e.a end
        if other and not route_is_location(other) then has_planet_link = true; break end
      end
      if not has_planet_link then
        local lr = loc.orbit_radius or 0
        local best, bd = nil, nil
        for _, p in ipairs(star_planets) do
          local d = math.abs((p.orbit_radius or 0) - lr)
          if not bd or d < bd then bd, best = d, p end
        end
        if best then add_edge(loc.name, best.name, false) end
      end
    end
  end

  -- эксклюзивные (ручные) — поверх автоматики
  for _, ec in ipairs(EXCLUSIVE_CONNECTIONS or {}) do
    add_edge(ec.from, ec.to, false)
  end

  -- Зеркало прототипов: любая существующая space-connection, оба конца
  -- которой есть на карте, отрисовывается (иначе платформа на такой связи
  -- летит по карте без линии).
  pcall(function()
    for _, c in pairs(prototypes.space_connection) do
      local f = c.from and c.from.name
      local t = c.to and c.to.name
      if f and t and bodies_by_name[f] and bodies_by_name[t] then
        local fa, fb = bodies_by_name[f], bodies_by_name[t]
        local is_moon = (fa.parent_name ~= nil and fa.parent_name == fb.name)
          or (fb.parent_name ~= nil and fb.parent_name == fa.name)
        add_edge(f, t, is_moon)
      end
    end
  end)
  log("[space-map-rework] routes: " .. #storage.route_edges .. " edges"
    .. " (planets=" .. #star_planets .. ", locations=" .. #locations .. ", depth=" .. depth .. ")")
end

-- Принудительная пересборка графа (вызывается из /starmap-rebuild).
function force_routes_rebuild()
  storage.route_sig = nil
end

-- Пересборка графа после перезахода: правила/эксклюзивные связи могли
-- измениться при той же сигнатуре состава. В on_load storage недоступен —
-- только флаг.
local routes_reset_after_load = false
pcall(function()
  script.on_load(function()
    routes_reset_after_load = true
  end)
end)

-- === Драйвер: каждый тик из events.lua после update_orbits() ===
function update_routes()
  if not ROUTES_ENABLED then return end
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid or not storage.planets then return end

  if routes_reset_after_load then
    routes_reset_after_load = false
    storage.route_sig = nil
  end

  local sig = routes_signature()
  if storage.route_sig ~= sig then
    storage.route_sig = sig
    rebuild_routes()
  end

  local by_name = storage.planet_by_name or {}

  -- Пре-проход: летящие платформы по каноническим парам (cf — доля вдоль
  -- канонического порядка lo->hi). Данные прошлого тика (маркеры обновляются
  -- ниже), лаг 1 тик.
  storage.travel_marks = storage.travel_marks or {}
  local travel_by_pair = {}
  for mkey, mark in pairs(storage.travel_marks) do
    if mark.from_name and mark.to_name and type(mark.progress) == "number" then
      local lo, hi = tostring(mark.from_name), tostring(mark.to_name)
      local flip = hi < lo
      local key = route_pair_key(mark.from_name, mark.to_name)
      local t = travel_by_pair[key]
      if not t then t = {}; travel_by_pair[key] = t end
      -- Сторона "позади" — по фактическому направлению движения
      -- (mark.dir = знак изменения platform.distance), а не по концам связи.
      -- toward_hi: каноническая доля cf растёт (рейс к hi-концу).
      local ds = mark.dir or 1
      local toward_hi = ((ds > 0) ~= flip)
      t[#t + 1] = {cf = flip and (1 - mark.progress) or mark.progress,
                   toward_hi = toward_hi, mkey = mkey}
    end
  end

  -- Наведённые платформы: пара связи -> множество ключей меток под курсором.
  -- Прогресс рисуется только позади наведённой метки: подсветка всех
  -- платформ связи при встречном рейсе выглядела "не в ту сторону".
  local hl_marks = nil
  if ROUTE_PROGRESS_ENABLED ~= false and ROUTE_PROGRESS_HOVER_ONLY ~= false then
    for _, p in pairs(game.players) do
      if p.valid and p.surface and p.surface.name == SURFACE_NAME then
        local pr = storage.hover_probe and storage.hover_probe[p.index]
        if pr and (game.tick - (pr.tick or -2000000000)) <= (HOVER_PROBE_TTL or 3) then
          local cap2 = (TRAVEL_MARKER_CAPTURE or 1.6) ^ 2
          for mkey, m in pairs(storage.travel_marks) do
            if m.x and m.y and m.from_name and m.to_name then
              local hdx, hdy = m.x - pr.x, m.y - pr.y
              if hdx * hdx + hdy * hdy <= cap2 then
                hl_marks = hl_marks or {}
                local pk = route_pair_key(m.from_name, m.to_name)
                local set = hl_marks[pk]
                if not set then set = {}; hl_marks[pk] = set end
                set[mkey] = true
              end
            end
          end
        end
      end
    end
  end

  -- === Линии путей ===
  local nseg = ROUTE_SEGMENTS or 48
  for i, edge in ipairs(storage.route_edges or {}) do
    local a, b = by_name[edge.a], by_name[edge.b]
    storage.route_renders[i] = storage.route_renders[i] or {}
    local slot_r = storage.route_renders[i]

    if a and b and a.position and b.position and a.discovered and b.discovered then
      -- лунные — прямая; звёздные — дуга со своей полосой
      local key = route_pair_key(edge.a, edge.b)
      -- Канонический порядок концов во всех вызовах route_path_points:
      -- линия и путь платформы обязаны совпадать.
      local gkey = edge.moon and nil or key
      local axc, ayc, bxc, byc = a.position.x, a.position.y, b.position.x, b.position.y
      local radA, radB = a.icon_radius or 1, b.icon_radius or 1
      if not edge.moon and tostring(edge.a) > tostring(edge.b) then
        axc, ayc, bxc, byc = bxc, byc, axc, ayc
        radA, radB = radB, radA
      end
      -- шкала прогресса: только метки наведённых платформ этой связи
      local hovered = hl_marks and hl_marks[key]
      local plist = nil
      if hovered then plist = travel_by_pair[key] end
      -- Полный пересчёт каждый тик (квантованный кэш давал рывки).
      -- Геометрия от центров; видимая середина — route_subpath_points.
      local pts, total, sA, sB = route_path_points(axc, ayc, bxc, byc, edge.moon, gkey, radA, radB)
      local s1 = total - sB
      if s1 < sA then s1 = sA end
      local vpts = route_subpath_points(pts, sA, s1, nseg)
      local color = edge.moon and ROUTE_MOON_COLOR or ROUTE_COLOR
      local seg_fn = nil
      if plist then
        local draw_rev = edge.moon and (tostring(edge.a) > tostring(edge.b)) or false
        local pcol = edge.moon and ROUTE_PROGRESS_MOON_COLOR or ROUTE_PROGRESS_COLOR
        seg_fn = function(i)
          local tmid = (i - 0.5) / nseg
          if draw_rev then tmid = 1 - tmid end
          for _, t in ipairs(plist) do
            -- пройденная часть (строго позади наведённой метки):
            -- рейс к hi -> tmid <= cf; рейс к lo -> tmid >= cf
            if hovered[t.mkey]
               and ((t.toward_hi and tmid <= t.cf)
                 or ((not t.toward_hi) and tmid >= t.cf)) then
              return pcol
            end
          end
          return nil
        end
      end
      route_sync_line(surface, slot_r, vpts, color, ROUTE_WIDTH or 1.5, seg_fn)
    else
      route_destroy_renders(slot_r)
    end
  end

  -- === Летящие платформы: маркер на пути, привязка к доле пути ===
  storage.travel_marks = storage.travel_marks or {}
  local seen = {}
  if ROUTE_PLATFORM_MARKS_ENABLED then
    for _, force in pairs(game.forces) do
      if force.valid then
        local ok_f, plats = pcall(function() return force.platforms end)
        if ok_f and plats then
          for _, platform in pairs(plats) do
            local conn = nil
            pcall(function()
              if platform.valid then conn = platform.space_connection end
            end)
            if conn then
              local from_n, to_n, clen, pdist, pname, pidx
              pcall(function() from_n = conn.from and conn.from.name end)
              pcall(function() to_n = conn.to and conn.to.name end)
              pcall(function() clen = conn.length end)
              pcall(function() pdist = platform.distance end)
              pcall(function() pname = platform.name end)
              pcall(function() pidx = platform.index end)
              -- путь — строго в направлении connection: from -> to
              -- (platform.distance отсчитывается от from к to)
              local a = from_n and by_name[from_n]
              local b = to_n and by_name[to_n]
              if a and b and a.position and b.position and a.discovered and b.discovered then
                -- frac = доля пути (0=from, 1=to). API 2.x: distance уже
                -- доля [0,1]; >1 — старый километровый API (делим на length).
                local frac = 0
                if type(pdist) == "number" then
                  if pdist <= 1.000001 then
                    frac = pdist
                  elseif type(clen) == "number" and clen > 0 then
                    frac = pdist / clen
                  end
                end
                if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

                -- лунная связь -> прямая, иначе дуга
                local pm_straight = (a.parent_name ~= nil and a.parent_name == b.name)
                  or (b.parent_name ~= nil and b.parent_name == a.name)
                -- та же геометрия, что у линии: канонический порядок + общий
                -- ключ пары. frac в API от from к to -> в канонике может
                -- инвертироваться (pfrac = 1 - frac).
                local pm_key = nil
                local pfrac = frac
                local pax, pay, pbx, pby = a.position.x, a.position.y, b.position.x, b.position.y
                local pra, prb = a.icon_radius or 1, b.icon_radius or 1
                if not pm_straight then
                  pm_key = route_pair_key(from_n, to_n)
                  if tostring(from_n) > tostring(to_n) then
                    pax, pay, pbx, pby = pbx, pby, pax, pay
                    pra, prb = prb, pra
                    pfrac = 1 - frac
                  end
                end
                local pts, total, sA, sB = route_path_points(pax, pay, pbx, pby, pm_straight, pm_key, pra, prb)
                -- маркер летит по видимой части (без концов под иконками)
                local vis = total - sA - sB
                if vis < 0 then vis = 0 end
                local tx, ty, dirx, diry = route_point_at(pts, sA + vis * pfrac)
                local key = force.name .. ":" .. tostring(pidx or 0)
                seen[key] = true
                local mark = storage.travel_marks[key]
                if not mark then mark = {}; storage.travel_marks[key] = mark end
                -- Анти-телепорт: скачок точки пути (перекидка дуги) ->
                -- пружинное догоняние. Снап — при смене рейса
                -- (другая пара, |Δfrac| >= FRAC_RESET).
                local x, y = tx, ty
                if mark.x and mark.y
                   and mark.from_name == from_n and mark.to_name == to_n
                   and mark.last_frac
                   and math.abs(frac - mark.last_frac) < (ROUTE_MARK_FRAC_RESET or 0.25) then
                  local jx, jy = tx - mark.x, ty - mark.y
                  local jd = math.sqrt(jx * jx + jy * jy)
                  if jd > (ROUTE_MARK_SNAP_DIST or 3) and jd <= (ROUTE_MARK_SPRING_DIST or 60) then
                    local step = jd * (ROUTE_MARK_SPRING or 0.12)
                    local maxs = ROUTE_MARK_MAX_STEP or 2.0
                    if step > maxs then step = maxs end
                    x = mark.x + jx / jd * step
                    y = mark.y + jy / jd * step
                  end
                end

                -- Направление движения = знак изменения frac: рейс from->to —
                -- frac растёт, обратный — падает. На паузе frac стоит, знак
                -- держится. Старт плеча (новая метка или сменились концы
                -- связи): приращения ещё нет — знак по позиции на связи:
                -- платформа стартует у конца, frac<=0.5 -> от from (+1),
                -- иначе от to (-1). Иначе первый тик обратного рейса
                -- показывал прогресс "не в ту сторону".
                local ds = mark.dir
                if (not mark.last_frac)
                   or mark.from_name ~= from_n or mark.to_name ~= to_n then
                  ds = (frac <= 0.5) and 1 or -1
                elseif frac > mark.last_frac + 1e-9 then ds = 1
                elseif frac < mark.last_frac - 1e-9 then ds = -1 end
                mark.dir = ds or 1
                mark.last_frac = frac

                -- касательная dirx/diry — вдоль канонического порядка пары;
                -- ds — по направлению рейса; при перевёрнутой канонике
                -- (from > to) нос = минус касательная
                local fdir = ds * ((pm_key and tostring(from_n) > tostring(to_n)) and -1 or 1)
                local fdx, fdy = dirx * fdir, diry * fdir
                local orient = (math.atan2(fdy, fdx) / TWO_PI + (ROUTE_PLATFORM_SPRITE_ROTATION or 0.5)) % 1
                local spr = r_obj(mark.sprite)
                if spr then
                  pcall(function()
                    spr.target = {x = x, y = y}
                    spr.orientation = orient
                  end)
                  r_bring_front(mark.sprite)
                else
                  local ok_s, sobj = pcall(function()
                    return rendering.draw_sprite{
                      sprite = "space-map-rework-platform-" .. tostring(PLATFORM_SPRITE_FRAME or 1),
                      target = {x = x, y = y},
                      surface = surface,
                      x_scale = (PLATFORM_SIZE * 32) / 54,
                      y_scale = (PLATFORM_SIZE * 32) / 54,
                      orientation = orient
                    }
                  end)
                  if ok_s and sobj then mark.sprite = sobj.id end
                end

                -- подпись платформы сбоку от линии
                local gap = ROUTE_PLATFORM_LABEL_GAP or 0.8
                local lx, ly = x - diry * gap, y + dirx * gap
                local lbl = r_obj(mark.label)
                if lbl then
                  pcall(function() lbl.target = {x = lx, y = ly} end)
                  r_bring_front(mark.label)
                else
                  local ok_l, lobj = pcall(function()
                    return rendering.draw_text{
                      text = pname or "platform",
                      surface = surface,
                      target = {x = lx, y = ly},
                      color = {r = 0.85, g = 0.95, b = 1, a = 0.9},
                      scale = 0.45,
                      alignment = "center"
                    }
                  end)
                  if ok_l and lobj then mark.label = lobj.id end
                end

                -- Кликабельная сущность маркера (hover -> камера в gui.lua,
                -- ПКМ -> remote view). LuaEntity в storage не хранится —
                -- поиск по позиции каждый тик. Сущность не двигается каждый
                -- тик: постоянные position= нарушают перевыделение движком
                -- (теряется наведение); плавность даёт спрайт, хитбокс
                -- догоняет скачками по порогу TRAVEL_MARKER_FOLLOW_STEP.
                local ent_new = {x = x, y = y}
                local ent = nil
                if mark.x and mark.y then
                  ent = route_find_marker_entity(surface, {x = mark.x, y = mark.y},
                    TRAVEL_MARKER_PARK_RADIUS or 2)
                end
                if not ent then
                  -- рассинхрон: поиск у новой позиции
                  ent = route_find_marker_entity(surface, ent_new,
                    TRAVEL_MARKER_PARK_RADIUS or 2)
                end
                if ent and ent.valid then
                  local ep = ent.position
                  local edx, edy = ep.x - ent_new.x, ep.y - ent_new.y
                  if edx * edx + edy * edy > (TRAVEL_MARKER_FOLLOW_STEP or 0.3) ^ 2 then
                    local ok_tp, moved = pcall(function() return ent.teleport(ent_new) end)
                    if (not ok_tp) or moved == false then
                      pcall(function() ent.position = ent_new end)
                    end
                  end
                else
                  pcall(function()
                    surface.create_entity{
                      name = TRAVEL_MARKER_NAME,
                      position = ent_new,
                      force = "neutral"
                    }
                  end)
                end
                -- storage-safe метаданные для hover-окна (gui.lua) и ПКМ
                mark.x, mark.y = x, y
                mark.force, mark.index = force.name, pidx or 0
                mark.name = pname
                mark.from_name, mark.to_name = from_n, to_n
                -- прогресс рейса: доля пути + длина коннекшена (км, прототип)
                mark.progress = frac
                mark.km_total = (type(clen) == "number" and clen > 0) and clen or nil
              end
            end
          end
        end
      end
    end
  end
  -- маркеры прилетевших/исчезнувших платформ
  for key, mark in pairs(storage.travel_marks) do
    if not seen[key] then
      r_destroy(mark.sprite)
      r_destroy(mark.label)
      -- и кликабельную сущность маркера (у последней позиции)
      if mark.x and mark.y then
        pcall(function()
          for _, e in ipairs(surface.find_entities_filtered{
            name = TRAVEL_MARKER_NAME,
            position = {x = mark.x, y = mark.y},
            radius = (TRAVEL_MARKER_PARK_RADIUS or 2) + 1
          }) do
            if e.valid then pcall(function() e.destroy() end) end
          end
        end)
      end
      storage.travel_marks[key] = nil
    end
  end
  -- чистка сущностей-сирот (тик мог быть пропущен) раз в 10 с
  if game.tick % 600 == 37 then
    local ok_s, all = pcall(function()
      return surface.find_entities_filtered{name = TRAVEL_MARKER_NAME}
    end)
    if ok_s and all and #all > 0 then
      local live = {}
      for _, mark in pairs(storage.travel_marks) do
        if mark.x and mark.y then
          live[#live + 1] = mark
        end
      end
      for _, e in ipairs(all) do
        local keep = false
        if e.valid then
          local ep = e.position
          for _, mark in ipairs(live) do
            local dx, dy = ep.x - mark.x, ep.y - mark.y
            if dx * dx + dy * dy <= 9 then keep = true; break end
          end
          if not keep then pcall(function() e.destroy() end) end
        end
      end
    end
  end
end

-- Обёртка с логом ошибок (pcall в events.lua скрыл бы ошибки модуля).
function update_routes_safe()
  local ok, err = pcall(update_routes)
  if not ok and route_err_count < 10 then
    route_err_count = route_err_count + 1
    log("[space-map-rework] routes ERROR: " .. tostring(err))
    for _, p in pairs(game.players) do
      pcall(function() p.print("[routes] ОШИБКА: " .. tostring(err)) end)
    end
  end
end

-- Регистрация команды под несколькими именами (короткое /starmap-* +
-- /starmap-test-*); занятое имя не перебивается. Глобально: используется в
-- events.lua (routes.lua грузится раньше по порядку require в control.lua).
function reg_starmap_cmd(names, help, fn)
  for _, name in ipairs(names) do
    pcall(function()
      local taken = false
      pcall(function() taken = commands.commands[name] ~= nil end)
      if not taken then
        commands.add_command(name, help, fn)
      end
    end)
  end
end

-- Диагностика: связи, летящие платформы, сырое platform.distance
-- ([0,1] = доля пути API 2.x; >1 = километры).
reg_starmap_cmd({"starmap-routes", "starmap-test-routes"}, "ТЕСТ: связи и летящие платформы", function(e)
  local p = e.player_index and game.players[e.player_index] or nil
  local function say(s)
    if p then p.print(s) end
    log(s)
  end
  say("[routes] edges: " .. #(storage.route_edges or {}))
  for i, edge in ipairs(storage.route_edges or {}) do
    local slot_r = storage.route_renders and storage.route_renders[i]
    local line_ok = false
    if slot_r and type(slot_r.line) == "table" then
      local n_valid = 0
      for _, id in ipairs(slot_r.line) do if r_valid(id) then n_valid = n_valid + 1 end end
      line_ok = n_valid == #slot_r.line and #slot_r.line > 0
    end
    say("[routes]   " .. edge.a .. " <-> " .. edge.b .. (edge.moon and " (луна)" or "")
      .. " | line=" .. (line_ok and "OK" or "нет"))
  end
  local n_marks = 0
  for _ in pairs(storage.travel_marks or {}) do n_marks = n_marks + 1 end
  say("[routes] travel marks: " .. n_marks)
  for _, force in pairs(game.forces) do
    if force.valid then
      local ok_f, plats = pcall(function() return force.platforms end)
      if ok_f and plats then
        for _, platform in pairs(plats) do
          pcall(function()
            if platform.valid and platform.space_connection then
              local conn = platform.space_connection
              local key = force.name .. ":" .. tostring(platform.index)
              local mark = storage.travel_marks and storage.travel_marks[key]
              say(string.format("[routes] fly: %s | %s -> %s | distance(raw)=%s length=%s | frac=%s dir=%s",
                tostring(platform.name),
                tostring(conn.from and conn.from.name),
                tostring(conn.to and conn.to.name),
                tostring(platform.distance),
                tostring(conn.length),
                tostring(mark and mark.last_frac),
                tostring(mark and mark.dir)))
            end
          end)
        end
      end
    end
  end
end)

-- Диагностика: реальные space-connection + проверка записи length
-- (демонстрация read-only).
reg_starmap_cmd({"starmap-conn", "starmap-test-conn"}, "ТЕСТ: реальные space-connection + проверка записи в runtime", function(e)
  local p = e.player_index and game.players[e.player_index] or nil
  local function say(s)
    if p then p.print(s) end
    log(s)
  end

  local n, first = 0, nil
  for name, c in pairs(prototypes.space_connection) do
    n = n + 1
    if not first then first = name end
    if n <= 40 then
      say(string.format("[conn] %s: %s -> %s, length=%s",
        name,
        tostring(c.from and c.from.name),
        tostring(c.to and c.to.name),
        tostring(c.length)))
    end
  end
  say("[conn] всего коннекшенов: " .. n)

  if first then
    local before = prototypes.space_connection[first].length
    local ok, err = pcall(function()
      prototypes.space_connection[first].length = 12345
    end)
    local after = prototypes.space_connection[first].length
    if ok then
      say(string.format("[conn] ЗАПИСЬ length: ошибки не было; length: %s -> %s (%s)",
        tostring(before), tostring(after),
        (after == 12345) and "ИЗМЕНИЛСЯ!" or "остался прежним"))
    else
      say("[conn] ЗАПИСЬ length ЗАПРЕЩЕНА (read-only): " .. tostring(err))
    end
  end
  say("[conn] ИТОГ: сами коннекшены (from/to/length) в runtime НЕ меняются и не создаются —")
  say("[conn] только в data-стадии (мы уже заменили их там на свои). В runtime записываемы")
  say("[conn] лишь platform.space_connection (перекинуть платформу на существующий коннекшн)")
  say("[conn] и platform.distance (доля пути 0..1 от from к to).")
end)
