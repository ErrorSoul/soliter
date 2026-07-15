# Рефакторинг — бриф-исполнитель для агента (Sonnet)

Этот файл — **единая точка входа** для агента, который выполняет рефактор. Цель документа:
дать карту проекта и протокол, чтобы агент **не читал лишнее** (экономия токенов) и правил
точечно. Детали трёх крупных задач (config/coords/hit_test) уже расписаны в
[refactoring.md](./refactoring.md) — здесь на них ссылки, не дублируем.

## Правила (НЕ нарушать)
- **Логика не меняется.** Только перемещение кода + `require` + удаление мёртвого/дубля.
- **Defold-специфика:** `.script` — НЕ модули, их нельзя `require` друг в друга. Общий код
  выносим ТОЛЬКО в обычный `.lua`-модуль (как `sfx.lua`, `i18n.lua`) и подключаем `require`.
  Message-passing boilerplate (`on_message`-ветки) — пер-скриптовый, сливать объединением
  скриптов НЕЛЬЗЯ; выносим максимум внутреннее вычисление в хелпер.
- **Относительные URL (`"."`, `"#sprite"`) в функции модуля резолвятся к ВЫЗЫВАЮЩЕМУ
  скрипт-инстансу** — поэтому хелпер вида `ui_fx.highlight(scale)` с `go.animate(".", …)`
  безопасен (действует на GO звонящего). Это ключ к выносу highlight-блоков.
- Работа в отдельной ветке. **Один пункт очереди = один коммит.** БЕЗ трейлера Co-Authored-By.
- Мерж в master — только после явного апрува пользователя (см. CLAUDE.md).

## Протокол токен-экономии
1. Этот файл + `refactoring.md` — читать ПОЛНОСТЬЮ один раз. Дальше — по индексу §1.
2. На каждый пункт: открывать ТОЛЬКО указанные `file:Lстарт-Lконец`, не весь файл
   (`Read` с `offset`/`limit`).
3. После каждого пункта — верификация §4. Зелено → коммит → следующий. Красно → откат пункта.
4. Не «улучшать» соседний код (Karpathy: хирургические правки). Мёртвый код трогаем только
   там, где он явно перечислен ниже.

---

## §1. ИНДЕКС ПРОЕКТА (карта — чтобы не сканировать)

Формат: `файл (LOC) — ответственность — ключевые функции / on_message-ветки`.

**Игровые скрипты (main/Scripts):**
- `cursor.script` (883) — God Object: ввод + drag-drop оркестрация — on_input, on_message,
  check_tableau_slots/last_cards/free_slots/flower_slot/base_slots/dragon_buttons/free_tableau_slots,
  screen_to_world(+2 мёртвых screena_to_world), fly_card_arc, move_stack_cards, clean_cursor.
- `main.script` (716) — состояние игры, колода, раздачи, auto-finish, интеграция солвера —
  deal_cards, create_deck, shuffle_deck, build_solver_snapshot, debug_solve, can_auto_finish,
  auto_finish_step; ветки: card_to_base, check_auto_finish, dragons_collected, debug_solve.
- `card.script` (168) — сущность карты: drag-анимация, валидация дропа — set_card,
  is_correct_card; ветки: start_drag, drag_update, drop_success, drop_failed, can_move_card,
  highlight, unhighlight.
- `tableau_script.script` (173) — стопка tableau: видимость, auto-fly — update_visible_cards,
  can_stack_cards, last_card_to_slot, color_to_cell; ветки: update_stack, remove_card,
  occupy_slot, check_slot.
- `free_cell.script` (120) — free cell: валидация, трекинг драконов, синк счётчика кнопки —
  check_dragon, send_to_dragon_buttons, change_button_counter, wo_array; ветки: check_slot,
  occupy_slot, clear_slot, remove_card, can_pick_card, set_cursor (ДУБЛЬ), highlight, unhighlight.
- `dragon_button.script` (86) — кнопка сбора драконов — check_state, free_slot_any; ветки:
  set_button, send_counter_to_button, get_dragon_cards, change_free_slots_button_counter,
  highlight, unhighlight.
- `base_slot.script` (88) — foundation-слот — check_correct_cards; ветки: check_slot,
  occupy_slot, set_cursor, highlight (+ проброс в last_card), unhighlight.
- `flower_slot.script` (22) — слот цветка — ветки: check_slot, occupy_slot.
- `game_manager.script` (40) — загрузчик уровней/прокси — ветки: start_game, restart_level,
  switch_level, unload_level, proxy_loaded/unloaded.
- `sfx.lua` (25) — обёртка звуков (cross-collection queue).
- `i18n.lua` (79) — локализация en/ru/tr. `tutorial_state.lua` (50) — шаги туториала.

**GUI:** `gui/ui.gui_script` (166) — старт/туториал/победа. `gui/game.gui_script` (134) — HUD.

**Solver (под тестами — НЕ трогаем в этом рефакторе, см. §5):** `rules.lua` (991),
`bridge.lua` (84), `board_view.lua` (132), `watch.lua` (101), `run.lua` (310).

---

## §2. ОЧЕРЕДЬ ЗАДАЧ (в порядке выполнения)

Крупные три — по уже готовым разделам refactoring.md (там точные строки и код модуля):

1. **config.lua** — refactoring.md «Задача 1». Константы (suit→слот мэппинги, размеры,
   z-index, offset). Покрывает дубль suit→button (cursor.script:35-38 ≈ tableau_script.script:23-30).
2. **coords.lua** — refactoring.md «Задача 2». Вынести рабочую `screen_to_world`; удалить
   ДВА мёртвых `screena_to_world` (cursor.script ~55-74 и ~110-127) + `FIXED_ZOOM`.
3. **hit_test.lua** — refactoring.md «Задача 3». Вынести `is_point_in_rect` + все `check_*`.

Затем — мелкие/cleanup (часть в refactoring.md, часть — НОВЫЕ находки §3):

4. **Мёртвый код / debug** — refactoring.md «Задача 4» и «Задача 5» (закомментированные блоки,
   `pprint`, DEBUG_DRAW, DEBUG_DEAL). ⚠️ НЕ удаляй `DEBUG_SOLVER`-блоки (in-game солвер ещё
   активен) — их стрип отдельной задачей перед релизом, см. launch-handoff §0b.
5. **Дубль-хендлер `set_cursor`** — §3.A (новое).
6. **ui_fx.lua — highlight/unhighlight** — §3.B (новое, ОПЦИОНАЛЬНО/осторожно).
7. **Контракты сообщений** — refactoring.md «Задача 6» (документация в architecture.md).

---

## §3. НОВЫЕ находки (нет в refactoring.md)

### §3.A — Дубль-ветка `set_cursor` в free_cell.script  ✅ безопасно, быстро
`free_cell.script:52-60` содержит ДВЕ идентичные `elseif hash("set_cursor")` ветки:
- 52-55 — рабочая.
- 57-60 — **мёртвая** (тот же hash, недостижима).

Правка: удалить строки **57-60** (вторую ветку целиком). Тело не меняется.
Верификация: §4.

### §3.B — ui_fx.lua: общий highlight/unhighlight  ⚠️ осторожно (boilerplate)
Идентичный паттерн (tint `vec4(1.5,1.4,1.0,1)` + `go.animate` scale pingpong INSINE 0.5,
unhighlight → tint `vec4(1,1,1,1)` + scale→1) повторяется в **трёх слот-скриптах**:
- `free_cell.script:107-116` (scale **1.06**)
- `dragon_button.script:48-56` (scale **1.15**)
- `base_slot.script:44-58` (scale **1.06**, НО ещё пробрасывает highlight в last_card —
  проброс ОСТАВИТЬ в скрипте, вынести только tint+scale часть)

План: создать `main/Scripts/ui_fx.lua`:
```lua
local M = {}
function M.highlight(scale)
   sprite.set_constant("#sprite", "tint", vmath.vector4(1.5, 1.4, 1.0, 1))
   go.cancel_animations(".", "scale")
   go.animate(".", "scale", go.PLAYBACK_LOOP_PINGPONG,
      vmath.vector3(scale, scale, 1), go.EASING_INSINE, 0.5)
end
function M.unhighlight()
   sprite.set_constant("#sprite", "tint", vmath.vector4(1, 1, 1, 1))
   go.cancel_animations(".", "scale")
   go.set(".", "scale", vmath.vector3(1, 1, 1))
end
return M
```
В каждом из трёх скриптов: `local ui_fx = require("main.Scripts.ui_fx")`, в ветках —
`ui_fx.highlight(1.06)` / `ui_fx.unhighlight()` (dragon_button — 1.15).
**Перед правкой подтвердить, что компонент спрайта = `#sprite`** (он такой во всех трёх — проверено).

**`card.script:155-167` НЕ включать** в общий хелпер: его unhighlight сбрасывает в
`self.normal_tint` (не литерал) — это особый случай, оставить как есть.

Это самый «рискованный» пункт (вносит indirection в message-handlers). Если на верификации
что-то не так — откатить, проект и без него корректен.

---

## §4. Верификация (после КАЖДОГО пункта)
```
bash tools/defold-build.sh          # EXIT 0 = Lua компилится во всех скриптах
/opt/homebrew/bin/lua solver/tests/run_all.lua   # 42/42 (solver+replay не трогаем — должны остаться зелёными)
```
Плюс — пользователь прогоняет в редакторе Defold (визуальная проверка highlight/drag), т.к.
рантайм-движок хедлессно не запустить. Goal-driven цикл: правка → build EXIT 0 → коммит.

## §5. Что НЕ трогать
- `solver/*` — под тестами, стабилен. Рефактор сюда не лезет.
- `DEBUG_SOLVER`-блоки в main.script/cursor.script — in-game солвер ещё в работе (launch-handoff §0b).
- Drag state machine (cursor.on_input + on_message) — НЕ переписывать (рискованно, ничего не блокирует).
- z-index систему, tutorial_state.lua — не переделывать.
- `card.script` highlight/unhighlight (особый tint) — не сливать в ui_fx.
