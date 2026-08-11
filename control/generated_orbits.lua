-- Опциональный файл с орбитами (если хотите задать вручную / из внешнего генератора).
-- Основной источник орбит - прототип mod-data "custom-se-starmap-orbits",
-- который заполняется в data-final-fixes.lua из прототипов (PlanetsLib).
-- Формат: [planet_name] = {parent="nauvis", parent_type="planet", distance=1.6, orientation=0.75}
return {
  -- Пример:
  -- ["muluna"] = {parent="nauvis", parent_type="planet", distance=1.6, orientation=0.75},
}
