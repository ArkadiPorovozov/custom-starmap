-- control/gui.lua
-- Карточки характеристик (SHIFT+I), клик ПКМ → Remote View,
-- камера предпросмотра платформы при наведении (как в ванильном starmap)

-- === Платформы: поиск по слотам, камера при наведении, ПКМ → Remote View ===

-- LuaSpacePlatform по сохранённой идентичности (force + index).
-- В storage храним ТОЛЬКО строки/числа — LuaObject хранить нельзя.
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

-- Найти слот платформы, на который смотрит игрок:
-- приоритет — выделенная сущность-маркер (player.selected), иначе позиция курсора.
-- Возвращает {body = <storage body>, slot_index = i, slot = <slot>} или nil.
function find_hovered_platform_slot(player, cursor_pos)
  if not player or not player.valid or not storage.planets then return nil end
  local probe = nil
  local sel = player.selected
  if sel and sel.valid and sel.name == "custom-se-platform-marker" then
    probe = sel.position
  elseif cursor_pos then
    probe = {x = cursor_pos.x or cursor_pos[1], y = cursor_pos.y or cursor_pos[2]}
  end
  if not probe then return nil end

  local capture2 = (PLATFORM_MARKER_HALF + 0.6) * (PLATFORM_MARKER_HALF + 0.6)
  local best, best_d2 = nil, nil
  for _, b in ipairs(storage.planets) do
    if b.platform_slots and b.position then
      local dist = (b.icon_radius or 1) + PLATFORM_GAP
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

-- ПКМ по платформе → Remote View на её поверхность (как ПКМ по планете)
function open_platform_remote_view(player, slot)
  local platform = find_space_platform(slot.force, slot.index)
  if not platform then
    player.print("[custom-se-starmap] Платформа «" .. (slot.name or "?") .. "» не найдена (улетела?)")
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
    player.print("[custom-se-starmap] Remote View → платформа «" .. (slot.name or "?") .. "»")
  else
    player.print("[custom-se-starmap] У платформы «" .. (slot.name or "?") .. "» нет поверхности")
  end
end

-- --- Камера предпросмотра платформы (hover, как в ванильном starmap) ---
local PLATFORM_CAM_FRAME = "custom-se-platform-cam"

-- Мировая позиция слота платформы (тело крутится — слот тоже)
local function platform_slot_world_pos(body, slot)
  local dist = (body.icon_radius or 1) + PLATFORM_GAP
  return body.position.x + math.cos(slot.angle) * dist,
         body.position.y + math.sin(slot.angle) * dist
end

-- Мировая позиция -> экранные GUI-пиксели.
-- Центр камеры = player.position (так ведёт себя character- и remote-камера).
-- Зум читается только у remote/god; для character берём PLATFORM_CURSOR_ZOOM.
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

-- Окошко камеры РЯДОМ С КУРСОРОМ (т.е. рядом с маркером, который под курсором),
-- с оффсетом и без выхода за край экрана.
local function place_camera_frame_at_cursor(player, frame, hit)
  if not (frame and frame.valid and hit and hit.body and hit.body.position) then return end
  local wx, wy = platform_slot_world_pos(hit.body, hit.slot)
  local sx, sy = world_to_screen(player, wx, wy)
  local res = player.display_resolution
  local scale = player.display_scale or 1
  if scale <= 0 then scale = 1 end
  local max_x = res.width  / scale - (PLATFORM_CAMERA_W + 36)
  local max_y = res.height / scale - (PLATFORM_CAMERA_H + 60)
  local lx = math.max(4, math.min(sx + PLATFORM_CAMERA_OFFSET_X, max_x))
  local ly = math.max(4, math.min(sy + PLATFORM_CAMERA_OFFSET_Y, max_y))
  pcall(function() frame.location = {x = lx, y = ly} end)
end

function close_platform_camera(player)
  local frame = player.gui.screen[PLATFORM_CAM_FRAME]
  if frame and frame.valid then frame.destroy() end
  storage.platform_camera = storage.platform_camera or {}
  storage.platform_camera[player.index] = nil
end

-- Вызывается каждый тик: держит окошко камеры синхронным с курсором игрока.
function update_platform_camera(player)
  if not (player and player.valid) then return end
  storage.platform_camera = storage.platform_camera or {}

  local hit = nil
  if player.surface and player.surface.name == SURFACE_NAME then
    hit = find_hovered_platform_slot(player, nil)
  end
  local key = hit and (hit.slot.force .. ":" .. tostring(hit.slot.index)) or nil
  local cur = storage.platform_camera[player.index]

  -- та же платформа — подправить вид камеры и позицию окна за курсором
  if cur and cur.key == key then
    local frame = player.gui.screen[PLATFORM_CAM_FRAME]
    local platform = find_space_platform(hit.slot.force, hit.slot.index)
    if frame and frame.valid and frame.cam_preview and frame.cam_preview.valid and platform then
      local ok_h, hub = pcall(function() return platform.hub end)
      if ok_h and hub and hub.valid then
        pcall(function() frame.cam_preview.position = hub.position end)
      end
      if game.tick % 3 == 0 then
        place_camera_frame_at_cursor(player, frame, hit)
      end
    end
    return
  end

  -- сменилась или курсор ушёл — закрыть старое окно
  if cur then close_platform_camera(player) end
  if not hit then return end

  -- открыть новое окно камеры
  local platform = find_space_platform(hit.slot.force, hit.slot.index)
  if not platform then return end
  local surf = nil
  pcall(function() surf = platform.surface end)
  if not (surf and surf.valid) then return end
  local pos = {x = 0, y = 0}
  local ok_h, hub = pcall(function() return platform.hub end)
  if ok_h and hub and hub.valid then pos = hub.position end

  local frame = nil
  pcall(function()
    frame = player.gui.screen.add{
      type = "frame",
      name = PLATFORM_CAM_FRAME,
      direction = "vertical",
      caption = {"", hit.slot.name or "platform", "  ·  ", starmap_body_localised_name(hit.body.prototype_name)}
    }
    frame.style.minimal_width = PLATFORM_CAMERA_W + 20
    local cam = frame.add{
      type = "camera",
      name = "cam_preview",
      position = pos,
      surface_index = surf.index,
      zoom = PLATFORM_CAMERA_ZOOM
    }
    cam.style.width = PLATFORM_CAMERA_W
    cam.style.height = PLATFORM_CAMERA_H
  end)
  if frame and frame.valid then
    place_camera_frame_at_cursor(player, frame, hit)
    storage.platform_camera[player.index] = {key = key, force = hit.slot.force, index = hit.slot.index}
  end
end

function toggle_info_cards(player)
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid then return end
  storage.info_visible = not storage.info_visible

  if storage.info_visible then
    for _, planet in ipairs(storage.planets or {}) do
      if planet.discovered then
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
    if player then player.print("[custom-se-starmap] Карточки (условия+ресурсы): ВКЛ") end
  else
    for _, planet in ipairs(storage.planets or {}) do
      r_destroy(planet.card_render_id)
      planet.card_render_id = nil
      planet.last_side = nil
    end
    if player then player.print("[custom-se-starmap] Карточки: ВЫКЛ") end
  end
end

function handle_planet_click(player, cursor_pos)
  if not player or not player.valid or not storage.planets then return end
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid then return end
  if player.surface.name ~= SURFACE_NAME then
    if not (player.physical_surface and player.physical_surface.name == SURFACE_NAME) then return end
  end

  -- 0) МАРКЕР ПЛАТФОРМЫ: ПКМ по нему → Remote View на поверхность платформы.
  --    Не перебиваем клик, если выделен маркер планеты (приоритет планеты).
  do
    local sel0 = player.selected
    local sel_is_planet = sel0 and sel0.valid and sel0.name
      and string.find(sel0.name, "custom-se-marker-", 1, true) ~= nil
    local sel_is_platform = sel0 and sel0.valid and sel0.name == "custom-se-platform-marker"
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
  end

  -- 1) по выделенной сущности (маркер сравниваем по имени — unit_number у них нет)
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

  -- 2) по позиции курсора — захват чуть шире видимой иконки (хитбокс compact)
  if not target_planet and cursor_pos then
    local cx = cursor_pos.x or cursor_pos[1]
    local cy = cursor_pos.y or cursor_pos[2]
    local best_score = nil
    for _, planet in ipairs(storage.planets) do
      if planet.discovered and planet.position then
        local dx = planet.position.x - cx
        local dy = planet.position.y - cy
        local d = math.sqrt(dx * dx + dy * dy)
        local capture = (planet.icon_radius or 1) + 0.5
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

  -- 3) по позиции игрока — тот же захват по размеру иконки
  if not target_planet then
    local px = player.position.x
    local py = player.position.y
    local best_score = nil
    for _, planet in ipairs(storage.planets) do
      if planet.discovered and planet.position then
        local dx = planet.position.x - px
        local dy = planet.position.y - py
        local d = math.sqrt(dx * dx + dy * dy)
        local capture = (planet.icon_radius or 1) + 0.6
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
    player.print("[custom-se-starmap] " .. planet_name .. " — без поверхности")
    local nauvis = game.surfaces["nauvis"]
    target_surface = nauvis
    found = (nauvis ~= nil)
  end

  if found and target_surface then
    pcall(function() player.game_view_settings.show_quickbar = true end)
    pcall(function()
      player.set_controller{type = defines.controllers.remote, surface = target_surface, position = {0, 0}}
    end)
    player.print("[custom-se-starmap] Remote View → " .. planet_name)
  else
    player.print("[custom-se-starmap] Нет поверхности для " .. planet_name)
  end
end
