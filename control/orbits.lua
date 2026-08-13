-- control/orbits.lua
-- Орбитальное движение: планеты вокруг звезды, луны вокруг родителя.
-- Все рендер-объекты адресуются по id (storage-safe).

function update_orbits()
  local surface = game.surfaces[SURFACE_NAME]
  if not surface or not surface.valid or not storage.planets then return end

  for _, planet in ipairs(storage.planets) do
    local speed
    if planet.parent_name then
      speed = MOON_ORBITAL_SPEED
    else
      -- Псевдо-Кеплер: линейная скорость ~ r^(-ORBIT_SPEED_KEPLER),
      -- нормированная на ORBIT_SPEED_REF_RADIUS.
      local r = planet.orbit_radius or 1
      if r < 1 then r = 1 end
      speed = ORBITAL_SPEED * (ORBIT_SPEED_REF_RADIUS / r) ^ ORBIT_SPEED_KEPLER
    end
    -- ORBITS_ENABLED=false: позиции не пересчитываются.
    if ORBITS_ENABLED ~= false then
      planet.angle = planet.angle + speed
      if planet.angle > math.pi * 2 then planet.angle = planet.angle - math.pi * 2 end
    end

    local x, y
    if planet.parent_name then
      local parent = storage.planet_by_name and storage.planet_by_name[planet.parent_name]
      if parent and parent.position then
        -- орбита луны центрируется на родителе
        if planet.orbit_id then
          r_set_target(planet.orbit_id, {x = parent.position.x, y = parent.position.y})
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
    planet.position = {x = x, y = y}

    -- Рендер есть только у открытых тел.
    if planet.discovered then
      r_set_target(planet.sprite_id, {x = x, y = y})
      -- обводка исследованного тела следует за иконкой
      r_set_target(planet.ring_id, {x = x, y = y})
      -- подпись под иконкой
      r_set_target(planet.name_text_id, {x = x, y = y + (planet.icon_radius or 1) + planet_name_gap(planet.icon_radius)})

      local sprite = r_obj(planet.sprite_id)
      if sprite then
        if planet.parent_name then
          -- луна: собственное вращение спрайта независимо от орбитального угла
          planet.self_angle = (planet.self_angle or planet.angle) + MOON_SELF_SPIN_SPEED
          if planet.self_angle > math.pi * 2 then planet.self_angle = planet.self_angle - math.pi * 2 end
          pcall(function() sprite.orientation = (planet.self_angle / (2 * math.pi)) % 1 end)
        else
          -- планета: orientation синхронно орбитальному углу
          pcall(function() sprite.orientation = (planet.angle / (2 * math.pi)) % 1 end)
        end
      end

      -- Карточка характеристик: пересоздаётся при смене стороны от центра
      -- (выравнивание текста left/right зависит от стороны).
      if planet.card_render_id and r_valid(planet.card_render_id) then
        local offset_x = (x >= 0) and 5 or -5
        local current_side = (x >= 0) and "right" or "left"
        if planet.last_side and planet.last_side ~= current_side then
          r_destroy(planet.card_render_id)
          local align = (current_side == "right") and "left" or "right"
          local card_text = build_card_text(planet.prototype_name)
          local ok, new_obj = pcall(function()
            return rendering.draw_text{
              text = card_text,
              surface = surface,
              target = {x = x + offset_x, y = y},
              color = {r = 0.92, g = 0.92, b = 0.92, a = 1},
              scale = 0.6,
              alignment = align
            }
          end)
          if ok and new_obj then
            planet.card_render_id = new_obj.id
            r_bring_front(new_obj.id)
          else
            planet.card_render_id = nil
          end
        else
          r_set_target(planet.card_render_id, {x = x + offset_x, y = y})
        end
        planet.last_side = current_side
      end

      -- Маркеры платформ и их подписи следуют за планетой (углы — из слотов)
      if planet.platform_render_ids then
        local dist = platform_slot_dist(planet)
        for idx, pid in ipairs(planet.platform_render_ids) do
          local slot = planet.platform_slots and planet.platform_slots[idx]
          local ang = (slot and slot.angle) or 0
          local ux, uy = math.cos(ang), math.sin(ang)
          if planet.platform_sprite_mode then
            r_set_target(pid, {x = x + ux * dist, y = y + uy * dist})
            r_bring_front(pid)
          else
            -- polygon-fallback: пересчёт вершин
            local po = r_obj(pid)
            if po then
              local verts = platform_triangle_verts({x = x, y = y}, ang, dist, PLATFORM_SIZE, PLATFORM_HALF_WIDTH)
              pcall(function() po.vertices = verts end)
            end
          end
          local lid = planet.platform_label_ids and planet.platform_label_ids[idx]
          if lid then
            r_set_target(lid, {x = x + ux * (dist + PLATFORM_LABEL_GAP), y = y + uy * (dist + PLATFORM_LABEL_GAP)})
            r_bring_front(lid)
          end
        end
      end

      -- z-order: орбита позади, иконка и подписи спереди
      r_move_back(planet.orbit_id)
      r_bring_front(planet.sprite_id)
      r_bring_front(planet.name_text_id)
      if planet.card_render_id then r_bring_front(planet.card_render_id) end
    end
  end

  -- Маркеры-сущности синхронизируются каждый тик (хитбоксы следуют за иконками).
  move_markers(surface)
end

-- Перемещение маркеров-сущностей вслед за иконками планет
-- (поиск по имени прототипа, из кандидатов — ближайший к целевой позиции).
function move_markers(surface)
  if not storage.planets then return end
  for _, planet in ipairs(storage.planets) do
    if planet.discovered and planet.marker_name and planet.position then
      local ok, found = pcall(function()
        return surface.find_entities_filtered{
          name = planet.marker_name,
          position = planet.position,
          radius = (planet.icon_radius or 1) + 2.5
        }
      end)
      if ok and found and found[1] and found[1].valid then
        local dx = found[1].position.x - planet.position.x
        local dy = found[1].position.y - planet.position.y
        if (dx * dx + dy * dy) > 0.04 then
          pcall(function() found[1].teleport({x = planet.position.x, y = planet.position.y}) end)
        end
      end

      -- Маркеры платформ (кликабельные сущности у слотов)
      if planet.platform_slots then
        local dist = platform_slot_dist(planet)
        for _, slot in ipairs(planet.platform_slots) do
          local tx = planet.position.x + math.cos(slot.angle) * dist
          local ty = planet.position.y + math.sin(slot.angle) * dist
          local ok2, found2 = pcall(function()
            return surface.find_entities_filtered{
              name = "space-map-rework-platform-marker",
              position = {x = tx, y = ty},
              radius = PLATFORM_MARKER_HALF + 1.2
            }
          end)
          if ok2 and found2 then
            -- ближайший маркер к слоту
            local best_e, best_d2 = nil, nil
            for _, e in ipairs(found2) do
              if e.valid then
                local dx = e.position.x - tx
                local dy = e.position.y - ty
                local d2 = dx * dx + dy * dy
                if not best_d2 or d2 < best_d2 then
                  best_e, best_d2 = e, d2
                end
              end
            end
            if best_e and best_d2 > 0.04 then
              pcall(function() best_e.teleport({x = tx, y = ty}) end)
            end
          end
          -- маркер один на тело (все слоты делят позицию) — хватит первого
          break
        end
      end
    end
  end
end
