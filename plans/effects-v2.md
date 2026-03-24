# Фаза 4 (v2): Оставшиеся эффекты — План для Sonnet

## Контекст

Базовые эффекты уже реализованы (scale drag, bounce drop, shake, glow pulse, lerp drag).
Этот план — оставшиеся эффекты: победный экран, тень карты, авто-перемещение, драконы по дуге.

Файлы: `card.script`, `ui.gui_script`, `cursor.script`, `dragon_button.script`, `base_slot.script`.
Архитектура: [architecture.md](../architecture.md).

---

## Задача 1: Victory текст bounce

**Файл:** `gui/ui.gui_script`

**Что сделать:**
- При показе victory overlay — анимировать popup: scale 0→1.2→1.0 (bounce появление)
- Текст "Victory!" fade-in с задержкой
- Overlay фон fade-in (alpha 0→0.6)

**Где вставить:** после `gui.set_enabled(gui.get_node("victory_overlay"), true)` в блоке `if tutorial_state.show_victory then`

**Код:**
```lua
if tutorial_state.show_victory then
    tutorial_state.show_victory = false

    local overlay = gui.get_node("victory_overlay")
    local popup = gui.get_node("victory_popup")
    local title = gui.get_node("text1")

    if tutorial_state.is_tutorial then
        gui.set_text(title, i18n.t("well_done"))
        gui.set_text(gui.get_node("text"), i18n.t("play_now"))
    else
        gui.set_text(title, i18n.t("victory"))
        gui.set_text(gui.get_node("text"), i18n.t("play_again"))
    end

    gui.set_enabled(overlay, true)

    -- Overlay fade-in
    gui.set_color(overlay, vmath.vector4(0, 0, 0, 0))
    gui.animate(overlay, "color.w", 0.6, gui.EASING_OUTQUAD, 0.4)

    -- Popup bounce: scale 0 → 1.2 → 1.0
    gui.set_scale(popup, vmath.vector3(0, 0, 1))
    gui.animate(popup, "scale", vmath.vector3(1.2, 1.2, 1), gui.EASING_OUTQUAD, 0.3, 0.2, function()
        gui.animate(popup, "scale", vmath.vector3(1, 1, 1), gui.EASING_INQUAD, 0.15)
    end)
end
```

**Важно:**
- Используется `gui.animate`, НЕ `go.animate` (GUI — отдельная система)
- `gui.set_color` работает с RGBA, где `w` = alpha
- Overlay color в ui.gui: `{0, 0, 0, 0.6}` — чёрный полупрозрачный. Мы стартуем с alpha=0 и анимируем до 0.6
- `gui.set_scale` и `gui.animate` работают с `vmath.vector3`, НЕ vector4

---

## Задача 2: Тень под картой при перетаскивании

**Файл:** `main/Scripts/card.script`

**Что сделать:**
- При `start_drag` — затемнить tint карты снизу НЕ получится (один спрайт). Вместо этого: создать "тень" через второй GO не практично.
- **Простой вариант:** при подхвате добавить лёгкое свечение (tint ярче), при отпускании — вернуть обычный tint. Это даёт ощущение "приподнятости".

**Код:**
```lua
-- В "start_drag" (после scale анимации):
sprite.set_constant("#sprite", "tint", vmath.vector4(1.15, 1.15, 1.15, 1))

-- В "drop_success" и "drop_failed" (вместе с scale обратно):
sprite.set_constant("#sprite", "tint", vmath.vector4(1, 1, 1, 1))
```

**Альтернатива (настоящая тень):** Требует добавить дочерний GO с тем же спрайтом, сдвинутым на (3, -3, -0.001), с tint (0, 0, 0, 0.3). Это сложнее — нужно менять card.go в Defold Editor. Если хочется — оставить как отдельную задачу.

---

## Задача 3: Auto-move flash (подсветка при авто-перемещении)

**Файл:** `main/Scripts/card.script`

**Что сделать:**
- Когда карта авто-перемещается (2→foundation, flower→slot), добавить кратковременную вспышку tint
- Индикатор: `message.animation == true` в `drop_success`

**Код (добавить в `drop_success` handler, в начало):**
```lua
elseif message_id == hash("drop_success") then
    self.is_dragging = false
    go.cancel_animations(".", "position")
    go.animate(".", "scale", go.PLAYBACK_ONCE_FORWARD,
        vmath.vector3(1, 1, 1), go.EASING_OUTQUAD, 0.15)

    -- Auto-move flash: если карта перемещена автоматически
    if message.animation then
        sprite.set_constant("#sprite", "tint", vmath.vector4(1.4, 1.4, 1.0, 1))
        timer.delay(0.15, false, function()
            sprite.set_constant("#sprite", "tint", vmath.vector4(1, 1, 1, 1))
        end)
    end

    -- ... остальной код drop_success без изменений
```

**Важно:** `timer.delay` нужен т.к. `sprite.set_constant` нельзя анимировать через `go.animate`. Можно заменить на `go.animate("#sprite", "tint", ...)` если свойство экспортировано — но в Defold tint анимируется через `go.animate(url, "tint", ...)` только для sprite component. Проверить: `go.animate("#sprite", "tint", go.PLAYBACK_ONCE_FORWARD, vmath.vector4(1,1,1,1), go.EASING_LINEAR, 0.3)` — если работает, убрать timer.delay.

**Проверенный вариант с go.animate:**
```lua
if message.animation then
    go.set("#sprite", "tint", vmath.vector4(1.4, 1.4, 1.0, 1))
    go.animate("#sprite", "tint", go.PLAYBACK_ONCE_FORWARD,
        vmath.vector4(1, 1, 1, 1), go.EASING_OUTQUAD, 0.3)
end
```

---

## Задача 4: Fly animation драконов по дуге

**Файл:** `main/Scripts/cursor.script`

**Что сделать:**
- Сейчас при сборе драконов (handler `dragons_collected` в main.script / cursor) карты телепортируются в free cell
- Нужно: анимировать полёт каждого дракона к free cell по дуге (не по прямой)
- Дуга через промежуточную точку (bezier через 2 шага анимации)

**Где искать:** В `cursor.script` найти обработчик сбора драконов. Это может быть в `dragon_button.script` → `msg.post(self.cursor, 'collect_dragons', ...)` → cursor обрабатывает.

**Алгоритм дуги (2 шага):**
```lua
function fly_card_arc(card_id, target_pos, delay, callback)
    local start_pos = go.get_position(card_id)
    -- Промежуточная точка: середина + смещение вверх
    local mid = vmath.vector3(
        (start_pos.x + target_pos.x) / 2,
        math.max(start_pos.y, target_pos.y) + 80,  -- 80px вверх от верхней точки
        0.25  -- над другими картами
    )

    -- Первый отрезок: к середине
    go.animate(card_id, "position", go.PLAYBACK_ONCE_FORWARD,
        mid, go.EASING_OUTQUAD, 0.2, delay, function()
            -- Второй отрезок: к цели
            go.animate(card_id, "position", go.PLAYBACK_ONCE_FORWARD,
                target_pos, go.EASING_INQUAD, 0.2, 0, callback)
        end)
end
```

**Применение:** Вместо `go.set_position(target, dragon_card)` использовать `fly_card_arc(dragon_card, target, i * 0.1)` — каждый дракон вылетает с задержкой.

**Важно:** Нужно найти точное место где драконы перемещаются. Искать `collect_dragons` или `dragon_to_slot` в cursor.script. Также карты после полёта должны правильно встать по z-index.

---

## Задача 5: Улучшить easing авто-перемещения

**Файл:** `main/Scripts/base_slot.script`

**Что сделать:**
- Строка 33: заменить `go.EASING_LINEAR` на `go.EASING_OUTQUAD` для более приятного замедления
- Уменьшить delay с 0.3 до 0.1 (быстрее начинает лететь)

**Код (строка 33):**
```lua
-- Было:
go.animate(message.card.id, "position", go.PLAYBACK_ONCE_FORWARD,
    go.get_position() + vmath.vector3(0, 0, 0.2), go.EASING_LINEAR, 0.5, 0.3, ...)

-- Стало:
go.animate(message.card.id, "position", go.PLAYBACK_ONCE_FORWARD,
    go.get_position() + vmath.vector3(0, 0, 0.2), go.EASING_OUTQUAD, 0.4, 0.1, ...)
```

---

## Порядок реализации

1. **Задача 1** (victory bounce) — самая заметная, только GUI анимации
2. **Задача 5** (easing авто-перемещения) — 1 строка, быстро
3. **Задача 2** (свечение при drag) — 2 строки, быстро
4. **Задача 3** (auto-move flash) — 3-4 строки
5. **Задача 4** (драконы по дуге) — сложнее, нужно найти код сбора

## Что НЕ делаем

- Confetti/particles — нужен particle system asset, отдельная задача
- Hover highlight — нет hover в HTML5 touch
- Настоящая тень (дочерний GO) — нужно править .go в Editor
- Магнит (snap to slot) — сложная логика в cursor, рискованно

## Ветка

`feature/effects-v2` (от master)
