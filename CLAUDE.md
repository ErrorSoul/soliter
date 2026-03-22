# CLAUDE.md

## Git Workflow

- Все изменения делаем в отдельной ветке (никогда не коммитим напрямую в master)
- Мерж в master — только после явного апрува пользователя
- Перед мержем — показать что изменилось

## Project

- Движок: Defold
- Платформа: HTML5 (Яндекс Игры)
- Язык: Lua
- Разрешение: 960x540 (landscape)

## Build

- Сборка HTML5 через Defold Editor или bob.jar
- `java -jar bob.jar --platform js-web --archive build`

## Plan

- [PLAN.md](./PLAN.md) — план доработки до публикации на Яндекс Играх
- [plans/](./plans/) — детальные планы по задачам:
  - [start-screen.md](./plans/start-screen.md) — стартовый экран (Фаза 2) ✅
  - [victory-screen.md](./plans/victory-screen.md) — victory screen (Фаза 2) ✅
  - [button-design.md](./plans/button-design.md) — дизайн кнопок (Фаза 2)
  - [tutorial.md](./plans/tutorial.md) — интерактивный туториал (Фаза 3)
