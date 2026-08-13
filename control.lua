-- control.lua: загрузка модулей control/. Порядок require определяет порядок инициализации.

require("control.constants")
require("connections-exclusive")  -- ручные space-connection (глоб. EXCLUSIVE_CONNECTIONS)
require("control.rendering")
require("control.surface")
require("control.starsystem")
require("control.orbits")
require("control.routes")  -- маршруты между телами + летящие платформы
require("control.player")
require("control.gui")
require("control.events")

log("[space-map-rework] control.lua loaded (modular) - yellow sun, transparent orbits, research-gated planets, platform markers")
