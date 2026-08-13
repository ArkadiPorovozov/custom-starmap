-- control/gui.lua
-- Карточки характеристик (SHIFT+I), ПКМ -> Remote View, камера предпросмотра
-- платформы и инфо-окно планеты при наведении, закрепы платформ (SHIFT+P).

-- Удержание hover-окна после ухода курсора (HOVER_GRACE_ENABLED/HOVER_GRACE_TICKS).
local HOVER_GRACE = (HOVER_GRACE_ENABLED and HOVER_GRACE_TICKS) or 0

-- Имена маркеров карты (для снятия selection-рамки в on_selected_entity_changed).
function starmap_is_marker_name(name)
  if not name then return false end
  if name == "space-map-rework-platform-marker" then return true end
  if name == "space-map-rework-travel-marker" then return true end
  if name == "space-map-rework-planet-marker" then return true end
  return string.find(name, "^space%-map%-rework%-marker%-") ~= nil
end

-- Источник hover-данных: player.selected ниже по тику уже nil (выделение
-- снято событием), поэтому читается пробник storage.hover_probe[player],
-- записанный event-хендлером (см. events.lua). TTL — HOVER_PROBE_TTL тиков:
-- пока курсор на маркере, движок перевыделяет сущность и пробник обновляется.
local function hover_marker(player)
  local ok, s = pcall(function() return player.selected end)
  if ok and s and s.valid and starmap_is_marker_name(s.name) then
    return s.name, s.position
  end
  local pr = storage.hover_probe and storage.hover_probe[player.index]
  if pr and (game.tick - (pr.tick or -2000000000)) <= (HOVER_PROBE_TTL or 3) then
    return pr.name, {x = pr.x, y = pr.y}
  end
  return nil, nil
end

-- === Платформы: поиск по слотам, камера при наведении, ПКМ → Remote View ===

-- LuaSpacePlatform по (force, index). В storage — только строки/числа.
function find_space_platform(force_name, index)
  local force = game.forces[force_name]
  if not force or not force.valid then return nil end
  local ok, plats = pcall(function() return force.platforms end)
  if not ok or not plats then return nil end
  for _, p in pairs(plats) do
    local ok_v, valid = pcall(function() return p.valid end)
    if ok_v and valid then
      local ok_i, idx = pcall(function() return p.index end)
      if ok_i and idx == index then return p end
    end
  end
  return nil
end

-- Слот платформы под курсором: player.selected приоритетнее cursor_pos.
-- Возвращает {body, slot_index, slot} или nil.
function find_hovered_platform_slot(player, cursor_pos)
  if not player or not player.valid or not storage.planets then return nil end
  local probe = nil
  local sel = player.selected
  if sel and sel.valid and sel.name == "space-map-rework-platform-marker" then
    probe = sel.position
  elseif cursor_pos then
    probe = {x = cursor_pos.x or cursor_pos[1], y = cursor_pos.y or cursor_pos[2]}
  end
  if not probe then return nil end

  local capture2 = (PLATFORM_MARKER_HALF + 0.6) * (PLATFORM_MARKER_HALF + 0.6)
  local best, best_d2 = nil, nil
  for _, b in ipairs(storage.planets) do
    if b.platform_slots and b.position then
      local dist = platform_slot_dist(b)
      for i, slot in ipairs(b.platform_slots) do
        local px = b.position.x + math.cos(slot.angle) * dist
        local py = b.position.y + math.sin(slot.angle) * dist
        local dx, dy = px - probe.x, py - probe.y
        local d2 = dx * dx + dy * dy
        if d2 <= capture2 and (not best_d2 or d2 < best_d2) then
          best_d2 = d2
          best = {body = b, slot_index = i, slot = slot}
        end
      end
    end
  end
  return best
end

-- ПКМ по платформе -> Remote View на её поверхность.
function open_platform_remote_view(player, slot)
  local platform = find_space_platform(slot.force, slot.index)
  if not platform then
    player.print("[space-map-rework] Платформа «" .. (slot.name or "?") .. "» не найдена (улетела?)")
    return
  end
  local surf = nil
  pcall(function() surf = platform.surface end)
  local pos = {x = 0, y = 0}
  local ok_h, hub = pcall(function() return platform.hub end)
  if ok_h and hub and hub.valid then pos = hub.position end
  if surf and surf.valid then
    pcall(function()
      player.set_controller{type = defines.controllers.remote, surface = surf, position = pos}
    end)
    player.print("[space-map-rework] Remote View → платформа «" .. (slot.name or "?") .. "»")
  else
    player.print("[space-map-rework] У платформы «" .. (slot.name or "?") .. "» нет поверхности")
  end
end

-- --- Камера предпросмотра платформы ---
local PLATFORM_CAM_FRAME = "space-map-rework-platform-cam"
-- окно планеты (приоритет над камерой; имя здесь — обе секции видны ниже)
local PLANET_INFO_FRAME = "space-map-rework-planet-info"

-- Мировая позиция слота (слот вращается вместе с телом).
local function platform_slot_world_pos(body, slot)
  local dist = platform_slot_dist(body)
  return body.position.x + math.cos(slot.angle) * dist,
         body.position.y + math.sin(slot.angle) * dist
end

-- Мировая позиция -> экранные GUI-пиксели. Центр камеры = player.position.
-- player.zoom доступен только у remote/god; для character — PLATFORM_CURSOR_ZOOM.
local function world_to_screen(player, wx, wy)
  local res = player.display_resolution
  local scale = player.display_scale or 1
  if scale <= 0 then scale = 1 end
  local zoom = PLATFORM_CURSOR_ZOOM
  local ok, z = pcall(function() return player.zoom end)
  if ok and type(z) == "number" and z > 0 then zoom = z end
  local sx = (res.width  / 2 + (wx - player.position.x) * 32 * zoom) / scale
  local sy = (res.height / 2 + (wy - player.position.y) * 32 * zoom) / scale
  return sx, sy
end

-- Размещение окна у мировой точки с оффсетом и клампом в экран.
-- state = {lx, ly} — сглаживание: доля HOVER_GUI_SMOOTHING пути за тик,
-- максимум HOVER_GUI_MAX_STEP px/тик.
local function place_frame_near(player, frame, wx, wy, w, h, off_x, off_y, state)
  if not (frame and frame.valid) then return end
  local sx, sy = world_to_screen(player, wx, wy)
  local res = player.display_resolution
  local scale = player.display_scale or 1
  if scale <= 0 then scale = 1 end
  local lx = math.max(4, math.min(sx + off_x, res.width  / scale - (w + 14)))
  local ly = math.max(4, math.min(sy + off_y, res.height / scale - (h + 14)))
  if state and state.lx and state.ly then
    local dx, dy = lx - state.lx, ly - state.ly
    -- микродвижения пропускаются: location= инвалидирует layout всего окна
    -- (с камерой — перерендер viewport; заметная просадка fps)
    if dx * dx + dy * dy < 2.25 then return end
    -- установка позиции не чаще раза в 2 тика (30 Гц достаточно плавно)
    if state.ltick and (game.tick - state.ltick) < 2 then return end
    local k = HOVER_GUI_SMOOTHING or 0.35
    lx = state.lx + dx * k
    ly = state.ly + dy * k
    local maxs = HOVER_GUI_MAX_STEP or 22
    if lx - state.lx >  maxs then lx = state.lx + maxs end
    if state.lx - lx >  maxs then lx = state.lx - maxs end
    if ly - state.ly >  maxs then ly = state.ly + maxs end
    if state.ly - ly >  maxs then ly = state.ly - maxs end
  end
  if state then state.lx, state.ly = lx, ly; state.ltick = game.tick end
  pcall(function() frame.location = {x = lx, y = ly} end)
end

-- Окно камеры у курсора (якорь — маркер под курсором).
local function place_camera_frame_at_cursor(player, frame, hit, wx, wy, state)
  if wx == nil then
    if not (hit and hit.body and hit.body.position) then return end
    wx, wy = platform_slot_world_pos(hit.body, hit.slot)
  end
  place_frame_near(player, frame, wx, wy,
    PLATFORM_CAMERA_W + 20, PLATFORM_CAMERA_H + 44,
    PLATFORM_CAMERA_OFFSET_X, PLATFORM_CAMERA_OFFSET_Y, state)
end

-- Мировая позиция маркера под курсором (из hover-источника).
local function selected_marker_pos(player)
  local _, pos = hover_marker(player)
  if pos then return pos.x, pos.y end
  return nil, nil
end

-- Снятие ванильного выделения (selection-рамка) каждым тиком до рендера.
local function deselect_if_marker(player, names)
  pcall(function()
    local s = player.selected
    if s and s.valid and names[s.name] then
      player.clear_selected_entity()
    end
  end)
end

function close_platform_camera(player)
  local frame = player.gui.screen[PLATFORM_CAM_FRAME]
  if frame and frame.valid then frame.destroy() end
  storage.platform_camera = storage.platform_camera or {}
  storage.platform_camera[player.index] = nil
end

-- Центр/зум камеры по bbox сгенерированных чанков поверхности платформы
-- (чанки генерятся только под постройки). Возвращает {x, y, zoom, area} или nil.
local function platform_camera_fit(surf)
  local ok, res = pcall(function()
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    local any = false
    for chunk in surf.get_chunks() do
      local a = chunk.area
      if a and a.left_top and a.right_bottom then
        any = true
        if a.left_top.x < minx then minx = a.left_top.x end
        if a.left_top.y < miny then miny = a.left_top.y end
        if a.right_bottom.x > maxx then maxx = a.right_bottom.x end
        if a.right_bottom.y > maxy then maxy = a.right_bottom.y end
      end
    end
    if not any then return nil end
    local w = (maxx - minx) + 40   -- запас до краёв окна
    local h = (maxy - miny) + 40
    local zoom = math.min(PLATFORM_CAMERA_W / (32 * w), PLATFORM_CAMERA_H / (32 * h))
    -- ниже порога движок рисует картографический вид, а не живой мир
    zoom = math.max(PLATFORM_CAMERA_MIN_ZOOM or 0.09, math.min(zoom, 0.6))
    return {
      x = (minx + maxx) / 2, y = (miny + maxy) / 2, zoom = zoom,
      area = {{minx - 16, miny - 16}, {maxx + 16, maxy + 16}}
    }
  end)
  if ok then return res end
  return nil
end

-- Чарт поверхности платформы для силы игрока: иначе камера показывает
-- туман войны.
local function chart_platform_for_viewer(player, surf, fit)
  pcall(function()
    if fit and fit.area then
      player.force.chart(surf, fit.area)
    else
      player.force.chart(surf, {{-80, -80}, {80, 80}})
    end
  end)
end

-- Вызывается каждый тик: держит окошко камеры синхронным с курсором игрока.
-- Летящая платформа под курсором: по позициям travel-меток в
-- storage.travel_marks (заполняет routes.lua каждый тик).
-- Возвращает {force, index, name, from_name, to_name, x, y, ...} или nil.
function find_hovered_travel_mark(probe_pos)
  if not probe_pos then return nil end
  local cap = TRAVEL_MARKER_CAPTURE or 1.2
  local best, best_d2 = nil, nil
  for _, m in pairs(storage.travel_marks or {}) do
    if m.x and m.y then
      local dx, dy = m.x - probe_pos.x, m.y - probe_pos.y
      local d2 = dx * dx + dy * dy
      if d2 <= cap * cap and (not best_d2 or d2 < best_d2) then
        best_d2 = d2
        best = {
          force = m.force, index = m.index, name = m.name,
          from_name = m.from_name, to_name = m.to_name,
          x = m.x, y = m.y,
          progress = m.progress, km_total = m.km_total
        }
      end
    end
  end
  return best
end

-- "15 000": пробелы-разделители тысяч
local function fmt_num(v)
  local s = tostring(math.floor(v + 0.5))
  local rev = s:reverse():gsub("(%d%d%d)", "%1 ")
  return (rev:reverse():gsub("^%s", ""))
end

-- Строка прогресса рейса (только платформы в пути): проценты +
-- пройдено/всего км (км — из длины прототипа коннекшена).
local function travel_flight_caption(m)
  local frac = m.progress or 0
  local pct = math.floor(frac * 100 + 0.5)
  local s = "Прогресс: " .. pct .. "%"
  if type(m.km_total) == "number" and m.km_total > 0 then
    s = s .. "  ·  " .. fmt_num(frac * m.km_total) .. " / " .. fmt_num(m.km_total) .. " км"
  end
  return s
end

-- Иконка + имя тела: "[space-location=n] LocalisedName"
local function space_loc_tag(name)
  local lname = name
  local ok_p, p = pcall(function()
    return prototypes.space_location[name] or prototypes.planet[name]
  end)
  if ok_p and p then
    local ok_l, ln = pcall(function() return p.localised_name end)
    if ok_l and ln then lname = ln end
  end
  return {"", "[space-location=" .. name .. "] ", lname}
end

-- Рейс платформы: from/to. Стоянка — текущее тело. Цель — текущая запись
-- расписания; иначе имена travel-метки. Возврат: a, b (или nil), traveling.
local function platform_route_names(platform, view)
  local ok_c, conn = pcall(function() return platform.space_connection end)
  local traveling = ok_c and conn ~= nil
  local from_name = nil
  local ok_lv, lv = pcall(function() return platform.last_visited_space_location end)
  if ok_lv and lv then
    local ok_n, n = pcall(function() return lv.name end)
    if ok_n then from_name = n end
  end
  local at_name = nil
  local ok_loc, loc = pcall(function() return platform.space_location end)
  if ok_loc and loc then
    local ok_n, n = pcall(function() return loc.name end)
    if ok_n then at_name = n end
  end
  if not traveling then return (at_name or from_name), nil, false end
  local to_name = nil
  local ok_s, dn = pcall(function()
    local sch = platform.get_schedule()
    if not (sch and sch.valid) then return nil end
    local recs = nil
    pcall(function() recs = sch.records end)
    if not recs then return nil end
    local cur = 1
    pcall(function() cur = sch.current or 1 end)
    local r = recs[cur] or recs[#recs]
    return r and r.station or nil
  end)
  if ok_s and type(dn) == "string" then to_name = dn end
  if not to_name and view then to_name = view.to_name end
  if not from_name and view then from_name = view.from_name end
  if not from_name then from_name = at_name end
  -- защита от "летит nauvis -> nauvis": запись расписания в момент отлёта
  -- может указывать на тело вылета; концы коннекшена дают второй конец
  -- однозначно (направление — по совпадению from_name с from/to прототипа)
  if to_name == from_name or not to_name then
    local cf, ct = nil, nil
    local ok_f, vf = pcall(function() local f = conn.from return f and f.name end)
    if ok_f then cf = vf end
    local ok_t, vt = pcall(function() local t = conn.to return t and t.name end)
    if ok_t then ct = vt end
    if cf and ct then
      if from_name == cf then to_name = ct
      elseif from_name == ct then to_name = cf
      elseif not to_name then to_name = ct end
    end
  end
  return from_name, to_name, true
end

-- Строка рейса: "[ик] A → [ик] B"; стоянка: "[ик] A"; равные концы —
-- одно тело (ошибочная пара не показывается).
local function platform_route_caption(platform, view)
  local a, b, traveling = platform_route_names(platform, view)
  if traveling then
    if a and b and a == b then return {"", space_loc_tag(a)} end
    return {"", space_loc_tag(a or "?"), "  →  ", space_loc_tag(b or "?")}
  end
  if a then return {"", space_loc_tag(a)} end
  return ""
end

-- Полёт: доля пути и длина коннекшена (км); nil — не в пути.
-- platform.distance: доля [0,1] на коннекшене (документировано 2.1).
local function platform_flight_info(platform)
  local ok_c, conn = pcall(function() return platform.space_connection end)
  if not (ok_c and conn) then return nil end
  local ok_l, len = pcall(function() return conn.length end)
  local ok_d, d = pcall(function() return platform.distance end)
  local total = (ok_l and type(len) == "number" and len > 0) and len or nil
  local frac = nil
  if ok_d and type(d) == "number" and total then
    if d <= 1 then frac = d else frac = math.min(math.max(d / total, 0), 1) end
    frac = math.min(math.max(frac, 0), 1)
  end
  return {frac = frac, total = total}
end

local function flight_km_caption(finfo)
  if finfo and finfo.frac and finfo.total then
    return fmt_num(finfo.frac * finfo.total) .. " км"
  end
  return ""
end

-- Имена платформ, стоящих у тела (live: force.platforms -> space_location).
local function parked_platform_names(body_name)
  local names = {}
  for _, force in pairs(game.forces) do
    if force and force.valid then
      local ok, plats = pcall(function() return force.platforms end)
      if ok and plats then
        for _, platform in pairs(plats) do
          local ok_l, loc = pcall(function()
            if not platform.valid then return nil end
            return platform.space_location
          end)
          if ok_l and loc and loc.name == body_name then
            local ok_n, nm = pcall(function() return platform.name end)
            names[#names + 1] = (ok_n and nm and nm ~= "") and nm or "platform"
          end
        end
      end
    end
  end
  table.sort(names)
  return names
end

-- Подпись hover-списка стоячих платформ: счёт + имена построчно;
-- nil — платформ у тела нет.
local function parked_list_caption(body_name)
  local names = parked_platform_names(body_name)
  if #names == 0 then return nil end
  local head = "Платформы: " .. #names
  for i, n in ipairs(names) do names[i] = "• " .. n end
  return head .. "\n" .. table.concat(names, "\n")
end


-- Каждый тик: синхронизация окна камеры с курсором. Единый путь для
-- припаркованной платформы (слот) и летящей (travel-метка).
function update_platform_camera(player)
  if not (player and player.valid) then return end
  storage.platform_camera = storage.platform_camera or {}

  -- приоритет окна планеты: пока оно открыто, камера закрыта и не открывается
  local pfr = player.gui.screen[PLANET_INFO_FRAME]
  if pfr and pfr.valid then
    if storage.platform_camera[player.index] then close_platform_camera(player) end
    return
  end

  local slot_hit, travel_hit = nil, nil
  if player.surface and player.surface.name == SURFACE_NAME then
    -- player.selected к этому моменту уже снят event-хендлером
    local _, probe_pos = hover_marker(player)
    if probe_pos then
      slot_hit = find_hovered_platform_slot(player, probe_pos)
      if not slot_hit then travel_hit = find_hovered_travel_mark(probe_pos) end
    end
  end
  local cur = storage.platform_camera[player.index]

  -- маркер платформы под курсором: ванильная рамка снимается
  if slot_hit or travel_hit then
    deselect_if_marker(player, {
      ["space-map-rework-platform-marker"] = true,
      ["space-map-rework-travel-marker"] = true
    })
  end

  -- единое view: источник (парковка/полёт); якорь окна — позиция маркера
  -- текущего тика (пробник события может запаздывать)
  local view = nil
  if slot_hit then
    -- один значок на тело: hover — список платформ у этого тела
    local wx, wy = platform_slot_world_pos(slot_hit.body, slot_hit.slot)
    view = {
      key = "PL:" .. tostring(slot_hit.body.prototype_name),
      list = true,
      wx = wx, wy = wy,
      title = starmap_body_localised_name(slot_hit.body.prototype_name),
      body_name = slot_hit.body.prototype_name, slot_i = slot_hit.slot_index
    }
  elseif travel_hit then
    view = {
      key = "T:" .. tostring(travel_hit.force) .. ":" .. tostring(travel_hit.index),
      force = travel_hit.force, index = travel_hit.index,
      wx = travel_hit.x, wy = travel_hit.y,
      title = {"", travel_hit.name or "platform"},
      from_name = travel_hit.from_name, to_name = travel_hit.to_name,
      travel = true,
      progress = travel_hit.progress,
      flight = travel_flight_caption(travel_hit)
    }
  end

  -- у закреплённой платформы своё следящее окно — hover-окно не открывается
  if view then
    local plist = storage.pinned_platforms and storage.pinned_platforms[player.index]
    for _, e in ipairs(plist or {}) do
      if e.force == view.force and e.index == view.index then view = nil break end
    end
  end

  if view then
    if cur and cur.key == view.key then
      -- та же платформа: окно следует за маркером
      cur.last_seen = game.tick
      local frame = player.gui.screen[PLATFORM_CAM_FRAME]
      if view.list then
        if frame and frame.valid then
          if game.tick % 30 == 0 then
            local cap = parked_list_caption(view.body_name)
            if not cap then close_platform_camera(player) return end
            if cap ~= (cur.list_caption or "") then
              cur.list_caption = cap
              local ll = frame.list_line
              if ll and ll.valid then pcall(function() ll.caption = cap end) end
            end
          end
          place_camera_frame_at_cursor(player, frame, nil, view.wx, view.wy, cur)
        end
        return
      end
      local platform = find_space_platform(view.force, view.index)
      if frame and frame.valid and platform then
        -- маршрут: раз в 60 тиков, caption — только при изменении
        if game.tick % 60 == 0 then
          local route_a, route_b = platform_route_names(platform, view)
          local rkey = tostring(route_a) .. ">" .. tostring(route_b)
          if rkey ~= (cur.route_key or "") then
            cur.route_key = rkey
            local rl = frame.route_line
            if rl and rl.valid then
              pcall(function() rl.caption = platform_route_caption(platform, view) end)
            end
          end
        end
        -- полоса полёта: обновление каждые 10 тиков; видимость — по смене
        -- статуса рейса, caption — только при изменении текста (layout дорогой)
        if game.tick % 10 == 0 then
          -- источник — live-данные платформы (space_connection/distance),
          -- не travel-метки: работает и для парковки, и для рейса
          local finfo = platform_flight_info(platform)
          local want = finfo ~= nil
          local ff = frame.flight_flow
          if ff and ff.valid then
            if want ~= (cur.flight_shown or false) then
              cur.flight_shown = want
              pcall(function() ff.visible = want end)
            end
            if finfo and finfo.frac then
              local fb = ff.flight_bar
              if fb and fb.valid then pcall(function() fb.value = finfo.frac end) end
              local cap = flight_km_caption(finfo)
              if cap ~= (cur.km_caption or "") then
                cur.km_caption = cap
                local kl = ff.flight_km
                if kl and kl.valid then pcall(function() kl.caption = cap end) end
              end
            end
          end
        end
        place_camera_frame_at_cursor(player, frame, nil, view.wx, view.wy, cur)
      end
      return
    end

    -- новая платформа: открыть окно (текстовое, без камеры — вторая вьюпорт
    -- отрисовка движком каждый кадр грузила fps)
    if cur then close_platform_camera(player) end

    if view.list then
      -- значок тела: окно — список стоячих платформ (без маршрута/полосы)
      local cap0 = parked_list_caption(view.body_name)
      if not cap0 then return end
      local frame = nil
      pcall(function()
        frame = player.gui.screen.add{
          type = "frame",
          name = PLATFORM_CAM_FRAME,
          direction = "vertical",
          style = "tooltip_frame"
        }
        frame.add{
          type = "label",
          caption = view.title,
          style = "tooltip_title_label"
        }
        local ll = frame.add{
          type = "label",
          name = "list_line",
          caption = cap0,
          style = "tooltip_label"
        }
        ll.style.single_line = false
      end)
      if frame and frame.valid then
        local state = {
          key = view.key,
          list = true,
          body_name = view.body_name,
          slot_i = view.slot_i,
          list_caption = cap0,
          last_seen = game.tick
        }
        place_camera_frame_at_cursor(player, frame, nil, view.wx, view.wy, state)
        storage.platform_camera[player.index] = state
      end
      return
    end

    local platform = find_space_platform(view.force, view.index)
    if not platform then return end

    -- рейс/маршрут считаются до создания окна (нужны в state)
    local finfo0 = platform_flight_info(platform)
    local route_a, route_b = platform_route_names(platform, view)

    local frame = nil
    pcall(function()
      frame = player.gui.screen.add{
        type = "frame",
        name = PLATFORM_CAM_FRAME,
        direction = "vertical",
        style = "tooltip_frame"
      }
      frame.add{
        type = "label",
        caption = view.title,
        style = "tooltip_title_label"
      }
      -- маршрут рейса с иконками тел (как в ванильном окне платформы);
      -- на стоянке — одно тело
      frame.add{
        type = "label",
        name = "route_line",
        caption = platform_route_caption(platform, view),
        style = "tooltip_label"
      }
      -- полоса полёта: прогресс + пройденные км; скрыта на стоянке
      local ff = frame.add{
        type = "flow",
        name = "flight_flow",
        direction = "horizontal"
      }
      ff.style.top_margin = 3
      local bar = ff.add{
        type = "progressbar",
        name = "flight_bar",
        value = (finfo0 and finfo0.frac) or 0
      }
      bar.style.width = PLATFORM_CAMERA_W - 92
      local km = ff.add{
        type = "label",
        name = "flight_km",
        caption = flight_km_caption(finfo0),
        style = "tooltip_label"
      }
      km.style.left_margin = 6
      if not finfo0 then ff.visible = false end
    end)
    if frame and frame.valid then
      local state = {
        key = view.key,
        force = view.force,
        index = view.index,
        body_name = view.body_name,
        slot_i = view.slot_i,
        travel = view.travel,
        flight_shown = (finfo0 ~= nil),
        km_caption = flight_km_caption(finfo0),
        route_key = tostring(route_a) .. ">" .. tostring(route_b),
        last_seen = game.tick
      }
      place_camera_frame_at_cursor(player, frame, nil, view.wx, view.wy, state)
      storage.platform_camera[player.index] = state
    end
    return
  end

  -- курсор не на маркере платформы: окно живёт ещё HOVER_GRACE тиков
  if cur then
    if (game.tick - (cur.last_seen or 0)) <= HOVER_GRACE then
      local frame = player.gui.screen[PLATFORM_CAM_FRAME]
      local wx, wy = nil, nil
      if cur.travel then
        -- летящая: свежая позиция метки (grace, метка ещё жива)
        local m = storage.travel_marks and storage.travel_marks[cur.key:sub(3)]
        if m and m.x then wx, wy = m.x, m.y end
      else
        local b = storage.planet_by_name and storage.planet_by_name[cur.body_name]
        local slot = b and b.platform_slots and b.platform_slots[cur.slot_i]
        if b and slot then wx, wy = platform_slot_world_pos(b, slot) end
      end
      if frame and frame.valid and wx then
        place_camera_frame_at_cursor(player, frame, nil, wx, wy, cur)
        return
      end
    end
    close_platform_camera(player)
  end
end

-- --- Инфо-окно планеты при наведении ---
function close_planet_info(player)
  local frame = player.gui.screen[PLANET_INFO_FRAME]
  if frame and frame.valid then frame.destroy() end
  storage.planet_info = storage.planet_info or {}
  storage.planet_info[player.index] = nil
end

-- Тело по наведённому маркеру: "space-map-rework-marker-<proto>" -> proto, либо
-- базовый маркер -> ближайшее тело по позиции.
local function body_of_marker(sel_name, sel_pos)
  local pname = string.match(sel_name or "", "^space%-map%-rework%-marker%-(.+)$")
  if pname and storage.planet_by_name then
    return storage.planet_by_name[pname]
  end
  if sel_name == "space-map-rework-planet-marker" and sel_pos then
    local best, best_d2 = nil, nil
    for _, b in ipairs(storage.planets or {}) do
      if b.position then
        local dx, dy = b.position.x - sel_pos.x, b.position.y - sel_pos.y
        local d2 = dx * dx + dy * dy
        local cap = (b.icon_radius or 1) + 0.6
        if d2 <= cap * cap and (not best_d2 or d2 < best_d2) then
          best, best_d2 = b, d2
        end
      end
    end
    return best
  end
  return nil
end

function update_planet_info(player)
  if not (player and player.valid) then return end
  storage.planet_info = storage.planet_info or {}

  local sel_name, sel_pos = nil, nil
  if player.surface and player.surface.name == SURFACE_NAME then
    sel_name, sel_pos = hover_marker(player)
  end

  local body = nil
  if sel_name and sel_name ~= "space-map-rework-platform-marker" then
    body = body_of_marker(sel_name, sel_pos)
  end
  -- инфо-окно — только исследованные тела (PLANET_DISCOVERY_GATED)
  if body and PLANET_DISCOVERY_GATED ~= false
     and not starmap_body_unlocked(body.prototype_name) then
    body = nil
  end

  -- обводка тела: жёлтая у наведённого (определение тела — как у инфо-окна)
  starmap_update_hover_ring(player, body)

  local cur = storage.planet_info[player.index]

  if body then
    -- снятие ванильной обводки и тултипа
    pcall(function() player.clear_selected_entity() end)
    -- приоритет окна планеты: камера платформы закрывается
    close_platform_camera(player)
    local key = body.prototype_name

    if not (cur and cur.key == key) then
      -- открыть новое окно
      if cur then close_planet_info(player) end

      -- окно только с текстом (стили tooltip_frame / tooltip_title_label)
      local state = {
        key = key, last_seen = game.tick,
        w = 372, h = 240,
      }

      local frame = nil
      pcall(function()
        -- текст описания собран в data-final-fixes.lua
        frame = player.gui.screen.add{
          type = "frame",
          name = PLANET_INFO_FRAME,
          direction = "vertical",
          style = "tooltip_frame"
        }
        frame.style.padding = 6
        pcall(function() frame.ignored_by_interaction = true end)

        local eproto = nil
        local ok_ep, ep = pcall(function() return prototypes.entity[sel_name] end)
        if ok_ep then eproto = ep end

        local title_caption = nil
        local ok_ln, ln = pcall(function() return eproto and eproto.localised_name end)
        if ok_ln and ln then title_caption = ln end
        if not title_caption then title_caption = starmap_body_localised_name(body.prototype_name) end
        frame.add{type = "label", caption = title_caption, style = "tooltip_title_label"}

        local descr = nil
        local ok_ld, ld = pcall(function() return eproto and eproto.localised_description end)
        if ok_ld and ld then descr = ld end
        if not descr then descr = build_card_text(body.prototype_name) end

        local lbl = frame.add{
          type = "label",
          name = "info_text",
          caption = descr,
          style = "tooltip_label"
        }
        lbl.style.single_line = false
      end)
      if frame and frame.valid then
        cur = state
        storage.planet_info[player.index] = state
      end
    else
      cur.last_seen = game.tick
    end

    -- якорь окна — body.position текущего тика; пробник определяет только объект
    if cur and body and body.position then
      local frame = player.gui.screen[PLANET_INFO_FRAME]
      if frame and frame.valid then
        place_frame_near(player, frame, body.position.x, body.position.y,
          cur.w or 372, cur.h or 300, PLANET_INFO_OFFSET_X, PLANET_INFO_OFFSET_Y, cur)
      end
    end
    return
  end

  -- курсор не на маркере: grace-удержание (перевыделение движком после
  -- clear_selected_entity идёт с пропусками), затем закрытие
  if cur then
    local b = storage.planet_by_name and storage.planet_by_name[cur.key]
    if (game.tick - (cur.last_seen or 0)) <= HOVER_GRACE and b and b.position then
      local frame = player.gui.screen[PLANET_INFO_FRAME]
      if frame and frame.valid then
        place_frame_near(player, frame, b.position.x, b.position.y,
          cur.w or 372, cur.h or 300, PLANET_INFO_OFFSET_X, PLANET_INFO_OFFSET_Y, cur)
      end
    else
      close_planet_info(player)
    end
  end
end

function toggle_info_cards(player)
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid then return end
  storage.info_visible = not storage.info_visible

  if storage.info_visible then
    for _, planet in ipairs(storage.planets or {}) do
      local shown = planet.discovered
      if shown and PLANET_DISCOVERY_GATED ~= false then
        shown = starmap_body_unlocked(planet.prototype_name)
      end
      if shown then
        r_destroy(planet.card_render_id)
        local x = planet.position.x
        local y = planet.position.y
        local offset_x = (x >= 0) and 5 or -5
        local align = (x >= 0) and "left" or "right"
        local card_text = build_card_text(planet.prototype_name)
        local ok, obj = pcall(function()
          return rendering.draw_text{
            text = card_text,
            surface = surface,
            target = {x = x + offset_x, y = y},
            color = {r = 0.92, g = 0.92, b = 0.92, a = 0.9},
            scale = 0.68,
            alignment = align
          }
        end)
        if ok and obj then
          planet.card_render_id = obj.id
          planet.last_side = (x >= 0) and "right" or "left"
          r_bring_front(obj.id)
        end
      end
    end
    if player then player.print("[space-map-rework] Карточки (условия+ресурсы): ВКЛ") end
  else
    for _, planet in ipairs(storage.planets or {}) do
      r_destroy(planet.card_render_id)
      planet.card_render_id = nil
      planet.last_side = nil
    end
    if player then player.print("[space-map-rework] Карточки: ВЫКЛ") end
  end
end

function handle_planet_click(player, cursor_pos)
  if not player or not player.valid or not storage.planets then return end
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid then return end
  if player.surface.name ~= SURFACE_NAME then
    if not (player.physical_surface and player.physical_surface.name == SURFACE_NAME) then return end
  end

  -- 0) маркер платформы: ПКМ -> Remote View платформы.
  --    Клик не перебивается, если выделен маркер планеты.
  do
    local sel0 = player.selected
    local sel_is_planet = sel0 and sel0.valid and sel0.name
      and string.find(sel0.name, "space-map-rework-marker-", 1, true) ~= nil
    local sel_is_platform = sel0 and sel0.valid and sel0.name == "space-map-rework-platform-marker"
    local hit = nil
    if sel_is_platform then
      hit = find_hovered_platform_slot(player, nil)
    elseif not sel_is_planet and cursor_pos then
      hit = find_hovered_platform_slot(player, cursor_pos)
    end
    if hit then
      open_platform_remote_view(player, hit.slot)
      return
    end
    -- ПКМ по летящей платформе (travel-метка) -> тот же Remote View
    if not sel_is_planet and cursor_pos then
      local thit = find_hovered_travel_mark(cursor_pos)
      if thit then
        open_platform_remote_view(player, {force = thit.force, index = thit.index, name = thit.name})
        return
      end
    end
  end

  -- 1) по выделенной сущности (маркеры различаются по имени)
  local target_planet = nil
  local selected = player.selected
  if selected and selected.valid then
    for _, planet in ipairs(storage.planets) do
      if string.find(selected.name or "", planet.prototype_name) then
        target_planet = planet
        break
      end
    end
  end

  -- 2) по позиции курсора
  if not target_planet and cursor_pos then
    local cx = cursor_pos.x or cursor_pos[1]
    local cy = cursor_pos.y or cursor_pos[2]
    local best_score = nil
    for _, planet in ipairs(storage.planets) do
      if planet.discovered and planet.position then
        local dx = planet.position.x - cx
        local dy = planet.position.y - cy
        local d = math.sqrt(dx * dx + dy * dy)
        local capture = (planet.icon_radius or 1) + 0.25
        if d <= capture then
          local score = d - capture
          if not best_score or score < best_score then
            best_score = score
            target_planet = planet
          end
        end
      end
    end
  end

  -- 3) по позиции игрока
  if not target_planet then
    local px = player.position.x
    local py = player.position.y
    local best_score = nil
    for _, planet in ipairs(storage.planets) do
      if planet.discovered and planet.position then
        local dx = planet.position.x - px
        local dy = planet.position.y - py
        local d = math.sqrt(dx * dx + dy * dy)
        local capture = (planet.icon_radius or 1) + 0.35
        if d <= capture then
          local score = d - capture
          if not best_score or score < best_score then
            best_score = score
            target_planet = planet
          end
        end
      end
    end
  end

  if not target_planet then return end
  local planet_name = target_planet.prototype_name

  -- Remote View на поверхность — только после исследования тела
  -- (PLANET_DISCOVERY_GATED; starmap_body_unlocked — starsystem.lua)
  if PLANET_DISCOVERY_GATED ~= false and not starmap_body_unlocked(planet_name) then
    player.print("[space-map-rework] Тело не исследовано: " .. planet_name)
    return
  end

  local target_surface = nil
  local found = false
  if game.planets and game.planets[planet_name] then
    local lp = game.planets[planet_name]
    if lp.surface and lp.surface.valid then
      target_surface = lp.surface
      found = true
    else
      local ok, surf = pcall(function() return lp.create_surface() end)
      if ok and surf then
        target_surface = surf
        found = true
      end
    end
  end
  if not found and game.surfaces[planet_name] and game.surfaces[planet_name].valid then
    target_surface = game.surfaces[planet_name]
    found = true
  end
  if not found and (planet_name == "solar-system-edge" or planet_name == "shattered-planet") then
    player.print("[space-map-rework] " .. planet_name .. " — без поверхности")
    local nauvis = game.surfaces["nauvis"]
    target_surface = nauvis
    found = (nauvis ~= nil)
  end

  if found and target_surface then
    pcall(function() player.game_view_settings.show_quickbar = true end)
    pcall(function()
      player.set_controller{type = defines.controllers.remote, surface = target_surface, position = {0, 0}}
    end)
    player.print("[space-map-rework] Remote View → " .. planet_name)
  else
    player.print("[space-map-rework] Нет поверхности для " .. planet_name)
  end
end

-- === Закреплённые платформы (SHIFT+P): следящее окно-камера ===
-- Окно постоянно у маркера платформы: у паркованной следует за слотом вокруг
-- планеты, у летящей — за меткой на пути.
local PIN_FOLLOW_FRAME = "space-map-rework-pinf"

-- Платформа под курсором: парковочный слот или летящая метка.
-- Возвращает {force, index, name, kind} или nil. Глобально (events.lua).
function starmap_hovered_platform(player)
  if not (player and player.valid) then return nil end
  if not (player.surface and player.surface.name == SURFACE_NAME) then return nil end
  local _, probe_pos = hover_marker(player)
  if not probe_pos then return nil end
  local slot_hit = find_hovered_platform_slot(player, probe_pos)
  if slot_hit then
    return {force = slot_hit.slot.force, index = slot_hit.slot.index,
            name = slot_hit.slot.name, kind = "parked"}
  end
  local tr = find_hovered_travel_mark(probe_pos)
  if tr then
    return {force = tr.force, index = tr.index, name = tr.name, kind = "travel"}
  end
  return nil
end

-- Удаление всех следящих окон игрока (пересоздаются на следующем тике).
function destroy_pinned_follows(player)
  if not (player and player.valid) then return end
  for i = 1, 64 do
    local f = player.gui.screen[PIN_FOLLOW_FRAME .. "_" .. i]
    if not f then break end
    if f.valid then f.destroy() end
  end
  if storage.pinned_state then storage.pinned_state[player.index] = {} end
end

-- SHIFT+P: закреп/откреп наведённой платформы. Окна пересоздаются на
-- следующем тике update_pinned_follows.
function toggle_pin_platform(player, hit)
  if not (player and player.valid and hit) then return end
  storage.pinned_platforms = storage.pinned_platforms or {}
  local list = storage.pinned_platforms[player.index]
  if not list then list = {}; storage.pinned_platforms[player.index] = list end
  for i, e in ipairs(list) do
    if e.force == hit.force and e.index == hit.index then
      table.remove(list, i)
      player.print("[space-map-rework] Платформа «" .. (hit.name or "?") .. "» ОТКРЕПЛЕНА")
      destroy_pinned_follows(player)
      return
    end
  end
  table.insert(list, {force = hit.force, index = hit.index, name = hit.name or "platform"})
  player.print("[space-map-rework] Платформа «" .. (hit.name or "?")
    .. "» ЗАКРЕПЛЕНА — окно-камера следует за ней на карте (открепить: SHIFT+P или ✖)")
  destroy_pinned_follows(player)
end

-- Текущая мировая позиция маркера платформы: парковочный слот (следует за
-- вращением тела) или метка на пути.
-- Возвращает wx, wy, mode ("parked"/"travel"), body_name.
local function pinned_anchor(force_name, index)
  for _, b in ipairs(storage.planets or {}) do
    if b.platform_slots and b.position then
      for _, slot in ipairs(b.platform_slots) do
        if slot.force == force_name and slot.index == index then
          local wx, wy = platform_slot_world_pos(b, slot)
          return wx, wy, "parked", b.prototype_name
        end
      end
    end
  end
  local m = storage.travel_marks and storage.travel_marks[force_name .. ":" .. tostring(index)]
  if m and m.x then return m.x, m.y, "travel", nil end
  return nil
end

-- Одно следящее окно: создание/режим/содержимое/позиция.
local function pinned_follow_tick(player, i, e, stt)
  local fname = PIN_FOLLOW_FRAME .. "_" .. i
  local platform = find_space_platform(e.force, e.index)
  if not platform then
    -- платформа недоступна: авто-откреп
    local list = storage.pinned_platforms[player.index]
    if list then
      for j, x in ipairs(list) do
        if x.force == e.force and x.index == e.index then table.remove(list, j) break end
      end
    end
    player.print("[space-map-rework] Платформа «" .. (e.name or "?") .. "» недоступна — откреплена")
    destroy_pinned_follows(player)
    return
  end

  local wx, wy, mode, body_name = pinned_anchor(e.force, e.index)
  if not wx then return end -- переходное состояние (старт/посадка)

  local frame = player.gui.screen[fname]
  -- смена режима (parked/travel) или отсутствие окна -> пересоздание
  if (not (frame and frame.valid)) or stt.mode ~= mode then
    if frame and frame.valid then frame.destroy() end
    local surf = nil
    pcall(function() surf = platform.surface end)
    if not (surf and surf.valid) then return end
    local fit = platform_camera_fit(surf)
    local zoom = (fit and fit.zoom) or PLATFORM_CAMERA_ZOOM
    local pos = {x = 0, y = 0}
    if fit then pos = {x = fit.x, y = fit.y} end
    local ok_h, hub = pcall(function() return platform.hub end)
    if ok_h and hub and hub.valid then pos = hub.position end
    chart_platform_for_viewer(player, surf, fit)

    local title
    if mode == "travel" then
      local m = storage.travel_marks and storage.travel_marks[e.force .. ":" .. tostring(e.index)]
      title = {"", e.name or "platform", "  ·  ",
               tostring((m and m.from_name) or "?") .. " → " .. tostring((m and m.to_name) or "?")}
    else
      title = {"", e.name or "platform", "  ·  ", starmap_body_localised_name(body_name or "?")}
    end

    local ok = pcall(function()
      frame = player.gui.screen.add{
        type = "frame", name = fname, direction = "vertical",
        style = "tooltip_frame"
      }
      frame.style.padding = 6
      local head = frame.add{type = "flow", name = "head", direction = "horizontal"}
      local nm = head.add{type = "label", name = "nm", caption = title, style = "tooltip_title_label"}
      nm.style.top_padding = 4
      local dragf = head.add{type = "empty-widget", name = "spacer"}
      dragf.style.horizontally_stretchable = true
      head.add{
        type = "button", name = "space-map-rework-pin-remove", caption = "✖",
        style = "tool_button_red", tags = {pin_i = i}, tooltip = "Открепить платформу"
      }
      -- прогресс рейса (только travel): progressbar + строка
      if mode == "travel" then
        local m = storage.travel_marks and storage.travel_marks[e.force .. ":" .. tostring(e.index)]
        local bar = frame.add{type = "progressbar", name = "flight_bar", value = (m and m.progress) or 0}
        bar.style.width = PIN_CAMERA_W or 220
        local fl = frame.add{type = "label", name = "flight_progress",
          caption = m and travel_flight_caption(m) or "", style = "tooltip_label"}
        pcall(function() fl.style.font_color = {r = 0.55, g = 0.95, b = 0.55} end)
      end
      local cam = frame.add{
        type = "camera", name = "cam",
        position = pos, surface_index = surf.index, zoom = zoom
      }
      cam.style.width = PIN_CAMERA_W or 220
      cam.style.height = PIN_CAMERA_H or 146
    end)
    if not ok then return end
    stt.mode = mode
    stt.lx, stt.ly = nil, nil -- сброс позиционирования
  end

  if not (frame and frame.valid) then return end

  -- содержимое: периодический пересчёт камеры и прогресса рейса
  if game.tick % 30 == (i % 30) then
    pcall(function()
      local surf = platform.surface
      if surf and surf.valid then
        local fit = platform_camera_fit(surf)
        local ok_h, hub = pcall(function() return platform.hub end)
        local cam = frame["cam"]
        if cam and cam.valid then
          if ok_h and hub and hub.valid then cam.position = hub.position
          elseif fit then cam.position = {x = fit.x, y = fit.y} end
          if fit then cam.zoom = fit.zoom end
        end
        chart_platform_for_viewer(player, surf, fit)
      end
      -- заголовок обновляется при пересоздании окна (смена режима)
    end)
  end
  if mode == "travel" and game.tick % 10 == (i % 10) then
    local m = storage.travel_marks and storage.travel_marks[e.force .. ":" .. tostring(e.index)]
    if m then
      local fb = frame["flight_bar"]
      if fb and fb.valid then pcall(function() fb.value = m.progress or 0 end) end
      local fl = frame["flight_progress"]
      if fl and fl.valid then pcall(function() fl.caption = travel_flight_caption(m) end) end
      local nm = frame["head"] and frame["head"]["nm"]
      if nm and nm.valid then
        pcall(function()
          nm.caption = {"", e.name or "platform", "  ·  ",
            tostring(m.from_name or "?") .. " → " .. tostring(m.to_name or "?")}
        end)
      end
    end
  end

  -- окно следует за платформой (то же сглаживание, что у hover-окон)
  place_frame_near(player, frame, wx, wy,
    (PIN_CAMERA_W or 220) + 20, (PIN_CAMERA_H or 146) + (mode == "travel" and 76 or 52),
    PLATFORM_CAMERA_OFFSET_X, PLATFORM_CAMERA_OFFSET_Y, stt)
end

-- Каждый тик из events.lua: окна закрепов следуют за платформами.
-- Активно только на поверхности карты.
function update_pinned_follows(player)
  if not (player and player.valid) then return end
  storage.pinned_state = storage.pinned_state or {}
  local st = storage.pinned_state[player.index]
  if not st then st = {}; storage.pinned_state[player.index] = st end
  local on_map = player.surface and player.surface.name == SURFACE_NAME
  local list = storage.pinned_platforms and storage.pinned_platforms[player.index]
  if (not on_map) or not list or #list == 0 then
    destroy_pinned_follows(player)
    return
  end
  for i, e in ipairs(list) do
    if not st[i] then st[i] = {} end
    pcall(pinned_follow_tick, player, i, e, st[i])
  end
  -- удаление окон за пределами списка
  for i = #list + 1, #list + 8 do
    local f = player.gui.screen[PIN_FOLLOW_FRAME .. "_" .. i]
    if not f then break end
    if f.valid then f.destroy() end
    st[i] = nil
  end
end
