# Auto-finish — План реализации для Sonnet

## Суть

После каждого хода проверяем: если все оставшиеся карты (в tableau + free cells) — numbered и safe для foundation, запускаем авто-доигрывание. Карты по одной летят в foundation с паузой.

---

## Задача 1: Трекинг foundation_top в main.script

**Файл:** `main/Scripts/main.script`

Сейчас `card_to_base` не передаёт suit/value. Нужно трекать верхнюю карту каждого foundation.

**В `init(self)` добавить после `self.base_cards_count = 0`:**
```lua
self.foundation_top = { red = 1, blue = 1, green = 1 }  -- 1 = пусто, ждём 2
```

**Изменить `base_slot.script` строка 27** — передавать suit и value:
```lua
-- Было:
msg.post("/card_table#main", "card_to_base")

-- Стало:
msg.post("/card_table#main", "card_to_base", {
    suit = message.card.data.suit,
    value = message.card.data.value
})
```

**Изменить обработчик `card_to_base` в `main.script`** (строки 303-308):
```lua
if message_id == hash("card_to_base") then
    self.base_cards_count = (self.base_cards_count or 0) + 1
    if message.suit and message.value then
        self.foundation_top[message.suit] = message.value
    end
    if not self.tutorial_mode and self.base_cards_count >= 27 then
        self.currentState = self.states.WIN
        tutorial_state.show_victory = true
    end
end
```

---

## Задача 2: Функция can_auto_finish в main.script

**Добавить в `main/Scripts/main.script`:**

```lua
function can_auto_finish(self)
    if self.tutorial_mode then return false end
    if self.auto_finishing then return false end

    -- Собираем все оставшиеся карты: tableau stacks + free cells
    local remaining = {}

    -- Из tableau
    for i = 1, 8 do
        if self.tableau_stacks[i] then
            for _, card in ipairs(self.tableau_stacks[i].cards) do
                table.insert(remaining, card)
            end
        end
    end

    -- Из free cells (нужно получить через cursor)
    -- free cells хранятся в cursor.script: self.free_slots[id].is_empty / dragon
    -- Но карты в free cells — это GO, а не data.
    -- Проще: проверяем только tableau. Free cell карты тоже нужно проверить.

    for _, card in ipairs(remaining) do
        -- Драконы и цветок не должны оставаться
        if card.data.is_dragon or card.data.is_flower then
            return false
        end
        local v = card.data.value
        local s = card.data.suit
        -- Safe check: другие масти не отстают
        local min_other = 10
        for suit, val in pairs(self.foundation_top) do
            if suit ~= s then
                min_other = math.min(min_other, val)
            end
        end
        if v > min_other + 1 then
            return false
        end
    end

    return #remaining > 0
end
```

**Важно про free cells:** `main.script` не хранит карты free cells напрямую. Варианты:
1. **(Простой)** Проверять только tableau — если в free cells есть карты, они тоже numbered и safe проверка по tableau достаточна. НО: free cell может содержать дракона — тогда нельзя auto-finish. Решение: проверить `cursor.free_slots[id].dragon ~= nil`.
2. **(Правильный)** При вызове `check_auto_finish` cursor отправляет данные о free cells в message.

Рекомендую вариант 2:

```lua
-- cursor.script: при отправке check_auto_finish передать free cell карты
local free_cell_cards = {}
for slot_id, slot in pairs(self.free_slots) do
    if not slot.is_empty then
        table.insert(free_cell_cards, {
            slot_id = slot_id,
            dragon = slot.dragon
        })
    end
end
msg.post("/card_table#main", "check_auto_finish", { free_cells = free_cell_cards })
```

И в `can_auto_finish` добавить проверку:
```lua
-- Если есть непустые free cells с драконами — нельзя auto-finish
if message.free_cells then
    for _, fc in ipairs(message.free_cells) do
        if fc.dragon then
            return false
        end
    end
end
```

---

## Задача 3: auto_finish_step — пошаговая анимация

**Добавить в `main/Scripts/main.script`:**

```lua
function find_next_auto_card(self)
    -- Ищем карту которую можно отправить в foundation
    for i = 1, 8 do
        local stack = self.tableau_stacks[i]
        if stack and #stack.cards > 0 then
            local top_card = stack.cards[#stack.cards]
            if not top_card.data.is_dragon and not top_card.data.is_flower then
                local expected = self.foundation_top[top_card.data.suit] + 1
                if top_card.data.value == expected then
                    return top_card, i, "tableau"
                end
            end
        end
    end
    -- TODO: проверить free cells (нужен доступ к card data)
    return nil
end

function auto_finish_step(self)
    local card, stack_index, source = find_next_auto_card(self)
    if not card then
        -- Все карты перемещены или нечего двигать
        if self.base_cards_count >= 27 then
            self.currentState = self.states.WIN
            tutorial_state.show_victory = true
        end
        self.auto_finishing = false
        msg.post(self.cursor, "enable_input")
        return
    end

    -- Определяем целевой base_slot по масти
    local base_slot_map = {
        red = "base_slot1",
        blue = "base_slot2",
        green = "base_slot3"
    }
    local target_slot = base_slot_map[card.data.suit]

    -- Отправляем карту в foundation через существующий message flow
    msg.post(card.id, "drop_success", {
        slot_id = target_slot,
        position = self.base_slots[target_slot].pos,
        card = card,
        animation = true
    })

    -- Удаляем из tableau
    table.remove(self.tableau_stacks[stack_index].cards)

    -- Обновляем visible cards в tableau
    msg.post("tableau_slot" .. stack_index, "remove_card", { id = card.id })

    -- Следующий шаг через паузу
    timer.delay(0.4, false, function()
        auto_finish_step(self)
    end)
end

function start_auto_finish(self)
    self.auto_finishing = true
    msg.post(self.cursor, "disable_input")
    -- Небольшая пауза перед стартом
    timer.delay(0.5, false, function()
        auto_finish_step(self)
    end)
end
```

**Внимание:** `base_slot_map` должен совпадать с `cursor.script:self.base_slot_trace`. Это дублирование — в идеале вынести в `config.lua` (задача рефакторинга), но пока допустимо.

**Проблема с `base_slot_map`:** маппинг `red→base_slot1` работает только если первая красная карта пошла в base_slot1. Но если юзер сначала положил blue в base_slot1, маппинг сломается.

**Решение:** использовать `cursor.base_slot_trace` через message, или трекать маппинг в main.script:

```lua
-- В init:
self.suit_to_base = {}  -- заполняется когда первая карта масти уходит в base

-- В card_to_base handler:
if message.suit and not self.suit_to_base[message.suit] then
    self.suit_to_base[message.suit] = sender  -- sender = base_slot GO
end
```

Но `sender` в card_to_base — это `/card_table#main` URL, не slot_id. Нужно передавать slot_id:

```lua
-- base_slot.script:
msg.post("/card_table#main", "card_to_base", {
    suit = message.card.data.suit,
    value = message.card.data.value,
    slot_id = self.slot_id
})

-- main.script в card_to_base handler:
if message.suit and message.slot_id then
    self.suit_to_base[message.suit] = message.slot_id
end
```

---

## Задача 4: Вызов проверки после каждого хода

**Файл:** `main/Scripts/main.script`

Добавить обработчик `check_auto_finish` в `on_message`:
```lua
elseif message_id == hash("check_auto_finish") then
    if can_auto_finish(self) then
        start_auto_finish(self)
    end
```

**Файл:** `main/Scripts/cursor.script`

После каждого успешного drop (в обработчиках `slot_valid` и `valid_card`), после `clean_cursor(self)`:
```lua
-- Проверяем auto-finish после хода (не в туториале)
if not tutorial_state.is_tutorial then
    msg.post("/card_table#main", "check_auto_finish")
end
```

Строки для вставки — после `clean_cursor(self)` в:
- `slot_valid` handler (строка ~413)
- `valid_card` handler (строка ~453)

---

## Задача 5: Блокировка ввода

**Файл:** `main/Scripts/cursor.script`

В `init(self)` добавить:
```lua
self.input_disabled = false
```

В начало `on_input` (строка 126), сразу после объявления:
```lua
if self.input_disabled then return end
```

Добавить обработчики в `on_message`:
```lua
elseif message_id == hash("disable_input") then
    self.input_disabled = true
elseif message_id == hash("enable_input") then
    self.input_disabled = false
```

---

## Задача 6: Обновить card_to_base в base_slot.script

**Файл:** `main/Scripts/base_slot.script` строка 27

```lua
-- Было:
msg.post("/card_table#main", "card_to_base")

-- Стало:
msg.post("/card_table#main", "card_to_base", {
    suit = message.card.data.suit,
    value = message.card.data.value,
    slot_id = self.slot_id
})
```

---

## Порядок реализации

1. **Задача 6** — base_slot передаёт suit/value/slot_id (1 строка)
2. **Задача 1** — foundation_top трекинг в main.script
3. **Задача 5** — disable/enable input в cursor
4. **Задача 2** — can_auto_finish
5. **Задача 3** — auto_finish_step + start_auto_finish
6. **Задача 4** — вызов check_auto_finish после каждого хода

## Критерии приёмки

- [ ] После каждого хода — проверка auto-finish
- [ ] Когда все оставшиеся numbered карты safe — запускается авто-доигрывание
- [ ] Карты летят по одной с паузой ~0.4с
- [ ] Ввод заблокирован во время авто-доигрывания
- [ ] После последней карты — victory
- [ ] Не ломает туториал (auto-finish отключен в tutorial_mode)
- [ ] Маппинг suit→base_slot корректен (трекается по первой карте)
- [ ] Restart/Menu кнопки работают во время auto-finish (GUI input отдельный)

## Ветка

`feature/auto-finish` (от master)
