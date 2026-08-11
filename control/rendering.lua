-- control/rendering.lua
-- Хелперы Factorio 2.1. В storage нельзя хранить LuaRenderObject/LuaEntity,
-- поэтому храним числовые id и резолвим объект по требованию.

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

-- === Геометрия слотов платформ (ЕДИНАЯ формула для всех модулей!) ===
-- Зазор от края иконки до маркера зависит от размера планеты.
function platform_gap_for(icon_radius)
  return math.max(PLATFORM_GAP, (icon_radius or 1) * PLATFORM_GAP_SCALE)
end

-- Дистанция от центра планеты до центра маркера платформы
function platform_slot_dist(body)
  return (body.icon_radius or 1) + platform_gap_for(body.icon_radius)
end
