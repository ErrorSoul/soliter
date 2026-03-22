# Рефакторинг — План реализации

## Цель

Разбить God Object `cursor.script` на модули, убрать дублирование и мёртвый код.
**Логика не меняется** — только перемещение кода и require.

---

## Задача 1: config.lua — единый конфиг

**Создать:** `main/Scripts/config.lua`

Вынести все хардкод-константы из разных скриптов в один модуль:

```lua
local M = {}

-- Маппинг цвет → слот (используется в cursor.script и tableau_script.script)
M.BASE_SLOT_TRACE = {
    red = "base_slot1",
    blue = "base_slot2",
    green = "base_slot3"
}

M.DRAGON_BUTTON_TRACE = {
    red = "dragon_button1",
    blue = "dragon_button2",
    green = "dragon_button3"
}

-- Размеры (используются в cursor.script)
M.CARD_SIZE = vmath.vector3(90, 150, 0)
M.CARD_HALF_SIZE = vmath.vector3(45, 75, 0)
M.BTN_SIZE = vmath.vector3(48, 48, 0)
M.BTN_HALF_SIZE = vmath.vector3(24, 24, 0)

-- Z-index слои
M.Z_CARD_DEFAULT = 0.2
M.Z_CARD_DRAGGING = 0.3
M.Z_CARD_LAST_IN_STACK = 0.03
M.Z_CARD_STACK_BASE = 0.002
M.Z_CARD_STACK_STEP = 0.002

-- Стопка
M.STACK_CARD_OFFSET_Y = -35

-- Дисплей
M.DISPLAY_WIDTH = 960
M.DISPLAY_HEIGHT = 540

return M
```

**Затем заменить во всех скриптах:**
- `cursor.script`: убрать `self.size`, `self.half_size`, `self.btn_size`, `self.half_btn_size`, `self.base_slot_trace`, `self.dragon_button_trace`, `DISPLAY_WIDTH`, `DISPLAY_HEIGHT`. Использовать `config.CARD_HALF_SIZE` и т.д.
- `tableau_script.script`: убрать локальный `color_table` в `color_to_cell()`. Использовать `config.DRAGON_BUTTON_TRACE`.
- `tableau_script.script`: заменить магическое `-35` на `config.STACK_CARD_OFFSET_Y`, `0.03`/`0.002` на `config.Z_*`.
- `main.script`: заменить магическое `-35` на `config.STACK_CARD_OFFSET_Y`.
- `card.script`: заменить `0.2` и `0.3` на `config.Z_CARD_DEFAULT` и `config.Z_CARD_DRAGGING`.

---

## Задача 2: coords.lua — координатные преобразования

**Создать:** `main/Scripts/coords.lua`

Вынести единственную рабочую `screen_to_world()` из `cursor.script` (строки 75-101):

```lua
local config = require("main.Scripts.config")
local M = {}

function M.screen_to_world(x, y)
    local w, h = window.get_size()
    w = w / (w / config.DISPLAY_WIDTH)
    h = h / (h / config.DISPLAY_HEIGHT)
    local zoom = math.min(w / config.DISPLAY_WIDTH, h / config.DISPLAY_HEIGHT)
    local offset_x = (w - config.DISPLAY_WIDTH * zoom) / 2
    local offset_y = (h - config.DISPLAY_HEIGHT * zoom) / 2
    local norm_x = (2 * x / w) - 1
    local norm_y = (2 * y / h) - 1
    local world_x = (norm_x + 1) * (config.DISPLAY_WIDTH / 2)
    local world_y = (norm_y + 1) * (config.DISPLAY_HEIGHT / 2)
    world_x = (world_x - offset_x / zoom)
    world_y = (world_y - offset_y / zoom)
    return world_x, world_y
end

return M
```

**В `cursor.script`:**
- Удалить `screena_to_world()` (строки 51-70) — мёртвый код, первая версия
- Удалить `screen_to_world()` (строки 75-101) — перенесена в модуль
- Удалить `screena_to_world()` (строки 106-123) — мёртвый код, вторая версия
- Удалить `FIXED_ZOOM = 2` (строка 103) — не используется
- Удалить `DISPLAY_WIDTH`, `DISPLAY_HEIGHT` (строки 42-43)
- Добавить `local coords = require("main.Scripts.coords")`
- Заменить `screen_to_world(action.x, action.y)` → `coords.screen_to_world(action.x, action.y)`

---

## Задача 3: hit_test.lua — проверки попадания

**Создать:** `main/Scripts/hit_test.lua`

Вынести из `cursor.script`:
- `is_point_in_rect()` (строки 533-538)
- `check_tableau_slots()` (строки 540-598)
- `check_last_cards()` (строки 612-638)
- `check_free_slots()` (строки 640-646)
- `check_flower_slot()` (строки 648-653)
- `check_base_slots()` (строки 655-661)
- `check_free_tableau_slots()` (строки 663-670)
- `check_dragon_buttons()` (строки 672-678)
- `is_card_in_stack()` (строки 601-610)

```lua
local config = require("main.Scripts.config")
local M = {}

function M.is_point_in_rect(x, y, rect_pos, half_size)
    return (x > rect_pos.x - half_size.x and
            x < rect_pos.x + half_size.x and
            y > rect_pos.y - half_size.y and
            y < rect_pos.y + half_size.y)
end

-- Все check_* функции принимают cursor_state (self из cursor.script)
-- и возвращают найденный объект или nil

function M.check_tableau_slots(state, cursor_x, cursor_y)
    -- ... тело из cursor.script, заменить self → state, self.half_size → config.CARD_HALF_SIZE
end

function M.check_last_cards(state, cursor_x, cursor_y)
    -- ... аналогично
end

function M.check_free_slots(state, cursor_x, cursor_y)
    -- ... state.free_slots, config.CARD_HALF_SIZE
end

function M.check_flower_slot(state, cursor_x, cursor_y)
    -- ... state.flower_slot, config.CARD_HALF_SIZE
end

function M.check_base_slots(state, cursor_x, cursor_y)
    -- ... state.base_slots, config.CARD_HALF_SIZE
end

function M.check_free_tableau_slots(state, cursor_x, cursor_y)
    -- ... state.tableau_slots, config.CARD_HALF_SIZE
end

function M.check_dragon_buttons(state, cursor_x, cursor_y)
    -- ... state.dragon_buttons, config.BTN_HALF_SIZE
end

return M
```

**В `cursor.script`:**
- `local hit = require("main.Scripts.hit_test")`
- Заменить все вызовы: `check_tableau_slots(self, x, y)` → `hit.check_tableau_slots(self, x, y)`
- Удалить все перенесённые функции

---

## Задача 4: Удалить мёртвый код

**`cursor.script`:**
- Удалить `screena_to_world()` ×2 (уже в задаче 2)
- Удалить `FIXED_ZOOM` (уже в задаче 2)

**`card.script`:**
- Строка 15-16: `self.is_highlighted = true` в init — убрать (устанавливается дважды: строка 11 и 16, причём 16 перезаписывает 11)
- Строки 17-19: `go.set_position(... 0.2)` в init — проверить, нужен ли (дублирует z-index, который и так 0.2)

**`tableau_script.script`:**
- Строки 115-121: закомментированный код коллизий — удалить
- Закомментированные print/pprint — удалить

---

## Задача 5: Убрать debug-код

**`main.script`:**
- Строка 1: `DEBUG_DEAL = true` → `DEBUG_DEAL = false` (или удалить весь debug_deal блок: строки 69-86 create_debug_stack, строки 108-111 в deal_cards, строки 217-229 в shuffle_deck)

**Все скрипты — удалить pprint():**
- `cursor.script`: строки 202, 380, 491 и другие
- `card.script`: строка 54 (`pprint("[CARD]", message_id)`)
- `tableau_script.script`: строка 46
- `free_cell.script`: строка 45
- `dragon_button.script`: строка 27

**`cursor.script`:**
- `DEBUG_DRAW` и весь блок отрисовки (строки 140-182 в on_input, строки 681-714 в update) — удалить. Переменная `self.debug_text` больше не нужна.

---

## Задача 6: Описать контракты сообщений

**Добавить в `architecture.md`** секцию "Message contracts" — таблицу:

| Message | Sender → Receiver | Параметры | Описание |
|---------|-------------------|-----------|----------|
| `set_card` | main → card | `{data: {value, suit, is_dragon, is_flower}}` | Инициализация карты |
| `start_drag` | cursor → card | — | Начало перетаскивания |
| `drag_update` | cursor → card | `{position: vec3}` | Обновление позиции при drag |
| `drop_success` | cursor → card | `{slot_id, position, card, animation?, complete?}` | Успешный ход |
| `drop_failed` | cursor → card | `{position: vec3}` | Возврат на место |
| `check_slot` | cursor → slot | `{card?}` или `{cards?, source_card?}` | Запрос валидации |
| `slot_valid` | slot → cursor | — | Ход валиден |
| `slot_invalid` | slot → cursor | — | Ход невалиден |
| `can_move_card` | cursor → card | `{card: source_data}` | Проверка стекинга |
| `valid_card` | card → cursor | — | Стекинг валиден |
| `invalid_card` | card → cursor | — | Стекинг невалиден |
| `occupy_slot` | card → slot | `{card, position, animation?, complete?}` | Карта занимает слот |
| `remove_card` | card → old_slot | `{id}` | Карта покидает слот |

---

## Порядок выполнения

1. **Задача 1** (config.lua) — база для остальных
2. **Задача 2** (coords.lua) — простое, убирает мёртвый код
3. **Задача 4** (мёртвый код) — можно совместить с задачей 2
4. **Задача 5** (debug) — независимая, безопасная
5. **Задача 3** (hit_test.lua) — самая большая, после config.lua
6. **Задача 6** (контракты) — документация, в конце

## Что НЕ делаем

- Не рефакторим логику drag state machine (cursor.on_input + on_message) — это рискованно и не блокирует ничего
- Не переделываем z-index систему — config.lua достаточно
- Не трогаем tutorial_state.lua — работает нормально
- Не меняем message-passing на прямые вызовы — это anti-pattern в Defold
