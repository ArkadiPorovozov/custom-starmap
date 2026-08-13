-- control/rendering.lua
-- Хелперы рендера. В storage нельзя хранить LuaRenderObject/LuaEntity —
-- хранятся числовые id, объект резолвится по требованию через rendering.get_object_by_id().

-- id или объект -> живой LuaRenderObject; nil, если объекта нет.
function r_obj(obj)
  if obj == nil then return nil end
  if type(obj) == "number" then
    local ok, o = pcall(function() return rendering.get_object_by_id(obj) end)
    if ok and o then
      local ok_v, v = pcall(function() return o.valid end)
      if ok_v and v then return o end
    end
    return nil
  end
  local ok, v = pcall(function() return obj.valid end)
  if ok and v then return obj end
  return nil
end

function r_valid(obj)
  return r_obj(obj) ~= nil
end

function r_destroy(obj)
  local o = r_obj(obj)
  if o then pcall(function() o.destroy() end) end
end

function r_set_target(obj, pos)
  local o = r_obj(obj)
  if o and pos then pcall(function() o.target = pos end) end
end

function r_bring_front(obj)
  local o = r_obj(obj)
  if o then pcall(function() o.bring_to_front() end) end
end

function r_move_back(obj)
  local o = r_obj(obj)
  if o then pcall(function() o.move_to_back() end) end
end

-- Отступ подписи планеты от края её иконки: max(база, icon_radius * коэф.).
function planet_name_gap(icon_radius)
  return math.max(PLANET_NAME_GAP or 0.25, (icon_radius or 1) * (PLANET_NAME_GAP_SCALE or 0.25))
end

-- === Геометрия слотов платформ (единая формула для всех модулей) ===
-- Зазор от края иконки планеты до маркера платформы: max(база, icon_radius * коэф.).
function platform_gap_for(icon_radius)
  return math.max(PLATFORM_GAP, (icon_radius or 1) * PLATFORM_GAP_SCALE)
end

-- Дистанция от центра планеты до ЦЕНТРА маркера платформы.
-- Учитывается половина размера маркера: иначе спрайт наполовину перекрывает иконку.
-- PLATFORM_SLOT_INWARD (constants.lua) сдвигает кольцо к планете: маркер
-- частично перекрывает край иконки.
function platform_slot_dist(body)
  return (body.icon_radius or 1)
    + platform_gap_for(body.icon_radius)
    + (PLATFORM_SIZE or 0.55) * 0.5
    - (PLATFORM_SLOT_INWARD or 0)
end
