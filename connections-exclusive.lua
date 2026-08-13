-- connections-exclusive.lua [space-map-rework]
-- Эксклюзивные (ручные) space-connection.
--
-- Связи задаются только здесь. Автопланировка (control/routes.lua +
-- data-final-fixes.lua) их не изменяет и не дублирует, но учитывает:
--   * дубль пары тел автоматически не создаётся;
--   * ручная связь location<->location отключает авто-подключение этих
--     локаций к планетам.
--
-- Обработка:
--   * data-стадия (data-final-fixes.lua): прототип space-connection
--     "space-map-rework-xconn-<from>-<to>"; иконки — автоматически;
--     астероиды маршрута генерируются ванильным хелпером space-age.
--     Длина: поле length (км); без поля — расстояние на карте x 1000.
--   * runtime (control/routes.lua): отрисовка на карте + маркеры платформ.
--
-- Формат (порядок from/to не важен, связь двусторонняя):
--   { from = "<planet|space-location>", to = "<planet|space-location>", length = 12345 },
--   length — целое > 0, км; опционально.
-- После правки: перезапуск игры (data-стадия) + перезаход в сейв.
-- Проверка: /starmap-test-conn, /starmap-test-routes.

EXCLUSIVE_CONNECTIONS = {
  -- пример:
  -- { from = "aquilo", to = "solar-system-edge", length = 60000 },
  -- { from = "solar-system-edge", to = "shattered-planet" },
}

return EXCLUSIVE_CONNECTIONS
