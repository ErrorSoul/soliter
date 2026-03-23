# Фаза 5: Респонсив (HTML5) — План реализации

## Принцип

В Defold респонсив ≠ перерасчёт позиций. Игровое поле 960×540 масштабируется целиком через проекцию. GUI-элементы привязываются к краям экрана через anchors.

**Три слоя:**
1. **Render script** — проекция, масштаб, letterbox → game objects (карты, слоты)
2. **GUI** — anchors, adjust mode → UI-элементы (кнопки, оверлеи, текст)
3. **HTML5** — canvas sizing, iframe → браузер / Яндекс Игры

---

## Задача 1: Проверить render script

**Файл:** `render.script`

**Что проверить:**
- `fixed_fit_projection` уже подключён (`main.script:38`)
- Нужно убедиться что letterbox корректно работает при разных пропорциях
- Проверить что `near`/`far` (-1, 1) достаточно для z-index системы (макс z = 0.3 при drag — ок)

**Что может понадобиться:**
- Заменить чёрный letterbox на цвет стола (тёмно-зелёный) — это `render.clear()` с нужным цветом
- Найти в render.script вызов `render.clear()` и заменить цвет на `{0.1, 0.2, 0.1, 1}` (или близкий к фону стола)

**Код:**
```lua
-- В render.script, в функции update():
render.clear({[render.BUFFER_COLOR_BIT] = vmath.vector4(0.1, 0.2, 0.1, 1),
              [render.BUFFER_DEPTH_BIT] = 1})
```

---

## Задача 2: GUI anchors и adjust mode

**Файл:** `gui/ui.gui`

Это текстовый protobuf-файл. Для каждой GUI-ноды нужно проверить/настроить:

### Стартовый экран (`start_screen`)
- `adjust_mode: ADJUST_FIT` — масштабировать сохраняя пропорции
- Дочерние элементы: центр экрана, без привязки к краям — ОК как есть

### Кнопки Restart / Tutorial
- Сейчас: абсолютная позиция, могут выйти за экран при нестандартных пропорциях
- Нужно: `x_anchor: XANCHOR_RIGHT`, `y_anchor: YANCHOR_TOP` — привязка к правому верхнему углу
- `adjust_mode: ADJUST_FIT`

### Victory overlay
- Должен занимать весь экран: `adjust_mode: ADJUST_STRETCH` для фона-затемнения
- Дочерние элементы (текст, кнопки): `adjust_mode: ADJUST_FIT`, центр

### Tutorial overlay
- Аналогично victory overlay

**Как редактировать ui.gui:**

GUI файл в Defold — это текстовый protobuf. Структура ноды:
```
nodes {
  type: TYPE_BOX
  id: "restart_button"
  position { x: 900.0 y: 520.0 }
  x_anchor: XANCHOR_NONE      ← заменить на XANCHOR_RIGHT
  y_anchor: YANCHOR_NONE      ← заменить на YANCHOR_TOP
  adjust_mode: ADJUST_FIT
  ...
}
```

**Важно:** при использовании anchors, `position` задаётся относительно привязанного края. Если `XANCHOR_RIGHT`, то `x: -60` значит "60px от правого края".

Нужно пересчитать позиции кнопок после смены anchor:
- Restart: было `x: 900, y: 520` → `x: -60, y: -20` (с right/top anchor)
- Tutorial: аналогично

---

## Задача 3: HTML5 canvas sizing

**Файл:** нужно создать или отредактировать HTML-шаблон

В `game.project` найти секцию `[html5]` и настроить:
```ini
[html5]
htmlfile = /builtins/manifests/web/engine_template.html
custom_css =
```

Или создать кастомный HTML-шаблон с CSS:
```css
#canvas {
    width: 100vw;
    height: 100vh;
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
}
body {
    margin: 0;
    background: #1a331a; /* цвет стола для областей за canvas */
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100vh;
    overflow: hidden;
}
```

**Для Яндекс Игр:**
- Игра загружается в iframe
- Canvas должен заполнять 100% iframe
- `object-fit: contain` сохраняет пропорции

---

## Задача 4: Тестирование

Проверить на разных пропорциях:
- 16:9 (стандарт) — должно быть без letterbox
- 4:3 (iPad) — вертикальный letterbox
- 21:9 (ультраширокий) — горизонтальный letterbox
- Мобильный portrait — большой letterbox сверху/снизу (игра landscape)

**Как тестировать:**
- В Defold Editor: Debug → Start Engine → изменить размер окна
- В браузере: открыть HTML5 билд → DevTools → toggle device toolbar

**Чек-лист:**
- [ ] Карты не обрезаются
- [ ] Кнопки видны при любом размере
- [ ] Victory overlay покрывает весь экран
- [ ] Touch/click попадает в правильные карты (screen_to_world корректен)
- [ ] Letterbox цвета стола, не чёрный

---

## Порядок

1. Задача 1 (render script) — быстрая, одна строка
2. Задача 2 (GUI anchors) — основная работа
3. Задача 3 (HTML5 canvas) — после сборки билда
4. Задача 4 (тесты) — ручное тестирование

## Что НЕ делаем

- Динамический перерасчёт позиций карт — не нужен, проекция справляется
- Portrait mode — игра только landscape
- Адаптивный размер карт — при 960×540 базе карты читаемы на любом экране
