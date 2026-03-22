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
```
base_slot.occupy_slot()
  → msg.post("/card_table#main", "card_to_base")
  → main: base_cards_count++ → если ≥27: show_victory=true

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
