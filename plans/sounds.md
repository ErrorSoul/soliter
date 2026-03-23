# Звуки — План реализации

## Контекст

Defold поддерживает `.ogg` (рекомендован) и `.wav`. Звуки подключаются через Sound-компонент на game object. Для глобальных звуков — один GO со всеми звуковыми компонентами.

---

## Звуковые эффекты

| ID | Событие | Характер звука | Длительность |
|----|---------|---------------|-------------|
| `card_pick` | Подхват карты (start_drag) | Мягкий "тук" / шелест | 0.1-0.2s |
| `card_drop` | Успешное размещение (drop_success) | Приглушённый "шлёп" | 0.1-0.3s |
| `card_error` | Невалидный ход (drop_failed) | Короткий "бзз" / глухой стук | 0.2-0.3s |
| `card_deal` | Раздача карт | Быстрый "вжух" / свист | 0.3-0.5s |
| `dragon_collect` | Сбор 4 драконов | "Свуш" + лёгкий звон | 0.5-0.8s |
| `button_click` | Клик UI-кнопки | Мягкий "клик" | 0.1s |
| `victory` | Победа | Короткий фанфар / джингл | 1-2s |
| `card_auto` | Авто-перемещение (flower/base) | Мягкий "свуш" | 0.2-0.3s |

---

## Задача 1: Создать звуковой менеджер

**Создать GO:** `main/Game Objects/sound_manager.go`

Добавить Sound-компоненты для каждого звука:
```
embedded_components {
  id: "card_pick"
  type: "sound"
  data: "sound: \"/assets/sounds/card_pick.ogg\"\nlooping: 0\ngroup: \"sfx\"\ngain: 0.8\n"
}
embedded_components {
  id: "card_drop"
  type: "sound"
  data: "sound: \"/assets/sounds/card_drop.ogg\"\nlooping: 0\ngroup: \"sfx\"\ngain: 0.8\n"
}
-- ... аналогично для остальных
```

**Добавить в `soliter.collection`:**
```
instances {
  id: "sound_manager"
  prototype: "/main/Game Objects/sound_manager.go"
  position { x: 0.0 y: 0.0 z: 0.0 }
}
```

---

## Задача 2: Lua-модуль для воспроизведения

**Создать:** `main/Scripts/sfx.lua`

```lua
local M = {}

-- URL sound_manager — задаётся при инициализации
M.url_prefix = "sound_manager"

function M.play(sound_id, gain)
    local url = msg.url(nil, M.url_prefix, sound_id)
    sound.play(url, { gain = gain or 1.0 })
end

-- Удобные обёртки
function M.card_pick()   M.play("card_pick", 0.6) end
function M.card_drop()   M.play("card_drop", 0.8) end
function M.card_error()  M.play("card_error", 0.5) end
function M.card_deal()   M.play("card_deal", 0.4) end
function M.dragon()      M.play("dragon_collect", 0.8) end
function M.button()      M.play("button_click", 0.5) end
function M.victory()     M.play("victory", 1.0) end
function M.card_auto()   M.play("card_auto", 0.5) end

return M
```

---

## Задача 3: Интеграция в скрипты

### card.script
```lua
local sfx = require("main.Scripts.sfx")

-- В "start_drag":
sfx.card_pick()

-- В "drop_success":
sfx.card_drop()

-- В "drop_failed":
sfx.card_error()
```

### main.script
```lua
local sfx = require("main.Scripts.sfx")

-- В deal_cards / deal_tutorial_cards, перед циклом раздачи:
sfx.card_deal()
```

### dragon_button.script
```lua
local sfx = require("main.Scripts.sfx")

-- В "get_dragon_cards":
sfx.dragon()
```

### ui.gui_script
```lua
-- GUI не может напрямую вызывать sound.play на GO из другой коллекции.
-- Варианты:
-- 1. Добавить Sound-компоненты прямо в ui.gui (GUI поддерживает встроенные звуки)
-- 2. Использовать shared module с флагами (как tutorial_state)

-- Вариант 1 (проще): в ui.gui добавить Sound-ноды
-- В gui_script:
sound.play("ui_sounds#button_click")
sound.play("ui_sounds#victory")
```

### Авто-перемещение (flower, base)
```lua
-- В tableau_script.script, в last_card_to_slot():
local sfx = require("main.Scripts.sfx")
sfx.card_auto()
```

---

## Задача 4: Подготовить звуковые файлы

**Создать директорию:** `assets/sounds/`

**Нужны файлы (.ogg):**
- `card_pick.ogg`
- `card_drop.ogg`
- `card_error.ogg`
- `card_deal.ogg`
- `dragon_collect.ogg`
- `button_click.ogg`
- `victory.ogg`
- `card_auto.ogg`

**Где взять:**
- Бесплатные: freesound.org, kenney.nl/assets (CC0)
- Генерация: sfxr/jsfxr (https://sfxr.me/) — можно сгенерировать ретро-звуки
- Для карточных звуков: записать реальный звук карт или найти "card flip/shuffle" на freesound

**Требования:**
- Формат: OGG Vorbis (рекомендован для Defold HTML5)
- Моно (не стерео) — экономия размера
- Sample rate: 44100 или 22050 Hz
- Размер: каждый файл < 50KB (короткие эффекты)

---

## Задача 5: Настройка групп и громкости

**В `game.project`:**
```ini
[sound]
gain = 1.0
```

**Группы звуков:**
- `sfx` — все игровые звуки (карты, драконы)
- `music` — фоновая музыка (если добавим)

Группы позволяют отключать звуки отдельно:
```lua
sound.set_group_gain("sfx", 0)   -- mute SFX
sound.set_group_gain("sfx", 1)   -- unmute
```

Можно добавить кнопку mute в UI (отдельная задача).

---

## Порядок

1. **Задача 4** (файлы) — найти/сгенерировать звуки
2. **Задача 1** (sound_manager.go) — создать GO с компонентами
3. **Задача 2** (sfx.lua) — модуль воспроизведения
4. **Задача 3** (интеграция) — добавить вызовы в скрипты
5. **Задача 5** (группы) — настройка громкости

## Зависимости

- Звуковые файлы нужны до задачи 1 (без файлов Sound-компонент не создать)
- sfx.lua зависит от sound_manager.go (нужен URL)
- GUI-звуки (button_click, victory) — отдельно от game sounds из-за cross-collection ограничения

## Что НЕ делаем

- Фоновая музыка — отдельная задача, нужен лицензированный трек
- Кнопка mute — отдельная UI-задача
- Пространственный звук (3D audio) — не нужен для 2D карточной игры
