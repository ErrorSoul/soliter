# CLAUDE.md

## Git Workflow

- Все изменения делаем в отдельной ветке (никогда не коммитим напрямую в master)
- Мерж в master — только после явного апрува пользователя
- Перед мержем — показать что изменилось
- **Мерж в master** разрешён только после: апрув трёх советников (advisor + grok-build + composer) **И** явный апрув пользователя.

## Compact — что сохранять при сжатии контекста

При компакте сохранять в порядке приоритета:
- **Архитектурные решения** — НИКОГДА не суммаризировать (сохранять дословно).
- **Изменённые файлы и их ключевые изменения.**
- **Текущий статус верификации** (pass/fail).
- **Открытые TODO и заметки по откату (rollback).**
- **Вывод инструментов** — можно удалять, но оставить pass/fail.

## Project

- Движок: Defold
- Платформа: HTML5 (Яндекс Игры)
- Язык: Lua
- Разрешение: 960x540 (landscape)
- [INDEX.md](./INDEX.md) — навигационная карта: символ→файл, message-passing edges, солвер+тесты. Смотреть ПЕРВЫМ, чтобы прыгать в нужный файл без чтения всего проекта. **Держать актуальной:** при перемещении/переименовании символов обновлять INDEX.md тем же коммитом — иначе он врёт и экономия токенов теряется.
- [architecture.md](./architecture.md) — архитектура, структура коллекций, message-passing, z-index система
- [docs/responsive-explained.md](./docs/responsive-explained.md) — как работает респонсив в Defold (проекция, GUI, input)
- [docs/sounds.md](./docs/sounds.md) — звуковая система: sfx.lua, sound_manager, cross-collection workaround

## Build

- Headless HTML5-сборка (Defold / js-web) → скилл `build`.

## Grok — два советчика для ревью

- Независимое ревью двумя моделями (grok-build + composer, `--effort max`) → скилл `grok-review`.

## Plan

- [PLAN.md](./PLAN.md) — план доработки до публикации на Яндекс Играх
- [plans/launch-global.md](./plans/launch-global.md) — **глобальный план запуска**: решаемость, ревью, ассеты, SDK, чистка, публикация + карта параллелизма
- [plans/](./plans/) — детальные планы по задачам:
  - [start-screen.md](./plans/start-screen.md) — стартовый экран (Фаза 2) ✅
  - [victory-screen.md](./plans/victory-screen.md) — victory screen (Фаза 2) ✅
  - [button-design.md](./plans/button-design.md) — дизайн кнопок (Фаза 2) ✅
  - [tutorial.md](./plans/tutorial.md) — туториал-слайдшоу (Фаза 3) ✅ (заменён на v2)
  - [tutorial-v2.md](./plans/tutorial-v2.md) — интерактивный туториал с мини-уровнем (Фаза 3)
  - [auto-finish.md](./plans/auto-finish.md) — авто-доигрывание карт в foundation
  - [effects.md](./plans/effects.md) — эффекты и анимации (Фаза 4)
  - [refactoring.md](./plans/refactoring.md) — рефакторинг cursor.script, config, cleanup
  - [refactor-sonnet.md](./plans/refactor-sonnet.md) — бриф-исполнитель рефактора для агента: индекс проекта + токен-протокол + новые находки (ui_fx, дубль set_cursor)
  - [responsive.md](./plans/responsive.md) — респонсив HTML5 (Фаза 5)
  - [sounds.md](./plans/sounds.md) — звуковые эффекты
