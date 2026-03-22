# Дизайн кнопок (Фаза 2)

## Контекст

Defold-проект, Shenzhen Solitaire. Разрешение 960x540, HTML5.

Сейчас кнопки Restart, Tutorial и victory_restart1 — белые квадраты (дефолтная текстура) с кривым scale, расположены в левой части экрана и **перекрывают free_slots** и **dragon_buttons**. Нужно стилизовать и переместить.

## Текущее расположение элементов (game objects в level collection)

```
Верхний ряд (y=457):
  free_slot1:  x=80    free_slot2: x=193   free_slot3: x=309
  dragon_btn1: x=420 y=511
  dragon_btn2: x=420 y=463
  dragon_btn3: x=420 y=416
  flower_slot: x=541
  base_slot3:  x=657   base_slot2: x=773   base_slot1: x=889

Tableau (y=299-300):
  slot1: x=77  slot2: x=193  slot3: x=309  slot4: x=425
  slot5: x=541 slot6: x=657  slot7: x=773  slot8: x=889
```

Текущие GUI-кнопки (проблема — перекрывают free_slots!):
- `restart_button`: position 151, 465 (прямо на free_slot2!)
- `tutorial_button`: position 151, 406
- `victory_restart1`: position 150, 344

## Что сделать

1. Переместить кнопки в безопасную зону — **правый нижний угол** (не перекрывают ни слоты, ни карты)
2. Стилизовать кнопки: тёмно-зелёный фон с рамкой, текст шрифтом main_font
3. Убрать кривые scale, использовать SIZE_MODE_MANUAL с нормальными размерами
4. Удалить дублирующую кнопку `victory_restart1` — она дублирует `restart_button`
5. Удалить мёртвый код `show_popup`/`hide_popup`

## Архитектура

**Подход:** Только изменения в `gui/ui.gui` и `gui/ui.gui_script`. Никаких новых файлов.

## Файлы для изменения

| Файл | Что менять |
|---|---|
| `gui/ui.gui` | Переместить и переделать ноды кнопок, удалить victory_restart1 |
| `gui/ui.gui_script` | Убрать victory_restart1, убрать мёртвый код show_popup/hide_popup |

## Детали реализации

### Layout кнопок

Новое расположение — **правый нижний угол**, горизонтально:

```
restart_button:  position: 830, 30    size: 120x40
tutorial_button: position: 700, 30    size: 120x40
```

Это пространство свободно — tableau_slot8 начинается на x=889, y=300, карты идут вниз до примерно y=80-100, но x=700-950 в нижней полосе y<50 свободен.

### Ноды в `ui.gui` (переделать):

**restart_button:**
```
position: 830, 30
scale: 1, 1 (убрать 0.489, 0.455)
size: 120x40
size_mode: SIZE_MODE_MANUAL (заменить SIZE_MODE_AUTO)
color: 0.15, 0.3, 0.15 (тёмно-зелёный, как start_screen)
layer: "buttons"
```

**restart_text (child of restart_button):**
```
position: 0, 0 (убрать offset 2.04, -2.19)
size: 120x40
text: "RESTART" (убрать лишние \n)
font: main_font
color: 1, 1, 1 (белый текст на тёмном фоне)
blend_mode: BLEND_MODE_ALPHA (заменить BLEND_MODE_MULT)
adjust_mode: по умолчанию (убрать ADJUST_MODE_STRETCH)
outline: опционально (0.2, 0.2, 0.2) для читаемости
```

**tutorial_button:**
```
position: 700, 30
scale: 1, 1
size: 120x40
size_mode: SIZE_MODE_MANUAL
color: 0.15, 0.3, 0.15
layer: "buttons"
```

**restart_text1 (child of tutorial_button) — переименовать в tutorial_text:**
НЕ переименовывать (ID менять нельзя без пересоздания ноды, а в коде не используется). Просто поменять свойства:
```
position: 0, 0
size: 120x40
text: "TUTORIAL" (убрать лишние \n)
font: main_font
color: 1, 1, 1
blend_mode: BLEND_MODE_ALPHA
adjust_mode: по умолчанию
```

### Удалить ноды:

- `victory_restart1` — вся нода с child `text2`. Дублирует restart_button
  - Сейчас: position 150,344, красный фон, текст "RESTART"
  - Не нужна: restart_button и так всегда видна во время игры

### Изменения в `ui.gui_script`:

1. **Удалить мёртвый код** (строки 1-7):
```lua
-- УДАЛИТЬ:
local function show_popup(self, popup_node)
    gui.set_enabled(gui.get_node(popup_node), true)
end

local function hide_popup(self, popup_node)
    gui.set_enabled(gui.get_node(popup_node), false)
end
```

2. **Убрать все упоминания victory_restart1:**
- `init()`: убрать `gui.set_enabled(gui.get_node("victory_restart1"), false)`
- `on_input()` start screen handler: убрать `gui.set_enabled(gui.get_node("victory_restart1"), true)`
- `on_input()` victory overlay handler: убрать `gui.set_enabled(gui.get_node("victory_restart1"), false)`
- `on_input()` game buttons: убрать блок с `victory_restart1`

3. **Финальный ui.gui_script** должен выглядеть так:

```lua
local function restart_level()
   msg.post("/main#game_manager", "restart_level", { level = {} })
end

function init(self)
    msg.post(".", "acquire_input_focus")
    -- Скрыть игровые кнопки до начала игры
    gui.set_enabled(gui.get_node("restart_button"), false)
    gui.set_enabled(gui.get_node("tutorial_button"), false)
    -- Victory overlay скрыт по умолчанию
    gui.set_enabled(gui.get_node("victory_overlay"), false)
    -- Стартовый экран включён по умолчанию
    self.game_started = false
end

function on_input(self, action_id, action)
    if action_id == hash("touch") and action.pressed then
        -- Обработка стартового экрана
        if not self.game_started then
            local play_button = gui.get_node("play_button")
            if gui.pick_node(play_button, action.x, action.y) then
                gui.set_enabled(gui.get_node("start_screen"), false)
                gui.set_enabled(gui.get_node("restart_button"), true)
                gui.set_enabled(gui.get_node("tutorial_button"), true)
                msg.post("/main#game_manager", "start_game")
                self.game_started = true
            end
            return true
        end

        -- Victory overlay
        local victory_overlay = gui.get_node("victory_overlay")
        if gui.is_enabled(victory_overlay) then
            local restart = gui.get_node("victory_restart")
            local menu = gui.get_node("victory_menu_button")

            if gui.pick_node(restart, action.x, action.y) then
                gui.set_enabled(victory_overlay, false)
                restart_level()
            elseif gui.pick_node(menu, action.x, action.y) then
                gui.set_enabled(victory_overlay, false)
                gui.set_enabled(gui.get_node("start_screen"), true)
                gui.set_enabled(gui.get_node("restart_button"), false)
                gui.set_enabled(gui.get_node("tutorial_button"), false)
                self.game_started = false
                msg.post("/main#game_manager", "unload_level")
            end

            return true
        end

        -- Игровые кнопки
        if gui.pick_node(gui.get_node("restart_button"), action.x, action.y) then
            restart_level()
        end

        if gui.pick_node(gui.get_node("tutorial_button"), action.x, action.y) then
            -- tutorial — reserved for future use
        end
    end
end

function on_message(self, message_id, message)
    if message_id == hash("show_victory") then
        gui.set_enabled(gui.get_node("victory_overlay"), true)
    end
end
```

## Definition of Done

1. Кнопки Restart и Tutorial перемещены в правый нижний угол, не перекрывают игровые слоты
2. Кнопки стилизованы: тёмно-зелёный фон, белый текст, ровный scale
3. Нода victory_restart1 удалена (вместе с child text2)
4. Мёртвый код show_popup/hide_popup удалён
5. Все ссылки на victory_restart1 убраны из ui.gui_script

## Критерии приёмки

- [ ] restart_button перемещена на ~(830, 30), size 120x40, SIZE_MODE_MANUAL
- [ ] tutorial_button перемещена на ~(700, 30), size 120x40, SIZE_MODE_MANUAL
- [ ] Обе кнопки: зелёный фон, белый текст, scale 1x1
- [ ] Текст кнопок без лишних \n, blend_mode ALPHA
- [ ] Нода victory_restart1 и text2 удалены из ui.gui
- [ ] Все упоминания victory_restart1 убраны из ui.gui_script
- [ ] show_popup/hide_popup удалены из ui.gui_script
- [ ] Кнопки не перекрывают free_slots, dragon_buttons и tableau
- [ ] Нет ошибок в консоли

## Ветка

`feature/button-design` (уже создана от master)

## Чего НЕ делать

- Не добавлять текстуры/атласы — только цветовая стилизация через ноды
- Не добавлять анимации (hover, press) — будет в Фазе 4
- Не менять game_manager.script или main.script
- Не менять ноды victory popup, start_screen или любые game objects
- Не создавать новые файлы
