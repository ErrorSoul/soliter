# Стартовый экран (Start Screen)

## Контекст

Defold-проект, Shenzhen Solitaire. Разрешение 960x540, HTML5. Сейчас при запуске сразу грузится игровой уровень через `game_manager.script` → `show(self, "#level_proxy")`. Нужен стартовый экран перед игрой.

## Что сделать

Добавить стартовый экран, который показывается при запуске игры. По нажатию "PLAY" — загружается игровой уровень. Экран должен переиспользовать существующий фон стола.

## Архитектура

**Подход:** Добавить ноды стартового экрана в существующий `gui/ui.gui` + управление в `gui/ui.gui_script`. НЕ создавать отдельную collection — UI уже живёт поверх всего в `main.collection`.

**Поток:**
1. `game_manager.script` → при `init()` НЕ грузит уровень сразу, а ждёт сообщение `start_game`
2. `ui.gui_script` → при `init()` показывает стартовый экран (title + кнопка PLAY)
3. Игрок нажимает PLAY → `ui.gui_script` прячет стартовый экран, шлёт `start_game` в game_manager
4. `game_manager` получает `start_game` → грузит уровень как раньше

## Файлы для изменения

| Файл | Что менять |
|---|---|
| `gui/ui.gui` | Добавить ноды: `start_screen` (контейнер), `title_text`, `play_button`, `play_text` |
| `gui/ui.gui_script` | Добавить логику показа/скрытия start screen, обработку нажатия PLAY |
| `main/Scripts/game_manager.script` | Убрать `show(self, "#level_proxy")` из `init()`, добавить обработку `start_game` |

## Definition of Done

1. При запуске игры виден стартовый экран с названием "Shenzhen Solitaire" и кнопкой "PLAY"
2. Уровень НЕ загружается до нажатия PLAY
3. По нажатию PLAY стартовый экран исчезает, уровень загружается
4. Кнопки Restart/Tutorial НЕ видны на стартовом экране (только во время игры)
5. После победы и нажатия Restart — показывается игра, а НЕ стартовый экран
6. Стартовый экран центрирован на экране 960x540

## Критерии приёмки

- [x] Стартовый экран показывается при запуске
- [x] Текст "Shenzhen Solitaire" отображается крупным шрифтом `main_font`, центрирован
- [x] Кнопка PLAY — box-нода с текстом, центрирована под заголовком
- [x] Нажатие PLAY скрывает экран и запускает игру
- [x] Кнопки Restart/Tutorial скрыты пока не начата игра (`gui.set_enabled(node, false)` в init)
- [x] Restart из victory popup НЕ возвращает на стартовый экран (перезагружает уровень)
- [ ] Нет ошибок в консоли (нужно протестировать)

## Детали реализации

### Ноды в `ui.gui` (добавить):

```
start_screen (TYPE_BOX) — контейнер, position: 480, 270, size: 960x540, цвет: тёмно-зелёный (0.15, 0.3, 0.15), layer: "layer"
  └─ title_text (TYPE_TEXT) — "Shenzhen Solitaire", font: main_font, position: 0, 80 (relative), чёрный текст
  └─ play_button (TYPE_BOX) — position: 0, -40 (relative), size: 200x80, белый фон
     └─ play_text (TYPE_TEXT) — "PLAY", font: main_font, чёрный
```

### Изменения в `ui.gui_script`:

```lua
function init(self)
    msg.post(".", "acquire_input_focus")
    -- Скрыть игровые кнопки
    gui.set_enabled(gui.get_node("restart_button"), false)
    gui.set_enabled(gui.get_node("tutorial_button"), false)
    gui.set_enabled(gui.get_node("victory_restart1"), false)
    -- Стартовый экран включён по умолчанию (enabled: true в .gui)
    self.game_started = false
end

-- В on_input добавить:
if not self.game_started then
    local play_button = gui.get_node("play_button")
    if gui.pick_node(play_button, action.x, action.y) then
        gui.set_enabled(gui.get_node("start_screen"), false)
        gui.set_enabled(gui.get_node("restart_button"), true)
        gui.set_enabled(gui.get_node("tutorial_button"), true)
        gui.set_enabled(gui.get_node("victory_restart1"), true)
        msg.post("/main#game_manager", "start_game")
        self.game_started = true
    end
    return true  -- блокируем input для игры
end
```

### Изменения в `game_manager.script`:

```lua
function init(self)
    msg.post(".", "acquire_input_focus")
    self.current_proxy = nil
    self.current_level = "soliter"
    -- НЕ грузим уровень, ждём start_game
end

-- Добавить в on_message:
if message_id == hash("start_game") then
    show(self, "#level_proxy")
end
```

## Ветка

Создать ветку `feature/start-screen` от master.

## Чего НЕ делать

- Не создавать новые .collection или .collectionproxy файлы
- Не менять логику уровней или карт
- Не добавлять анимации (будет отдельной задачей)
- Не трогать файлы вне перечисленных трёх
