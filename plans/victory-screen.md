# Victory Screen — Переделка экрана победы (Фаза 2)

## Контекст

Defold-проект, Shenzhen Solitaire. Разрешение 960x540, HTML5.

Сейчас victory popup — зелёный квадрат 300x400 с текстом "You win!!!" и кнопкой RESTART. Некрасивый, не центрирован, без затемнения фона. Нужно переделать в полноценный victory screen.

**ВАЖНО:** Есть баг — победа не определяется из-за опечатки в `main/Scripts/main.script:342`: `self.currenState` вместо `self.currentState`. Также отсутствует `msg.post` для отправки `show_victory` в UI. Это нужно починить в рамках этой задачи.

## Что сделать

1. Починить определение победы в `main.script`
2. Переделать victory popup в полноценный victory screen с затемнением, центрированием и кнопками
3. Добавить кнопку "Menu" (возврат на стартовый экран)

## Архитектура

**Подход:** Переделать существующие ноды в `gui/ui.gui` + логику в `gui/ui.gui_script`. Починить отправку сообщения о победе в `main.script`.

**Поток:**
1. `main.script` → `check_win()` возвращает true → отправляет `show_victory` в UI: `msg.post("/main#ui", "show_victory")`
2. `ui.gui_script` → получает `show_victory` → показывает затемнение + victory popup
3. Игрок нажимает "Play Again" → прячет popup, шлёт `restart_level`
4. Игрок нажимает "Menu" → прячет popup, показывает стартовый экран, шлёт `unload_level` (или restart_level + показ start_screen)

## Файлы для изменения

| Файл | Что менять |
|---|---|
| `main/Scripts/main.script` | Починить опечатку `currenState` → `currentState` (строка 342). Добавить `msg.post("/main#ui", "show_victory")` после определения победы (строка 345). |
| `gui/ui.gui` | Переделать ноды victory popup: добавить `victory_overlay` (затемнение), переделать `victory_popup` (центрировать, увеличить), добавить кнопку `victory_menu_button` |
| `gui/ui.gui_script` | Обновить логику: показ/скрытие overlay, обработка кнопки Menu (возврат на стартовый экран) |

## Текущая структура UI (для справки)

Адресация в `main.collection`:
- Game object `main` содержит: `game_manager` (script), `level_proxy`, `level_proxy1`, `ui` (gui)
- UI адрес для msg.post: `/main#ui`
- Game manager адрес: `/main#game_manager`

Текущие ноды victory popup в `ui.gui`:
- `victory_popup` — TYPE_BOX, 300x400, зелёный (0.302, 0.502, 0.302), position: 483, 253, **enabled: false**
  - `text1` — TYPE_TEXT, "You win !!!", font: main_font, чёрный
  - `victory_restart` — TYPE_BOX, кнопка RESTART внутри popup
    - `text` — TYPE_TEXT, "RESTART", font: second
  - `victory_close_button` — TYPE_BOX, маленькая кнопка закрытия

Есть также отдельная нода `victory_restart1` (position: 150, 344) — это кнопка RESTART **вне** popup, видимая во время игры.

## Детали реализации

### Баг-фикс в `main.script`:

```lua
-- Строка 342: БЫЛО
if self.currenState == self.states.PLAYING then
-- СТАЛО
if self.currentState == self.states.PLAYING then

-- Строка 344-345: БЫЛО
   self.state = self.states.WIN
   print("You win!")
-- СТАЛО
   self.currentState = self.states.WIN
   print("You win!")
   msg.post("/main#ui", "show_victory")
```

Обрати внимание: `self.state` тоже ошибка — должно быть `self.currentState`.

### Ноды в `ui.gui` (переделать/добавить):

```
victory_overlay (TYPE_BOX) — полноэкранный затемняющий слой
  position: 480, 270
  size: 960x540
  color: 0, 0, 0 (чёрный)
  alpha: 0.6
  layer: "buttons"
  enabled: false

victory_popup (TYPE_BOX) — ПЕРЕДЕЛАТЬ существующую ноду:
  position: 480, 270 (центр экрана, сейчас 483, 253)
  size: 400x300 (увеличить)
  scale: 1, 1 (убрать кривой scale 1.224)
  color: 0.2, 0.35, 0.2 (тёмно-зелёный)
  parent: victory_overlay
  size_mode: SIZE_MODE_MANUAL (убрать AUTO)
  enabled: по умолчанию через parent

  └─ text1 (TYPE_TEXT) — ОСТАВИТЬ, поменять текст на "Victory!" или "You Win!"
     position: 0, 80
     font: main_font

  └─ victory_restart (TYPE_BOX) — ПЕРЕДЕЛАТЬ в "Play Again"
     position: 0, -20
     size: 200x60
     scale: 1, 1 (убрать кривой scale)
     size_mode: SIZE_MODE_MANUAL
     └─ text → изменить текст на "PLAY AGAIN"

  └─ victory_menu_button (TYPE_BOX) — НОВАЯ кнопка "Menu"
     position: 0, -90
     size: 200x60
     └─ victory_menu_text (TYPE_TEXT) — "MENU", font: main_font

  └─ victory_close_button — УДАЛИТЬ (не нужна, есть Play Again и Menu)
```

### Изменения в `ui.gui_script`:

```lua
-- on_message: показ victory
function on_message(self, message_id, message)
    if message_id == hash("show_victory") then
        gui.set_enabled(gui.get_node("victory_overlay"), true)
    end
end

-- on_input: обработка кнопок victory
-- Play Again:
if gui.is_enabled(gui.get_node("victory_overlay")) then
    local restart = gui.get_node("victory_restart")
    local menu = gui.get_node("victory_menu_button")

    if gui.pick_node(restart, action.x, action.y) then
        gui.set_enabled(gui.get_node("victory_overlay"), false)
        msg.post("/main#game_manager", "restart_level")
        return true
    end

    if gui.pick_node(menu, action.x, action.y) then
        gui.set_enabled(gui.get_node("victory_overlay"), false)
        -- Показать стартовый экран
        gui.set_enabled(gui.get_node("start_screen"), true)
        gui.set_enabled(gui.get_node("restart_button"), false)
        gui.set_enabled(gui.get_node("tutorial_button"), false)
        gui.set_enabled(gui.get_node("victory_restart1"), false)
        self.game_started = false
        -- Выгрузить текущий уровень
        msg.post("/main#game_manager", "unload_level")
        return true
    end

    return true  -- блокируем input для игры под overlay
end
```

### Изменения в `game_manager.script`:

```lua
-- Добавить обработку unload_level:
elseif message_id == hash("unload_level") then
    if self.current_proxy then
        msg.post(self.current_proxy, "unload")
        self.current_proxy = nil
    end
```

## Definition of Done

1. При победе показывается затемнение фона + центрированный popup
2. Popup содержит текст "Victory!" / "You Win!", кнопки "Play Again" и "Menu"
3. "Play Again" перезапускает уровень (как текущий Restart)
4. "Menu" возвращает на стартовый экран (скрывает popup, показывает start_screen, выгружает уровень)
5. Победа реально определяется (починена опечатка `currenState`)
6. `show_victory` отправляется из `main.script` в UI

## Критерии приёмки

- [ ] Опечатка `currenState` исправлена на `currentState` в `main.script:342`
- [ ] `self.state` исправлен на `self.currentState` в `main.script:344`
- [ ] `msg.post("/main#ui", "show_victory")` отправляется при победе
- [ ] Victory overlay затемняет экран (чёрный, alpha 0.6)
- [ ] Victory popup центрирован (480, 270), размер увеличен
- [ ] Кнопка "Play Again" перезапускает уровень
- [ ] Кнопка "Menu" возвращает на стартовый экран
- [ ] Input блокируется, пока виден victory overlay
- [ ] Кнопка victory_close_button удалена
- [ ] Нет ошибок в консоли

## Ветка

`feature/victory-screen` (уже создана от master)

## Чего НЕ делать

- Не добавлять анимации (конфетти, bounce и т.д. — будет в Фазе 4)
- Не добавлять статистику (время, ходы — отдельная задача)
- Не менять логику карт, drag&drop или стеков
- Не трогать `check_win()` — только исправить вызов и отправку сообщения
- Не создавать новые .collection или .collectionproxy
