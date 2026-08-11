-- settings.lua
-- ВНИМАНИЕ: сейчас это АРХИВ. Рабочие значения живут в control/constants.lua —
-- константы в приоритете, потому что startup-настройки фиксируются в сохранении
-- и не меняются после правки дефолтов. Файл оставлен, чтобы старые сейвы грузились
-- без ошибок миграции настроек.
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
    default_value = 0,
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
    default_value = 0.6,
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
  -- Множители лун: размер и орбиты
  {
    type = "double-setting",
    name = "custom-se-starmap-moon-size-scale",
    setting_type = "startup",
    default_value = 0.5,
    minimum_value = 0.05,
    maximum_value = 5,
    order = "b4",
    localised_name = "Множитель размера лун",
    localised_description = "Итоговый размер луны = базовый размер × этот множитель. Меньше 1 — луны меньше планет."
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-moon-orbit-scale",
    setting_type = "startup",
    default_value = 0.25,
    minimum_value = 0.05,
    maximum_value = 5,
    order = "b5",
    localised_name = "Множитель радиуса орбит лун",
    localised_description = "Радиус орбиты луны = (distance + bonus) × sat-scale × этот множитель. Меньше 1 — орбиты ближе к родителю."
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
    localised_name = "Мин. расстояние между орбитами звездных планет (устаревшая, см. ниже)",
    localised_description = "Кроме лун. Оставлена для совместимости — используйте star-orbit-gap."
  },
  {
    type = "double-setting",
    name = "custom-se-starmap-star-orbit-gap",
    setting_type = "startup",
    default_value = 8,
    minimum_value = 0,
    maximum_value = 100,
    order = "c2",
    localised_name = "Разрыв между орбитами планет вокруг звезды",
    localised_description = "Минимальное расстояние между соседними орбитами вокруг солнца (не лун). Больше = орбиты дальше друг от друга."
  },
  -- Скорости вращения отдельно
  {
    type = "double-setting",
    name = "custom-se-starmap-star-orbit-speed",
    setting_type = "startup",
    default_value = 0.0003,
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
    default_value = 0.0009,
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
