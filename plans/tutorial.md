# Интерактивный туториал (Фаза 3)

## Контекст

Defold-проект, Shenzhen Solitaire. Разрешение 960x540, HTML5.

Туториал — пошаговый гайд, объясняющий правила игры. Показывается при нажатии кнопки TUTORIAL во время игры. Каждый шаг: затемнение экрана + подсветка нужной зоны + текст-подсказка. Тап — следующий шаг. На последнем шаге — кнопка "Понял!" закрывает туториал.

## Правила игры (для понимания контекста)

Shenzhen Solitaire — карточный пасьянс:

- **3 масти**: красная, синяя, зелёная. Карты от 2 до 10 в каждой масти.
- **Драконы**: по 4 карты-дракона каждого цвета (12 всего).
- **Цветок**: 1 карта-цветок.
- **Итого**: 27 числовых + 12 драконов + 1 цветок = 40 карт.

**Зоны поля (координаты для справки):**
```
Верхний ряд (y≈457):
  Free cells (3 шт):   x=80, 193, 309     — временное хранение
  Dragon buttons (3):   x=420, y=511/463/416 — кнопки сбора драконов
  Flower slot:          x=541               — слот для цветка
  Base slots (3):       x=657, 773, 889     — собираем масти 2→10

Tableau (8 стопок, y≈299):
  x = 77, 193, 309, 425, 541, 657, 773, 889
  Карты идут вниз от стопки со смещением ~30px
```

**Правила:**
- На tableau: класть карту ДРУГОЙ масти с меньшим значением (напр. 7 красная на 8 синюю)
- Free cells: положить любую одну карту, максимум 3 ячейки
- Base slots: собирать одну масть от 2 до 10 по порядку
- Драконы: когда все 4 дракона одного цвета открыты → кнопка собирает их в free cell
- Цветок: автоматически уходит в flower slot
- Победа: все base slots заполнены (2→10 каждая масть)

## Что сделать

Добавить туториал из 7 шагов, целиком в GUI (gui/ui.gui + gui/ui.gui_script). Каждый шаг подсвечивает зону и показывает текст.

## Архитектура

**Подход:** Всё через GUI ноды. Один тёмный overlay на весь экран + "окна" (светлые box-ноды) поверх overlay для подсветки зон + текстовая панель с описанием + кнопка "Далее" / "Понял!".

**Почему окна, а не вырезы:** В Defold GUI нет стенсилов для "дырок" в overlay. Вместо этого используем `inherit_alpha: true` на child-нодах overlay, и добавляем белые/светлые box-ноды поверх в нужных позициях, имитируя подсветку. Или проще: 4 тёмных прямоугольника вокруг подсвечиваемой зоны.

**Выбранный подход — самый простой:** Один overlay (затемнение) + одна highlight-нода (светлый прямоугольник с alpha ~0.3, белый) которая перемещается на каждом шаге + текстовая панель + кнопка.

**Поток:**
1. Игрок нажимает TUTORIAL → `ui.gui_script` показывает tutorial overlay, шаг 1
2. Игрок тапает → переход к шагу 2, 3, ... 7
3. На шаге 7 кнопка "Понял!" → скрыть overlay

## Файлы для изменения

| Файл | Что менять |
|---|---|
| `gui/ui.gui` | Добавить ноды туториала |
| `gui/ui.gui_script` | Добавить логику шагов |

## Детали реализации

### Ноды в `ui.gui` (добавить):

```
tutorial_overlay (TYPE_BOX) — затемнение всего экрана
  position: 480, 270
  size: 960x540
  color: 0, 0, 0
  alpha (w): 0.7
  layer: "buttons"
  enabled: false
  inherit_alpha: true

  └─ tutorial_highlight (TYPE_BOX) — подсветка зоны (перемещается скриптом)
     position: 480, 299  (начальная — tableau зона)
     size: 920x200       (начальная — ширина tableau)
     color: 1, 1, 1      (белый)
     alpha (w): 0.15      (еле видимый, чтобы зона "светилась")
     inherit_alpha: false (НЕ наследует alpha от overlay, иначе будет слишком тёмным)

  └─ tutorial_text_bg (TYPE_BOX) — фон для текста
     position: 0, -220   (внизу экрана, relative to overlay center)
     size: 700x100
     color: 0.1, 0.2, 0.1  (очень тёмно-зелёный)
     alpha (w): 0.95
     inherit_alpha: false

     └─ tutorial_text (TYPE_TEXT) — текст подсказки
        position: 0, 15
        size: 660x60
        font: main_font
        color: 1, 1, 1 (белый)
        text: "" (задаётся скриптом)
        line_break: true

     └─ tutorial_next_btn (TYPE_BOX) — кнопка "Далее"
        position: 0, -35
        size: 120x30
        color: 0.3, 0.5, 0.3 (зелёный)

        └─ tutorial_next_text (TYPE_TEXT) — текст кнопки
           size: 120x30
           font: main_font
           color: 1, 1, 1
           text: "NEXT"  (меняется на "GOT IT!" на последнем шаге)

  └─ tutorial_step_text (TYPE_TEXT) — индикатор шага "1/7"
     position: 330, -180
     size: 60x30
     font: main_font
     color: 0.7, 0.7, 0.7
     text: "1/7"
     inherit_alpha: false
```

### Шаги туториала (данные для скрипта):

```lua
local TUTORIAL_STEPS = {
    {
        -- Шаг 1: Обзор поля
        highlight_pos = vmath.vector3(480, 270, 0),   -- центр всего поля
        highlight_size = vmath.vector3(920, 400, 0),   -- почти весь экран
        text = "Welcome to Shenzhen Solitaire!\nThe goal: sort all cards by suit from 2 to 10.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        -- Шаг 2: Tableau
        highlight_pos = vmath.vector3(480, 250, 0),   -- зона tableau
        highlight_size = vmath.vector3(860, 250, 0),   -- 8 стопок
        text = "These are the tableau stacks.\nDrag cards here: different suit, descending value.\nExample: red 7 on blue 8 — OK. Red 7 on red 8 — NO.",
        text_bg_pos = vmath.vector3(0, 220, 0),       -- текст сверху, чтоб не перекрывать
    },
    {
        -- Шаг 3: Free Cells
        highlight_pos = vmath.vector3(193, 457, 0),    -- центр 3 free cells
        highlight_size = vmath.vector3(300, 90, 0),
        text = "Free cells — temporary storage.\nYou can place any single card here. Max 3 cards.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        -- Шаг 4: Base Slots
        highlight_pos = vmath.vector3(773, 457, 0),    -- центр 3 base slots
        highlight_size = vmath.vector3(300, 90, 0),
        text = "Foundation slots — your goal!\nStack cards of the SAME suit from 2 to 10.\nFill all three to win.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        -- Шаг 5: Драконы
        highlight_pos = vmath.vector3(420, 463, 0),    -- кнопки драконов
        highlight_size = vmath.vector3(80, 140, 0),
        text = "Dragon buttons — collect dragons!\nWhen all 4 dragons of one color are face-up,\npress the button to sweep them into a free cell.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        -- Шаг 6: Цветок
        highlight_pos = vmath.vector3(541, 457, 0),    -- flower slot
        highlight_size = vmath.vector3(100, 90, 0),
        text = "The Flower card goes here automatically.\nIt's a free bonus — no action needed!",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        -- Шаг 7: Победа
        highlight_pos = vmath.vector3(480, 270, 0),
        highlight_size = vmath.vector3(920, 400, 0),
        text = "Clear the tableau by sorting all cards\ninto the foundation — and you win!\nGood luck!",
        text_bg_pos = vmath.vector3(0, -220, 0),
        next_text = "GOT IT!",  -- вместо "NEXT"
    },
}
```

### Изменения в `ui.gui_script`:

Добавить данные шагов и функции управления туториалом:

```lua
-- Данные шагов (таблица TUTORIAL_STEPS — см. выше)

local tutorial_step = 0  -- 0 = туториал не активен

local function show_tutorial_step(step)
    local data = TUTORIAL_STEPS[step]
    if not data then return end

    local highlight = gui.get_node("tutorial_highlight")
    gui.set_position(highlight, data.highlight_pos)
    gui.set_size(highlight, data.highlight_size)

    local text_bg = gui.get_node("tutorial_text_bg")
    gui.set_position(text_bg, data.text_bg_pos)

    gui.set_text(gui.get_node("tutorial_text"), data.text)
    gui.set_text(gui.get_node("tutorial_step_text"), step .. "/" .. #TUTORIAL_STEPS)

    -- Текст кнопки
    local next_text = data.next_text or "NEXT"
    gui.set_text(gui.get_node("tutorial_next_text"), next_text)
end

local function start_tutorial()
    tutorial_step = 1
    gui.set_enabled(gui.get_node("tutorial_overlay"), true)
    show_tutorial_step(1)
end

local function stop_tutorial()
    tutorial_step = 0
    gui.set_enabled(gui.get_node("tutorial_overlay"), false)
end

local function next_tutorial_step()
    tutorial_step = tutorial_step + 1
    if tutorial_step > #TUTORIAL_STEPS then
        stop_tutorial()
    else
        show_tutorial_step(tutorial_step)
    end
end
```

**В `init()`** добавить:
```lua
gui.set_enabled(gui.get_node("tutorial_overlay"), false)
```

**В `on_input()`** — ПОСЛЕ проверки start_screen, ПЕРЕД проверкой victory_overlay, добавить блок:

```lua
-- Обработка туториала
if tutorial_step > 0 then
    local next_btn = gui.get_node("tutorial_next_btn")
    if gui.pick_node(next_btn, action.x, action.y) then
        next_tutorial_step()
    end
    return true  -- блокируем input для игры
end
```

**В блоке обработки tutorial_button** (сейчас пустой комментарий `-- tutorial — reserved for future use`) заменить на:
```lua
if gui.pick_node(gui.get_node("tutorial_button"), action.x, action.y) then
    start_tutorial()
end
```

### Важные моменты:

1. `tutorial_highlight` должен иметь `inherit_alpha: false` — иначе он будет затемнён вместе с overlay и не будет видна "подсветка"
2. `tutorial_text_bg` тоже `inherit_alpha: false` — чтобы текст был читаемым
3. `tutorial_step_text` — `inherit_alpha: false`
4. highlight_pos координаты — это **абсолютные** координаты на экране (потому что parent overlay центрирован на 480,270, а highlight_pos задаётся через `gui.set_position` **RELATIVE** к parent). Поэтому нужно пересчитать:
   - Если overlay position = 480,270, а highlight нужен на экранной позиции 193,457:
   - Relative position = 193-480, 457-270 = **-287, 187**

   **ВАЖНО: Все координаты в TUTORIAL_STEPS должны быть RELATIVE к центру overlay (480,270)!**

Исправленные координаты:
```lua
local TUTORIAL_STEPS = {
    {
        highlight_pos = vmath.vector3(0, 0, 0),          -- центр экрана = центр overlay
        highlight_size = vmath.vector3(920, 400, 0),
        text = "Welcome to Shenzhen Solitaire!\nThe goal: sort all cards by suit from 2 to 10.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        highlight_pos = vmath.vector3(0, -20, 0),         -- tableau чуть ниже центра
        highlight_size = vmath.vector3(860, 250, 0),
        text = "These are the tableau stacks.\nDrag cards here: different suit, descending value.\nExample: red 7 on blue 8 — OK. Red 7 on red 8 — NO.",
        text_bg_pos = vmath.vector3(0, 220, 0),
    },
    {
        highlight_pos = vmath.vector3(-287, 187, 0),      -- free cells (193-480, 457-270)
        highlight_size = vmath.vector3(300, 90, 0),
        text = "Free cells — temporary storage.\nYou can place any single card here. Max 3 cards.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        highlight_pos = vmath.vector3(293, 187, 0),       -- base slots (773-480, 457-270)
        highlight_size = vmath.vector3(300, 90, 0),
        text = "Foundation slots — your goal!\nStack cards of the SAME suit from 2 to 10.\nFill all three to win.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        highlight_pos = vmath.vector3(-60, 193, 0),       -- dragon buttons (420-480, 463-270)
        highlight_size = vmath.vector3(80, 140, 0),
        text = "Dragon buttons — collect dragons!\nWhen all 4 dragons of one color are face-up,\npress the button to sweep them into a free cell.",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        highlight_pos = vmath.vector3(61, 187, 0),        -- flower slot (541-480, 457-270)
        highlight_size = vmath.vector3(100, 90, 0),
        text = "The Flower card goes here automatically.\nIt's a free bonus — no action needed!",
        text_bg_pos = vmath.vector3(0, -220, 0),
    },
    {
        highlight_pos = vmath.vector3(0, 0, 0),
        highlight_size = vmath.vector3(920, 400, 0),
        text = "Clear the tableau by sorting all cards\ninto the foundation — and you win!\nGood luck!",
        text_bg_pos = vmath.vector3(0, -220, 0),
        next_text = "GOT IT!",
    },
}
```

## Definition of Done

1. Кнопка TUTORIAL открывает пошаговый туториал
2. 7 шагов с затемнением, подсветкой зоны и текстом
3. Кнопка NEXT переключает шаги, на последнем — GOT IT! закрывает
4. Во время туториала input для игры заблокирован
5. Индикатор шага "1/7" ... "7/7" виден
6. Текст подсказок на английском, читаемый на тёмном фоне

## Критерии приёмки

- [ ] Нажатие TUTORIAL показывает tutorial_overlay
- [ ] Шаг 1: подсвечен весь экран, текст приветствия
- [ ] Шаг 2: подсвечена зона tableau, текст про правила стекинга
- [ ] Шаг 3: подсвечены free cells, текст про временное хранение
- [ ] Шаг 4: подсвечены base slots, текст про цель игры
- [ ] Шаг 5: подсвечены кнопки драконов, текст про сбор драконов
- [ ] Шаг 6: подсвечен flower slot, текст про цветок
- [ ] Шаг 7: весь экран, текст "Good luck!", кнопка "GOT IT!"
- [ ] Кнопка NEXT работает, индикатор шага обновляется
- [ ] GOT IT! закрывает туториал
- [ ] Input заблокирован во время туториала
- [ ] tutorial_overlay скрыт по умолчанию (enabled: false)
- [ ] Нет ошибок в консоли

## Ветка

Создать ветку `feature/tutorial` от master.

## Чего НЕ делать

- Не добавлять анимации переходов между шагами (будет в Фазе 4)
- Не делать автозапуск при первом входе (отдельная задача с localStorage)
- Не менять game_manager.script или main.script
- Не менять game objects или collection
- Не создавать новые текстуры/атласы
- Не трогать ноды start_screen, victory_overlay или кнопки Restart/Tutorial (кроме обработчика tutorial_button в скрипте)
