-- control/player.lua
-- Скрытие только хотбара, телепорт, дебаг показаний

function update_player_view_settings(player)
  if not player or not player.valid then return end
  local is_on_starmap = false
  if player.controller_type == defines.controllers.character then
    if player.surface and player.surface.name == SURFACE_NAME then is_on_starmap = true end
  elseif player.controller_type == defines.controllers.remote or player.controller_type == defines.controllers.god then
    if player.physical_surface and player.physical_surface.name == SURFACE_NAME then
      is_on_starmap = false
    elseif player.surface and player.surface.name == SURFACE_NAME then
      is_on_starmap = true
    end
  end
  pcall(function()
    if is_on_starmap then
      player.game_view_settings.show_quickbar = false
    elseif player.game_view_settings.show_quickbar == false then
      player.game_view_settings.show_quickbar = true
    end
  end)
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
        pcall(function() player.set_controller{type = defines.controllers.character, character = player.character} end)
        if player.character then player.teleport(prev.position, game.surfaces[prev.surface]) end
      end
      player.print({"", "[custom-se-starmap] Возврат на ", prev.surface})
      update_player_view_settings(player)
      return
    else
      local nauvis = game.surfaces["nauvis"]
      if nauvis then
        player.teleport({0, 0}, nauvis)
        player.print("[custom-se-starmap] Возврат на Nauvis")
      end
      update_player_view_settings(player)
      return
    end
  end

  storage.player_prev[player.index] = {
    surface = player.surface.name,
    position = {x = player.position.x, y = player.position.y}
  }

  if player.controller_type == defines.controllers.remote then
    pcall(function() if player.exit_remote_view then player.exit_remote_view() end end)
    if player.character and player.character.valid then
      pcall(function() player.set_controller{type = defines.controllers.character, character = player.character} end)
      pcall(function() player.teleport({0, 0}, surface) end)
    else
      pcall(function() player.set_controller{type = defines.controllers.remote, surface = surface, position = {0, 0}} end)
    end
  else
    if player.controller_type == defines.controllers.god or player.controller_type == defines.controllers.editor then
      pcall(function() player.teleport({0, 0}, surface) end)
    else
      if player.character and player.character.valid then
        pcall(function() player.teleport({0, 0}, surface) end)
      else
        pcall(function() player.set_controller{type = defines.controllers.remote, surface = surface, position = {0, 0}} end)
      end
    end
  end

  pcall(function() player.game_view_settings.show_quickbar = false end)
  player.print("[custom-se-starmap] Калидус Sol — SHIFT+M возврат, SHIFT+I инфо, ПКМ → Remote View")

  -- ДЕБАГ: показания планет и расстояния + привязка
  if storage.planets then
    player.print("[DEBUG] Всего тел: " .. #storage.planets
      .. " | STAR_SCALE=" .. tostring(STAR_DISTANCE_SCALE)
      .. " SAT_SCALE=" .. tostring(SAT_DISTANCE_SCALE)
      .. " radius=distance*scale")
    for i, pl in ipairs(storage.planets) do
      local ptype = pl.parent_type or "star"
      if not pl.parent_name then ptype = "star" end
      player.print(string.format(
        "[%d] %s | dist=%.3f (raw_orbit=%.3f raw_proto=%.3f) radius=%.1f parent=%s<%s> mag=%.2f ang=%.2f",
        i, pl.name,
        pl.distance or 0, pl.raw_orbit_dist or -1, pl.raw_proto_dist or -1,
        pl.orbit_radius or 0, pl.parent_name or "star", ptype,
        pl.magnitude or 0, pl.angle or 0))
      if i >= 40 then
        player.print("... и ещё " .. (#storage.planets - 40) .. " тел")
        break
      end
    end
  end
end
