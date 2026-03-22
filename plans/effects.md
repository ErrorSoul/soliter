# Фаза 4: Эффекты и анимации — План реализации

## Контекст

Все эффекты реализуются через `go.animate()` и `sprite.set_constant()` (tint).
Файлы для редактирования: `card.script`, `cursor.script`, `base_slot.script`, `free_cell.script`, `flower_slot.script`, `dragon_button.script`, `tableau_script.script`.
Архитектура описана в [architecture.md](../architecture.md).

---

## Задача 1: Scale up при подхвате карты

**Файл:** `main/Scripts/card.script`

**Что сделать:**
- В обработчике `"start_drag"` — анимировать scale карты 1.0 → 1.1 за 0.1s, easing OUTQUAD
- В обработчике `"drop_success"` и `"drop_failed"` — анимировать scale обратно 1.1 → 1.0 за 0.15s, easing OUTQUAD

**Код:**
```lua
-- В "start_drag":
self.is_dragging = true
go.animate(".", "scale", go.PLAYBACK_ONCE_FORWARD,
    vmath.vector3(1.1, 1.1, 1), go.EASING_OUTQUAD, 0.1)

-- В "drop_success" и "drop_failed" (перед остальным кодом):
go.animate(".", "scale", go.PLAYBACK_ONCE_FORWARD,
    vmath.vector3(1, 1, 1), go.EASING_OUTQUAD, 0.15)
```

**Стек-карты:** cursor.script посылает `start_drag` каждой карте стека — scale автоматически применится ко всем.

---

## Задача 2: Bounce при успешном drop

**Файл:** `main/Scripts/card.script`

**Что сделать:**
- В обработчике `"drop_success"` (после отправки `occupy_slot`) — анимировать scale pulse: 1.0 → 1.08 → 1.0
- Использовать два последовательных `go.animate` через callback

**Код:**
```lua
-- В "drop_success", после основной логики:
go.animate(".", "scale", go.PLAYBACK_ONCE_FORWARD,
    vmath.vector3(1.08, 1.08, 1), go.EASING_OUTQUAD, 0.1, 0, function()
        go.animate(".", "scale", go.PLAYBACK_ONCE_FORWARD,
            vmath.vector3(1, 1, 1), go.EASING_INQUAD, 0.1)
    end)
```

---

## Задача 3: Shake при невалидном ходе

**Файл:** `main/Scripts/card.script`

**Что сделать:**
- В обработчике `"drop_failed"` — после анимации возврата на место, добавить горизонтальную тряску
- Тряска: 3 колебания по X (±5px) за 0.3s
- Реализовать через серию `go.animate` с чередованием направления, ИЛИ через один `go.animate` с `EASING_OUTSINE` + `PLAYBACK_ONCE_PINGPONG`

**Код (простой вариант):**
```lua
-- В "drop_failed", в callback анимации возврата:
go.animate(".", "position", go.PLAYBACK_ONCE_FORWARD,
    message.position, go.EASING_OUTQUAD, 0.3, 0, function()
        local pos = go.get_position()
        go.animate(".", "position.x", go.PLAYBACK_ONCE_FORWARD,
            pos.x + 5, go.EASING_OUTSINE, 0.05, 0, function()
                go.animate(".", "position.x", go.PLAYBACK_ONCE_FORWARD,
                    pos.x - 5, go.EASING_OUTSINE, 0.05, 0, function()
                        go.animate(".", "position.x", go.PLAYBACK_ONCE_FORWARD,
                            pos.x + 3, go.EASING_OUTSINE, 0.05, 0, function()
                                go.animate(".", "position.x", go.PLAYBACK_ONCE_FORWARD,
                                    pos.x, go.EASING_OUTSINE, 0.05)
                            end)
                    end)
            end)
    end)
```

**Важно:** shake должен работать и для стека карт. В `cursor.script` при `invalid_card` / `slot_invalid` — `drop_failed` посылается каждой карте стека, значит каждая будет трястись (это ок, визуально смотрится как одна тряска).

---

## Задача 4: Glow pulse кнопки дракона

**Файл:** `main/Scripts/dragon_button.script`

**Что сделать:**
- Когда кнопка становится активной (в `check_state()`, условие `counter==4 && free_slot_any`) — запустить бесконечную пульсацию scale
- Когда кнопка деактивируется — остановить пульсацию, вернуть scale в 1.0

**Код:**
```lua
function check_state(self)
    if self.is_enable and self.counter == 4 and free_slot_any(self) then
        msg.post("#sprite", "play_animation", {id = hash("button" .. "_" .. self.sprite)})
        msg.post(self.cursor, 'set_button_state', {slot_id = self.slot_id, is_active = true})
        -- Запускаем пульсацию
        go.cancel_animations(".", "scale")
        go.animate(".", "scale", go.PLAYBACK_LOOP_PINGPONG,
            vmath.vector3(1.15, 1.15, 1), go.EASING_INSINE, 0.5)
    else
        msg.post("#sprite", "play_animation", {id = hash("button" .. "_" .. self.default_sprite)})
        msg.post(self.cursor, 'set_button_state', {slot_id = self.slot_id, is_active = false})
        -- Останавливаем пульсацию
        go.cancel_animations(".", "scale")
        go.set(".", "scale", vmath.vector3(1, 1, 1))
    end
end
```

---

## Задача 5: Плавный подхват карты (lerp к курсору)

**Файл:** `main/Scripts/card.script`

**Что сделать:**
- Сейчас при `drag_update` карта телепортируется: `go.set_position(message.position + z)`
- Заменить на `go.animate` с очень короткой длительностью (0.05s) и OUTQUAD easing
- Нужно отменять предыдущую анимацию перед запуском новой

**Код:**
```lua
elseif message_id == hash("drag_update") and self.is_dragging then
    go.cancel_animations(".", "position")
    local target = message.position + vmath.vector3(0, 0, 0.3)
    go.animate(".", "position", go.PLAYBACK_ONCE_FORWARD,
        target, go.EASING_OUTQUAD, 0.05)
```

**Внимание:** это может добавить input lag. Если ощущения плохие — уменьшить до 0.03s или вернуть `go.set_position`. Тестировать обязательно.

---

## Задача 6: Раздача карт веером (улучшить deal)

**Файл:** `main/Scripts/main.script`

**Что сделать:**
- Сейчас карты летят из позиции стопки. Изменить: все карты начинают из одной центральной точки (480, 270) — центр экрана
- Easing: заменить LINEAR на OUTQUAD для более приятного замедления
- Добавить начальный scale 0.5 → 1.0 параллельно с полётом

**Код (в `deal_cards`):**
```lua
local start_pos = vmath.vector3(480, 270, 0.2)
local card = factory.create("#card_factory", start_pos, vmath.quat(0, 0, 0, 1))
-- ... set_card ...
go.set(".", "scale", vmath.vector3(0.5, 0.5, 1), card)
go.animate(card, "scale", go.PLAYBACK_ONCE_FORWARD,
    vmath.vector3(1, 1, 1), go.EASING_OUTQUAD, 0.5, delay)
go.animate(card, "position", go.PLAYBACK_ONCE_FORWARD,
    target_position, go.EASING_OUTQUAD, 0.5, delay, callback)
```

Аналогично для `deal_tutorial_cards`.

---

## Порядок реализации

1. **Задача 1** (scale up drag) — самая простая, 5 строк
2. **Задача 2** (bounce drop) — простая, 5 строк
3. **Задача 4** (glow pulse) — простая, в одном файле
4. **Задача 3** (shake) — средняя, вложенные callbacks
5. **Задача 5** (lerp drag) — рискованная, может добавить lag
6. **Задача 6** (deal веером) — средняя, два места правки

## Что НЕ делаем в этом PR

- Тень под картой (нужен дополнительный sprite/GO — отдельная задача)
- 3D покачивание (skew через scale.x — экспериментальное, отдельно)
- Confetti/particles (нужен particle system — отдельная задача)
- Victory текст bounce (UI анимации в gui_script — отдельная задача)
- Hover highlight (нет hover event в HTML5 touch — неприменимо)
- Auto-move flash (зависит от auto-finish, которая ещё не готова)
- Fly animation драконов по дуге (сложная, отдельная задача)
