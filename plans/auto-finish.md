# Авто-доигрывание (Auto-finish)

## Контекст

Defold-проект, Shenzhen Solitaire. 960x540, HTML5.

Когда все сложные решения уже приняты и осталось только машинально перекладывать карты в foundation — игра доигрывает за юзера. Классическая фича всех солитеров.

## Когда активировать

**Условие safe auto-finish:**

Карту (value V, suit S) можно безопасно переместить в foundation, если:
1. `V == foundation[S] + 1` (следующая по порядку)
2. Для всех **других** мастей T ≠ S: `foundation[T] >= V - 1`

Правило 2 гарантирует: карта с value V-1 других мастей уже в foundation, значит наша карта никому не нужна как цель для стекинга.

**Полный auto-finish (все карты летят)** — когда ВСЕ оставшиеся карты удовлетворяют условию. На практике это часто случается когда:
- Все драконы собраны
- Flower на месте
- Осталось ~5-15 numbered карт, уже упорядоченных

## Алгоритм

```lua
-- Проверяет, можно ли запустить auto-finish
function can_auto_finish(self)
    -- foundation_values[suit] = top value (1 если пуст, значит ждём 2)
    local fv = {
        red   = self.foundation_top.red   or 1,
        blue  = self.foundation_top.blue  or 1,
        green = self.foundation_top.green or 1,
    }

    -- Проверяем все карты в tableau и free cells
    for _, card in ipairs(self:get_all_remaining_cards()) do
        if card.is_dragon or card.is_flower then
            return false  -- драконы/цветок ещё не собраны — рано
        end
        local v = card.value
        local s = card.suit
        -- Условие 1: карта должна быть достижима в будущем (не сейчас, а вообще)
        -- Условие 2: safe auto-move
        local min_other = 10
        for suit, val in pairs(fv) do
            if suit ~= s then
                min_other = math.min(min_other, val)
            end
        end
        if v > min_other + 1 then
            return false  -- эта карта ещё нужна другим мастям для стекинга
        end
    end

    return true
end
```

## Упрощённый вариант (рекомендуемый)

Вместо сложной проверки — **жадный цикл**: после каждого хода пытаемся переместить верхнюю карту в foundation. Если получилось — повторяем. Если нет — стоп.

```lua
function try_auto_move(self)
    -- Вызывается после каждого хода юзера
    local moved = true
    while moved do
        moved = false
        -- Проверяем верхние карты всех tableau стеков
        for i = 1, 8 do
            local stack = self.tableau_stacks[i]
            if #stack.cards > 0 then
                local top_card = stack.cards[#stack.cards]
                if can_move_to_foundation(top_card) then
                    animate_card_to_foundation(top_card)
                    table.remove(stack.cards)
                    moved = true
                end
            end
        end
        -- Проверяем free cells
        for _, slot in pairs(self.free_slots) do
            if slot.card and can_move_to_foundation(slot.card) then
                animate_card_to_foundation(slot.card)
                slot.card = nil
                moved = true
            end
        end
    end
end

function can_move_to_foundation(card)
    if card.is_dragon or card.is_flower then return false end
    local foundation_top = get_foundation_top(card.suit)
    if card.value ~= foundation_top + 1 then return false end

    -- Safe check: другие масти не отстают слишком сильно
    local min_other = 10
    for _, suit in ipairs({"red", "blue", "green"}) do
        if suit ~= card.suit then
            min_other = math.min(min_other, get_foundation_top(suit))
        end
    end
    return card.value <= min_other + 1
end
```

## Визуальное исполнение

Когда auto-finish активирован:
1. **Пауза 0.3с** между перемещениями (чтоб юзер видел что происходит)
2. Карта **летит по дуге** к своему foundation slot (go.animate position)
3. Звук/эффект при каждом размещении (если есть)
4. После последней карты → **victory**

```lua
function auto_finish_step(self)
    -- Находим следующую карту для auto-move
    local card, source = find_next_auto_card(self)
    if not card then
        -- Все карты перемещены — проверяем победу
        check_and_trigger_victory(self)
        return
    end

    -- Анимируем перемещение
    local target_pos = get_foundation_position(card.suit)
    go.animate(card.id, "position", go.PLAYBACK_ONCE_FORWARD,
        target_pos, go.EASING_OUTQUAD, 0.3, 0, function()
            -- Обновляем состояние
            remove_card_from_source(card, source)
            add_card_to_foundation(card)
            -- Следующий шаг через небольшую паузу
            timer.delay(0.15, false, function()
                auto_finish_step(self)
            end)
        end)
end
```

## Интеграция

### Где вызывать проверку

В `cursor.script` — после каждого успешного drop:
```lua
-- После drop_success на любой слот:
msg.post("/level/card_table", "check_auto_finish")
```

В `main.script`:
```lua
if message_id == hash("check_auto_finish") then
    if can_auto_finish(self) then
        start_auto_finish(self)
    end
end
```

### Отслеживание foundation

Нужно трекать `foundation_top` — текущее верхнее значение каждого foundation:

```lua
-- В main.script
self.foundation_top = { red = 1, blue = 1, green = 1 }  -- 1 = пусто (ждём 2)

-- При получении card_to_base:
if message_id == hash("card_to_base") then
    self.foundation_top[message.suit] = message.value
    self.base_cards_count = self.base_cards_count + 1
    -- ... проверка победы ...
end
```

Для этого `cursor.script` при drop на base_slot должен отправлять suit и value:
```lua
msg.post("/level/card_table", "card_to_base", { suit = card.suit, value = card.value })
```

### Блокировка ввода во время auto-finish

```lua
self.auto_finishing = false

-- В cursor input handler:
if self.auto_finishing then return end  -- игнорируем ввод
```

Флаг `auto_finishing` устанавливается в main.script и передаётся курсору:
```lua
function start_auto_finish(self)
    self.auto_finishing = true
    msg.post(self.cursor, "disable_input")
    auto_finish_step(self)
end
```

## Файлы для изменения

| Файл | Что менять |
|---|---|
| `main/Scripts/main.script` | `foundation_top`, `can_auto_finish`, `auto_finish_step`, `check_auto_finish` message |
| `main/Scripts/cursor.script` | Отправка `check_auto_finish` после drop, `card_to_base` с suit/value, `disable_input` |
| `main/Scripts/base_slot.script` | (возможно) отдавать suit/value при occupy_slot |

## Критерии приёмки

- [ ] После каждого хода проверяется возможность auto-finish
- [ ] Когда все оставшиеся карты safe — запускается авто-доигрывание
- [ ] Карты летят в foundation по одной с паузой ~0.3с
- [ ] Ввод заблокирован во время анимации
- [ ] После последней карты — victory
- [ ] Не ломает обычную игру и туториал
- [ ] `foundation_top` корректно трекается (red/blue/green)

## Ветка

`feature/auto-finish` (от master)

## Зависимости

- **Зависит от tutorial-v2** (или хотя бы от починки победы — `card_to_base` сообщения)
- Если tutorial-v2 уже сделан — `card_to_base` уже отправляется, можно расширить message с suit/value

## Чего НЕ делать

- Не добавлять particle effects (Фаза 4)
- Не менять правила игры
- Не трогать dragon_button логику — только numbered cards авто-летят
- Не блокировать RESTART/MENU кнопки во время auto-finish
