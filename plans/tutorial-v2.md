# Интерактивный туториал v2 (Фаза 3)

## Контекст

Defold-проект, Shenzhen Solitaire. Разрешение 960x540, HTML5.

Текущий туториал — слайдшоу с текстом. Заменить на **интерактивный мини-уровень**: фиксированная раздача из 12 карт, юзер реально двигает карты, подсказки направляют, в конце — мини-победа.

## Предпосылка: баг с определением победы

**КРИТИЧНО:** В `main.script` сломана победа:
1. `self.currentState` никогда не устанавливается в `PLAYING` (остаётся `INIT`)
2. `check_win()` вызывается на строке 343, но **нигде не определена**
3. `show_victory` никогда не отправляется из game loop

Починить в рамках этой задачи.

## Файлы

### Новые

| Файл | Назначение |
|---|---|
| `main/Scripts/tutorial_state.lua` | Lua-модуль: `M.is_tutorial = false` |

### Изменяемые

| Файл | Что менять |
|---|---|
| `main/Scripts/main.script` | Победа через сообщения, `PLAYING` state, фикс. раздача |
| `gui/ui.gui_script` | Слайды → хинты, SKIP кнопка, tutorial_state |
| `gui/ui.gui` | SKIP кнопка, убрать NEXT, поправить верстку |
| `main/Scripts/cursor.script` | Отправлять `tutorial_move` в UI после ходов |

## Часть 1: Починить победу

### 1.1. Победа через сообщения (не polling)

Удалить строки 342-348 из `update()` (check_win polling).

В `cursor.script` — после успешного drop на base_slot:
```lua
msg.post("/level/card_table", "card_to_base")
```

В `main.script` — добавить в `on_message`:
```lua
function on_message(self, message_id, message, sender)
    if message_id == hash("card_to_base") then
        self.base_cards_count = (self.base_cards_count or 0) + 1
        local target = self.tutorial_mode and 6 or 27  -- туториал: 6 карт, обычная: 27
        if self.base_cards_count >= target then
            self.currentState = self.states.WIN
            msg.post("/main#ui", "show_victory")
        end
    end
end
```

### 1.2. State PLAYING

В конце `deal_cards()`:
```lua
self.currentState = self.states.PLAYING
self.base_cards_count = 0
```

## Часть 2: Shared state

### `main/Scripts/tutorial_state.lua`
```lua
local M = {}
M.is_tutorial = false
return M
```

Подключить в `main.script` и `gui/ui.gui_script`:
```lua
local tutorial_state = require("main.Scripts.tutorial_state")
```

## Часть 3: Фиксированная раздача

### Дизайн: 12 карт, ~10 ходов, все механики

**Раскладка (direct placement, НЕ через deal_cards):**

```
Stack 1: d_red (bottom), 2_red (top)         — 2_red → foundation, открывает дракона
Stack 2: d_red (bottom), d_red (top)          — два дракона видны
Stack 3: d_red (bottom), 4_blue (top)         — 4_blue блокирует дракона
Stack 4: flower (bottom), 3_red (top)         — 3_red блокирует flower
Stack 5: 4_green (alone)                      — цель для стекинга 3_red
Stack 6: 2_green (alone)                      — 2_green → foundation
Stack 7-8: пусто
```

12 карт: 4×d_red + 2_red + 3_red + 4_blue + 4_green + flower + 2_green = 10. Хм, 10 карт.

Пересчёт — ровно 10 карт. Стеки 1-3 по 2 карты, стеки 4 по 2, стеки 5-6 по 1, 7-8 пусто.

### Прохождение (каждый ход очевиден):

1. **Move 2_red (S1) → foundation** — "Перетащи двойку в foundation. Собирай масть: 2, 3, 4..."
   S1: d_red открыт.

2. **Move 2_green (S6) → foundation** — "Ещё одна двойка! Drag it."
   S6: пусто.

3. **Move 3_red (S4) onto 4_green (S5)** — "Стекинг: клади карту ДРУГОЙ масти с меньшим значением."
   S4: flower открыт → **flower авто-улетает!** "Цветок уходит автоматически."
   S5: 4_green + 3_red.

4. **Move 3_red (S5) → foundation (red, has 2)** — "Тройка идёт на двойку."
   S5: 4_green.

5. **Move 4_blue (S3) → free cell** — "Эта карта мешает. Убери её во free cell!"
   S3: d_red открыт. **Все 4 дракона теперь видны!**

6. **Press dragon button** — "Все 4 красных дракона на виду! Жми кнопку!"
   Драконы собраны.

7. **WIN!** — foundation: 2_red, 3_red, 2_green. Flower на месте. Драконы собраны.
   Tableau: 4_green (S5), 4_blue (free cell) — остатки, но для туториала ОК.

**Итого: 6 ходов + 1 авто-ход flower + 1 нажатие кнопки.**

Учит:
- ✅ Foundation (шаги 1, 2, 4)
- ✅ Стекинг (шаг 3)
- ✅ Flower авто-ход (после шага 3)
- ✅ Free cell (шаг 5)
- ✅ Dragon button (шаг 6)

### Победа туториала

Победу определяем НЕ по пустому tableau (там останутся 4_green и 4_blue), а **по сбору драконов**. Когда драконы собраны — туториал пройден.

В `main.script`:
```lua
function on_message(self, message_id, message, sender)
    if message_id == hash("dragons_collected") then
        if self.tutorial_mode then
            msg.post("/main#ui", "show_victory")
        end
    end
    -- ... card_to_base для обычной игры ...
end
```

В `dragon_button.script` — после успешного сбора драконов:
```lua
msg.post("/level/card_table", "dragons_collected")
```

### Функция раздачи

Для туториала НЕ использовать `deal_cards()` — она распределяет равномерно. Вместо неё — `deal_tutorial_cards()` с прямым размещением:

```lua
local function deal_tutorial_cards(self)
    local tableau_positions = get_tableau_positions(self)
    self.tableau_stacks = {}

    local layout = {
        -- {stack_index, cards_array} — bottom to top
        {1, {
            {id="d_red", value="d", suit="red", is_dragon=true},
            {id="2_red", value=2, suit="red"},
        }},
        {2, {
            {id="d_red", value="d", suit="red", is_dragon=true},
            {id="d_red", value="d", suit="red", is_dragon=true},
        }},
        {3, {
            {id="d_red", value="d", suit="red", is_dragon=true},
            {id="4_blue", value=4, suit="blue"},
        }},
        {4, {
            {id="flower", value="f", suit="flower", is_flower=true},
            {id="3_red", value=3, suit="red"},
        }},
        {5, {
            {id="4_green", value=4, suit="green"},
        }},
        {6, {
            {id="2_green", value=2, suit="green"},
        }},
    }

    -- Инициализируем все 8 стеков
    for i = 1, 8 do
        local slot_id = "tableau_slot" .. i
        self.tableau_stacks[i] = { slot_id = slot_id, cards = {}, animations_completed = 0 }
    end

    -- Размещаем карты
    for _, stack_def in ipairs(layout) do
        local stack_index = stack_def[1]
        local cards = stack_def[2]
        local stack_position = tableau_positions[stack_index]
        local slot_id = "tableau_slot" .. stack_index

        for card_index, card_data in ipairs(cards) do
            local card_offset = vmath.vector3(0, (card_index - 1) * -35, 0)
            local target_position = stack_position + card_offset

            local card = factory.create("#card_factory", stack_position, vmath.quat(0, 0, 0, 1))
            msg.post(card, "set_card", { data = card_data, slot_id = slot_id })

            table.insert(self.tableau_stacks[stack_index].cards,
                { id = card, data = card_data, slot_id = slot_id })
            table.insert(self.cards, card)

            go.animate(card, "position", go.PLAYBACK_ONCE_FORWARD,
                target_position, go.EASING_LINEAR, 0.3, 0.1 * (stack_index + card_index),
                function()
                    self.tableau_stacks[stack_index].animations_completed =
                        self.tableau_stacks[stack_index].animations_completed + 1
                    if self.tableau_stacks[stack_index].animations_completed == #cards then
                        msg.post(slot_id, "update_stack", {
                            cursor = self.cursor,
                            index = stack_index,
                            stack = self.tableau_stacks[stack_index].cards
                        })
                    end
                end)
        end
    end
end
```

### Модификация init

```lua
function init(self)
    -- ... существующий код до create_deck ...

    self.tutorial_mode = tutorial_state.is_tutorial
    self.cards = {}
    self.cursor = factory.create("#cursor_factory")

    if self.tutorial_mode then
        deal_tutorial_cards(self)
    else
        self.deck = create_deck(self)
        shuffle_deck(self)
        deal_cards(self)
    end

    -- ... остальной init (base_slots, free_slots, etc.) ...
end
```

## Часть 4: Подсказки

### Концепция

Overlay НЕ блокирует игру — `inherit_alpha: false` на highlight, юзер кликает сквозь overlay на карты. Подсказка = текст внизу экрана.

Хинты привязаны к **типу последнего хода**, не к номеру шага:

```lua
-- ui.gui_script
local tutorial_move_count = 0

local TUTORIAL_HINTS = {
    [0] = "Drag a 2 to the foundation slot!",
    [1] = "Another 2! Send it to foundation too.",
    [2] = "Stack 3 on 4 of a DIFFERENT suit.",
    [3] = "Send 3 to its foundation (on top of 2).",
    [4] = "This card blocks a dragon. Move it to a free cell!",
    [5] = "All 4 dragons visible! Press the dragon button!",
}

local function update_tutorial_hint()
    local hint = TUTORIAL_HINTS[tutorial_move_count] or "You did it!"
    gui.set_text(gui.get_node("tutorial_text"), hint)
    gui.set_text(gui.get_node("tutorial_step_text"),
        (tutorial_move_count + 1) .. "/" .. 6)
end
```

### Сообщения от game → UI

В `cursor.script`, `flower_slot.script`, `dragon_button.script` — после ключевых действий:

```lua
if tutorial_state.is_tutorial then
    msg.post("/main#ui", "tutorial_move", { type = "base" })  -- или "free_cell", "flower", "dragon"
end
```

В `ui.gui_script`:
```lua
function on_message(self, message_id, message)
    if message_id == hash("tutorial_move") then
        tutorial_move_count = tutorial_move_count + 1
        update_tutorial_hint()
    elseif message_id == hash("show_victory") then
        if tutorial_state.is_tutorial then
            gui.set_text(gui.get_node("text1"), "Well done!")
            gui.set_text(gui.get_node("text"), "PLAY NOW")
        end
        gui.set_enabled(gui.get_node("victory_overlay"), true)
    end
end
```

## Часть 5: UI

### Кнопка Tutorial → запуск мини-уровня

```lua
if gui.pick_node(gui.get_node("tutorial_button"), action.x, action.y) then
    tutorial_state.is_tutorial = true
    tutorial_move_count = 0
    gui.set_enabled(gui.get_node("tutorial_overlay"), true)
    update_tutorial_hint()
    msg.post("/main#game_manager", "restart_level", { level = {} })
end
```

### SKIP кнопка

Добавить в `ui.gui`:

```
tutorial_skip_btn (child of tutorial_overlay):
  position: 430, 240
  size: 60x30
  color: 0.5, 0.5, 0.5
  type: TYPE_BOX
  size_mode: SIZE_MODE_MANUAL
  inherit_alpha: false

tutorial_skip_text (child of tutorial_skip_btn):
  text: "SKIP"
  font: main_font
  color: 1, 1, 1
```

Обработка:
```lua
if tutorial_state.is_tutorial then
    if gui.pick_node(gui.get_node("tutorial_skip_btn"), action.x, action.y) then
        tutorial_state.is_tutorial = false
        gui.set_enabled(gui.get_node("tutorial_overlay"), false)
        msg.post("/main#game_manager", "restart_level", { level = {} })
        return true
    end
end
```

### Верстка

```
tutorial_text_bg:   size: 800x80 (было 700x100)
tutorial_text:      size: 760x60, position: 0, 0
tutorial_next_btn:  УДАЛИТЬ (не нужен — хинты меняются автоматически)
tutorial_next_text: УДАЛИТЬ
tutorial_step_text: оставить, сдвинуть под text_bg
```

### Туториальная победа

При нажатии "PLAY NOW" в victory overlay:
```lua
if tutorial_state.is_tutorial then
    tutorial_state.is_tutorial = false
    gui.set_enabled(victory_overlay, false)
    gui.set_enabled(gui.get_node("tutorial_overlay"), false)
    msg.post("/main#game_manager", "restart_level", { level = {} })
end
```

## Удалить старый код

- `TUTORIAL_STEPS` таблица
- `tutorial_step` переменная
- `show_tutorial_step()`, `start_tutorial()`, `stop_tutorial()`, `next_tutorial_step()`
- Блок `if tutorial_step > 0 then` в `on_input()`

## Порядок реализации

1. Создать `tutorial_state.lua`
2. Починить победу: сообщения `card_to_base` / `dragons_collected`, убрать check_win из update
3. Добавить `deal_tutorial_cards()` в main.script
4. Добавить `tutorial_move` сообщения в cursor/flower_slot/dragon_button
5. Переделать ui.gui_script: хинты вместо слайдов, SKIP
6. Обновить ui.gui: SKIP кнопка, убрать NEXT, верстка
7. Тестировать: пройти туториал от начала до победы

## Критерии приёмки

- [ ] `tutorial_state.lua` создан и подключен
- [ ] Победа работает через сообщения (и обычная, и туториальная)
- [ ] Фиксированная раздача из 10 карт в 6 стеках
- [ ] 6 ходов: foundation → foundation → стекинг → foundation → free cell → dragon button
- [ ] Flower авто-улетает после шага 3
- [ ] Подсказки меняются после каждого хода
- [ ] SKIP выходит из туториала
- [ ] Победа туториала → "Well done! PLAY NOW"
- [ ] Обычная игра не сломана
- [ ] Нет ошибок в консоли

## Ветка

`feature/tutorial-v2` (от master)

## Чего НЕ делать

- Не менять collection layout — только логику раздачи
- Не ломать обычную игру
- Не добавлять анимации подсказок
- Не удалять tutorial ноды из ui.gui — переиспользуем
