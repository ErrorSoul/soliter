# Architecture

## Движок и платформа

- **Defold** (Lua), HTML5, разрешение 960x540 (landscape)
- Рендер: `render.script` с `use_fixed_fit_projection`
- Проекция: fixed_fit, near=-1, far=1

## Структура коллекций

```
main.collection
├── ui.gui              — GUI: стартовый экран, кнопки, victory, tutorial overlay
├── game_manager.script — загрузка/выгрузка уровней через collection proxy
└── #level_proxy → soliter.collection
    ├── card_table (GO)
    │   ├── main.script       — состояние игры, колода, раздача, победа
    │   ├── #card_factory     — фабрика карт
    │   └── #cursor_factory   — фабрика курсора
    ├── cursor (GO, создаётся через factory)
    │   └── cursor.script     — ввод, drag & drop, валидация ходов
    ├── tableau_slot1..8 (GO)
    │   └── tableau_script.script — стопки карт, видимые карты, стекинг
    ├── base_slot1..3 (GO)
    │   └── base_slot.script  — foundation (масти 2→10)
    ├── free_slot1..3 (GO)
    │   └── free_cell.script  — свободные ячейки, отслеживание драконов
    ├── flower_slot (GO)
    │   └── flower_slot.script — слот для цветка
    └── dragon_button1..3 (GO)
        └── dragon_button.script — кнопки сбора драконов
```

## Игровые объекты

### Карта (`card.go` + `card.script`)
- Спрайт 90x150, текстура из `main.atlas`
- Свойства: `value`, `suit`, `is_dragon`, `is_flower`, `owner` (slot_id)
- Sprite id: `"{value}_{suit}"` (напр. `"5_green"`, `"d_red"`, `"flower"`)
- Z-index: 0.2 (в стопках управляется tableau_script)
- Highlight: tint `vmath.vector4(1.2, 1.2, 0.8, 1)` (определён, но не используется активно)

### Курсор (`cursor.go` + `cursor.script`)
- Получает input focus, обрабатывает touch/mouse
- `screen_to_world()` — конвертация экранных координат → игровые
- Хранит: `free_slots`, `base_slots`, `flower_slot`, `tableau_slots`, `dragon_buttons`, `tableau_stacks`, `last_cards`
- Состояние drag: `is_dragging`, `dragging_stack`, `selected_card`, `drag_offset`, `original_position`, `stack_cards`
- Hit-test: `is_point_in_rect()` для всех типов слотов

### Слоты
| Тип | Кол-во | Правила | Скрипт |
|-----|--------|---------|--------|
| Tableau | 8 | Стек: разные масти, убывающие значения | `tableau_script.script` |
| Base (foundation) | 3 | Одна масть, возрастающие значения (с 2) | `base_slot.script` |
| Free cell | 3 | Одна любая карта, трекинг драконов | `free_cell.script` |
| Flower | 1 | Только карта-цветок | `flower_slot.script` |
| Dragon button | 3 | Активируется при 4 драконах + свободный слот | `dragon_button.script` |

## Колода

- 3 масти (red, blue, green) × 9 значений (2–10) = 27 карт
- 3 масти × 4 дракона = 12 карт
- 1 цветок
- **Итого: 40 карт**, раздаются в 8 стопок

## Message-passing архитектура

### Drag & Drop flow
```
[touch pressed] → cursor.on_input()
  → check_tableau_slots() / check_free_slots() — находит карту
  → msg.post(card, "start_drag")

[touch move] → cursor.on_input()
  → msg.post(card, "drag_update", {position})
  → card: go.set_position(position + z:0.3)

[touch released] → cursor.on_input()
  → check_last_cards() / check_*_slots() — находит целевой слот
  → msg.post(target, "check_slot" / "can_move_card")

[slot ответ] → cursor.on_message()
  ├── "slot_valid" / "valid_card"
  │   → msg.post(card, "drop_success", {slot_id, position})
  │   → card → msg.post(new_slot, "occupy_slot")
  │   → card → msg.post(old_slot, "remove_card")
  │   → clean_cursor()
  └── "slot_invalid" / "invalid_card"
      → msg.post(card, "drop_failed", {position})
      → card: go.animate(возврат, OUTQUAD, 0.3s)
      → clean_cursor()
```

### Авто-перемещение (цветок, двойка, драконы)
```
tableau_script.update_visible_cards()
  → last_card_to_slot()
    ├── flower → msg.post(cursor, "send_to_flower_slot")
    ├── value=2 → msg.post(cursor, "send_to_base_slot")
    └── dragon → msg.post(dragon_button, "send_counter_to_button")

cursor → msg.post(card, "drop_success", {animation=true})
  → slot.occupy_slot() → go.animate(позиция, LINEAR, 0.5s, delay 0.3s)
```

### Драконы
```
free_cell: при размещении дракона
  → msg.post(dragon_button, "send_counter_to_button")
  → dragon_button.counter++ → check_state()
    → если counter==4 && free_slots>0:
       sprite → "button_{color}", cursor.set_button_state(active=true)

cursor: click на активную кнопку
  → msg.post(button, "get_dragon_cards")
  → button → msg.post(cursor, "get_dragon_cards", cards)
  → cursor: для каждого дракона → msg.post(card, "drop_success", {animation=true, complete=true})
  → button → msg.post("/card_table#main", "dragons_collected")
```

### Победа

Условие победы — **`main.board_cleared`**: 27 номиналов в foundation **И** ни одной
живой карты в свободных ячейках **И** ни одного несобранного дракона **И** цветок
в своём слоте. До 2026-08-21 игра объявляла победу по одному счётчику
`base_cards_count >= 27` и расходилась со своим эталоном (замер: в 26% решаемых
раздач 27-я карта садится, когда на столе ещё 4 дракона).

⚠ **«То же, что у солвера» — по следствию, не по формуле** (неточность в этом
файле поймана ревью блока L). `rules.is_goal` = «tableau пуст И живых карт в
ячейках нет»; foundation и цветок он не считает вообще — так он годится и для
мини-раздач туториала. `rules.is_win` = «все три foundation на 10 И цветок в
слоте». На полной раздаче все три предиката сходятся, но писать
`board_cleared == is_goal` нельзя.

Про цветок (внешнее ревью 2026-08-23, блок L). Без него `board_cleared` давал
«чисто», пока цветок ещё лежал в колонке: он не считался ни живой ячейкой, ни
драконом. 27-я карта приходит через `card_to_base` в том же кадре, а цветок
улетает только со следующего `tableau.update` — Victory показывался НА КАДР
РАНЬШЕ правила. Теперь эта ветка уходит в `begin_auto_collect`, и победу
объявляет путь, который уже умеет дожидаться посадки цветка.

**Всего мест, где ставится WIN, шесть — и это не одно условие на всех.** Полный
список, чтобы «унифицировать» нельзя было молча:

| # | где | условие |
|---|---|---|
| 1 | `card_to_base` → `declare_victory` | `board_cleared` |
| 2 | `dragons_collected` → `declare_victory` | `board_cleared` |
| 3 | `auto_collect_give_up` → `declare_victory` | 27 номиналов + пустые ячейки (**намеренно слабее**, см. ниже) |
| 4 | `auto_finish_step`, терминальная ветка | пустой tableau + нет живой ячейки + `base_cards_count > 0` |
| 5 | `dragons_collected`, ветка туториала | `tutorial_mode` |
| 6 | `flower_collected` → `declare_victory` | `board_cleared` (добавлено 2026-08-24, блок M2) |

Четвёртая согласована с `board_cleared` не по форме, а по следствию: пустой
tableau не может прятать цветок, а живую ячейку она проверяет сама. Пятая — про
мини-раздачу туториала, где обычного условия победы нет.

**Шестая — предикат тот же, что у первой, отличается только триггер, и в этом
весь смысл.** Цветок — четвёртое слагаемое `board_cleared`, значит его посадка
может ЗАКОНЧИТЬ партию. Раньше обработчик только взводил флаг, и это оставляло
дыру ровно там, где `auto_collecting` НЕ поднимали: игрок дожал последнюю масть
кнопкой сам (`dragons_collected` приходит через 1.5 с, а цветок под собранным
драконом летит дольше), либо цветок был припаркован в свободную ячейку и
переложен в слот последним ходом. В обоих случаях стол пуст, а спросить
`board_cleared` уже некому: путь уступки с её ожиданием не запущен. Точка 6 — это
единственная точка победы, достижимая при `auto_collecting == false` и без
`card_to_base`.

**Все шесть зовут `tutorial_state.request_victory()`** → `show_victory` → поллинг
в `ui.gui_script` → `gameplay_over` в `game_manager`. Поэтому платформенный
`GameplayAPI.stop` уходит с ЛЮБОЙ победы, и одной сквозной проверки в сценарии
`win` достаточно — она не «повезло поймать», а единственная воронка.

**Третья точка — уступка `auto_collect_give_up`, и условие там ДРУГОЕ:**
27 номиналов **и** пустые (незапечатанные) ячейки, но без требования чистого
стола. Это запасной выход G2a: если авто-сбор невозможен и ходов у игрока нет,
партия засчитывается — иначе вместо победы получается софт-лок. Требование по
ячейкам добавлено в блоке L: карта в незапечатанной ячейке — это живой ход, и
победу объявлять рано.

```
base_slot.occupy_slot()
  → msg.post("/card_table#main", "card_to_base")
  → main: base_cards_count++
      ├─ board_cleared → declare_victory()
      └─ иначе (номиналы кончились, драконы остались)
           → msg.post(cursor, "auto_collect_dragons")   [если не debug_replaying]
               → cursor жмёт горящие кнопки ТЕМ ЖЕ путём, что палец
               → dragon_button: timer 1.5s → "dragons_collected" → main
                   → board_cleared → declare_victory()

dragons_collected — ЕДИНСТВЕННАЯ точка победы после сбора, и туда же приходит
РУЧНОЙ сбор. Поэтому тупика нет: не сработает авто-нажатие — игрок дожмёт кнопки
сам и всё равно выиграет.

Запасной выход (G2a): кнопка масти горит только при 4 ОТКРЫТЫХ драконах, а дракон
под драконом с раздачи верхушкой не был — счётчик не дошёл до 4. Замер: в 4 из 15
таких партий не горит НИ ОДНА кнопка. Курсор, не нажав ничего, шлёт
`auto_collect_none`, и main засчитывает победу — иначе игрок остался бы без победы
вовсе. Сдвигать дракона, чтобы открыть следующего, авто-сбор пока не умеет.

UI (ui.gui_script.update)
  → поллит tutorial_state.show_victory каждый кадр
  → показывает victory_overlay
```

## Существующие анимации

| Что | Easing | Длительность | Delay | Где |
|-----|--------|-------------|-------|-----|
| Раздача карт | LINEAR | 0.5s (0.3s tutorial) | 0.1×(stack+card) | `main.script` |
| Drop failed (возврат) | OUTQUAD | 0.3s | — | `card.script` |
| Авто-перемещение (base/free/flower) | LINEAR | 0.5s | 0.3s | `base_slot`, `free_cell`, `flower_slot` |
| Драг: поворот карты (`euler.z`) | OUTQUAD | lag×1.6 | — | `card.script` + `ui_fx` |
| Драг: сжатие по X | OUTQUAD | 0.04s | — | `card.script` |
| Драг: доводка позиции | OUTQUAD | 0.05–0.16s, растёт вглубь стопки | — | `card.script` |

### Семантика `go.animate` / `go.cancel_animations` — ЗАМЕРЕНО, не из документации

Проверено зондом в реальной js-web сборке (три сценария, 2026-08-21). Важно, потому
что драг анимирует одновременно составное `scale` и под-свойство `scale.x`:

1. `go.cancel_animations(".", "scale")` **отменяет и живую анимацию `scale.x`**
   (линейная 1.0→0.4 за 1с, отменена на 0.2с — застыла на 0.88).
2. Одновременные анимации `scale` и `scale.x` — **побеждает составное**: `scale`
   переписывает x каждый кадр.
3. Путь `drop_failed` (cancel + анимация `scale` в единицу) честно возвращает 1.0.

Практический вывод: сбрасывать эффекты драга можно одним `cancel_animations("scale")`,
но **поворот `euler.z` он не трогает** — его надо гасить отдельно. Этим занимается
идемпотентная `card.reset_card_fx(settle)`; звать её обязан КАЖДЫЙ путь окончания
драга, иначе карта остаётся повёрнутой навсегда (сообщение `drop_*` может и не
прийти — см. F10).

### Скорость драга нормируется по времени кадра

`ui_fx.drag_speed(dx, dt)` считает px/сек, а не px/событие. До 2026-08-21 наклон
считался от сдвига МЕЖДУ СОБЫТИЯМИ ВВОДА: на 144 Гц событий вдвое больше, каждое
`dx` вдвое меньше — один и тот же жест давал разный эффект на разных машинах, а в
HTML5 частота кадров ещё и плавает. По той же причине расчёт драга живёт в
`cursor.update(dt)`, а не в `on_input`: в `on_input` времени кадра просто нет.
`ui_fx.smooth_speed` сглаживает скорость экспоненциально — в кадре без события мыши
сырая скорость равна нулю, и без сглаживания карта дёргано выпрямлялась между
движениями руки (замерено зондом: цель скакала 0 / 6.7 / 0).

## Z-index система

- Карты по умолчанию: z=0.2
- Карта при drag: z += 0.3 (в `drag_update`)
- Карты в tableau стопке: z = 0.002 + i×0.002, последняя = 0.03
- Карты в base: z = slot.z + 0.002 + count×0.002
- Слоты (фон): z ≈ -0.2

## Координаты и позиции

- Размер карты: 90×150 px
- Смещение карт в стопке: -35 по Y
- Кнопки драконов: (420, 511), (420, 463), (420, 416), размер 48×48
- Координаты из `screen_to_world()`: action.x/y → нормализация → игровые координаты

## Состояния игры (`main.script`)

- `INIT` → `PLAYING` → `WIN` / `GAME_OVER`
- `tutorial_state` (Lua module) — shared state между collection proxy и UI:
  - `is_tutorial`, `step`, `ui_dirty`, `show_victory`
  - `EXPECTED_MOVES[0..3]` — валидация ходов в туториале
  - Polling: UI проверяет флаги каждый кадр в `update()`

## UI (`gui/ui.gui_script`)

- Стартовый экран → "PLAY" → загрузка уровня через game_manager
- Кнопки: Restart, Tutorial (скрыты до начала игры)
- Victory overlay: "Victory!" / "Well done!" + "Play Again" / "Play Now" + "Menu"
- Tutorial overlay: подсказки по шагам + SKIP
- i18n через `main/Scripts/i18n.lua`

## Важные нюансы

- **Cross-collection messaging**: UI (gui) и game logic (proxied collection) не могут общаться через `msg.post`. Решение: shared Lua module `tutorial_state` + polling в `update()`.
- **Dragon complete flag**: `message.complete=true` при сборе драконов предотвращает повторное обновление free_slot, используется `is_blocked` в `free_cell.script`.
- **Автоматические ходы**: цветок и двойки авто-уходят в foundation/flower при появлении на вершине стопки (в `last_card_to_slot`). В туториале двойки НЕ авто-уходят (`tutorial_state.is_tutorial` check).
- **Stack drag**: при перетаскивании стопки карт сохраняются `relative_pos` каждой карты относительно верхней, и все карты двигаются синхронно.

## Message contracts

| Message | Sender → Receiver | Параметры | Описание |
|---------|-------------------|-----------|----------|
| `set_card` | main → card | `{data: {value, suit, is_dragon, is_flower}, slot_id}` | Инициализация карты |
| `start_drag` | cursor → card | — | Начало перетаскивания |
| `drag_update` | cursor → card | `{position: vec3, tilt?: number}` | Обновление позиции при drag |
| `drop_success` | cursor → card | `{slot_id, position: vec3, card, animation?: bool, complete?: bool}` | Успешный ход |
| `drop_failed` | cursor → card | `{position: vec3}` | Возврат карты на место |
| `check_slot` | cursor → slot | `{card?}` или `{cards?, source_card?}` | Запрос валидации хода |
| `slot_valid` | slot → cursor | — | Ход валиден |
| `slot_invalid` | slot → cursor | — | Ход невалиден |
| `can_move_card` | cursor → card | `{card: source_data}` | Проверка стекинга карты |
| `valid_card` | card → cursor | — | Стекинг валиден |
| `invalid_card` | card → cursor | — | Стекинг невалиден |
| `occupy_slot` | card → slot | `{card, position: vec3, animation?: bool, complete?: bool}` | Карта занимает слот |
| `remove_card` | card → old_slot | `{id}` | Карта покидает слот |
| `highlight` | cursor → slot/card | — | Подсветить объект (tutorial) |
| `unhighlight` | cursor → slot/card | — | Снять подсветку |
| `set_cursor` | cursor → slot | `{slot_id, params?}` | Передать ссылку на курсор слоту |
| `update_free_slot` | free_cell → cursor | `{slot_id, dragon, is_empty, is_blocked?}` | Синхронизация состояния свободной ячейки |
| `send_to_flower_slot` | tableau → cursor | `card` | Автоматический полёт цветка |
| `send_to_base_slot` | tableau → cursor | `card` | Автоматический полёт двойки в foundation |
| `tableau_card_added` | tableau → main | `{index, card: {id, data, slot_id}}` | Дельта-зеркало: карта добавлена в колонку (main.tableau_stacks всегда свежее) |
| `tableau_card_removed` | tableau → main | `{index, id}` | Дельта-зеркало: карта покинула колонку |
| `check_auto_finish` | cursor → main | `{free_cells: [{slot_id, dragon, is_blocked}]}` | Запрос проверки auto-finish; main оценивает ОТЛОЖЕННО (2 кадра в update) |
| `send_auto_finish_check` | main/cursor → cursor | — | Просьба курсору собрать free_cells и переслать check_auto_finish |
| `free_cell_changed` | free_cell → main | `{slot_id, card?, is_blocked}` | Зеркало содержимого ячейки (C4): ФИНАЛЬНОЕ состояние, не дельта. Без `card` = ячейка пуста |
| `flower_collected` | flower_slot → main | — | Цветок сел в свой слот (C5). Иначе снапшот забывает его: из tableau он ушёл, а `snap.flower` жил только на время полёта |
| `collect_done` | main → dragon_button | — | Масть собрана МИМО кнопки (реплей солвера, C6): ставит `is_enable=false` + `check_state`, т.е. состояние после человеческого клика |
| `auto_collect_dragons` | main → cursor | — | Все 27 номиналов в foundation, на столе остались только драконы: курсор нажимает горящие кнопки сбора сам, тем же путём, что палец (`pending_drop` + `get_dragon_cards`), масти разносит по 1.7с. Не шлётся во время `debug_replaying` — доской владеет директор реплея |
| `auto_collect_none` | cursor → main | — | Ответ на предыдущее: не нажато НИ ОДНОЙ кнопки (дракон под драконом, счётчик масти < 4). main засчитывает победу — иначе игрок остаётся без победы вовсе (G2a) |

### Реестр зеркал доски — КТО ЧИТАЕТ (не удалять как «мёртвое»)

Единой модели доски нет: состояние размазано по слотам, а main и cursor держат
зеркала. Таблица нужна ровно затем, чтобы чистка мёртвого кода не выкосила глаза
детектора рассинхрона (перепись C5 живёт в `snapshot_and_go_map` и ловит дрейф
`tableau_stacks`, который кормит **релизный** авто-финиш).

| Зеркало | Кто пишет | Кто читает | Что будет без солвера |
|---|---|---|---|
| `main.tableau_stacks` | раздача; дельта `tableau_card_added/removed`; локальный remove в `auto_finish_step` | **релизный** `can_auto_finish` / `find_next_auto_card` + снапшот | остаётся |
| `main.foundation_top` | `init`; `card_to_base` | **релизный** авто-финиш + снапшот | остаётся |
| `main.free_cell_state` | `init`; `free_cell_changed` (C4) | снапшот + **релизное условие победы** (`live_cells`/`board_cleared`) | остаётся — победа читает его напрямую |
| `main.flower_collected` | `init`; `flower_collected` (C5) | только снапшот | формально мёртв — **не удалять** без решения |
| `cursor.free_slots` | `set_free_slots`; `update_free_slot` | **релизный** путь: `get_dragon_cards`, `send_auto_finish_check` → `can_auto_finish` | остаётся |

Пятое зеркало (`cursor.free_slots`) — то же содержимое, что `free_cell_state`, но
другой владелец и другой потребитель: именно их расхождение и было багом C11.
