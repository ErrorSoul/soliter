# Интерактивный туториал v2 (Фаза 3)

## Контекст

Defold-проект, Shenzhen Solitaire. Разрешение 960x540, HTML5.

Интерактивный мини-уровень: фиксированная безвариативная раздача, юзер двигает карты, подсказки направляют, в конце — мини-победа.

## Архитектура

### Cross-collection коммуникация

**Проблема:** Игровая логика (cursor, main.script) находится в proxied коллекции "soliter", а UI (gui/ui.gui) — в bootstrap коллекции. `msg.post("/main#ui", ...)` не работает из proxied коллекции.

**Решение:** Polling через shared Lua module `tutorial_state.lua`. Defold использует единый Lua state для всех скриптов. Cursor ставит флаги, UI проверяет их в `update()`:
- `tutorial_state.ui_dirty` → обновление хинтов
- `tutorial_state.show_victory` → показ экрана победы

### Файлы

| Файл | Назначение |
|---|---|
| `main/Scripts/tutorial_state.lua` | Shared state: step, flags, expected moves, i18n |
| `main/Scripts/i18n.lua` | Локализация (en/ru/tr) |
| `main/Scripts/main.script` | Фикс. раздача, победа через shared flags |
| `main/Scripts/cursor.script` | Advance step при правильном ходе (без блокировки) |
| `main/Scripts/tableau_script.script` | Блокировка авто-отправки 2-ек в туториале |
| `gui/ui.gui_script` | Хинты, SKIP, polling shared state |
| `gui/ui.gui` | Вёрстка hint bar, SKIP кнопка, шрифты |

## Раскладка — БЕЗВАРИАТИВНАЯ

10 карт, 5 стеков. При каждом шаге видна ОДНА возможная комбинация.

```
S1: d_red, 4_blue, 7_green, 3_red, 2_red (top) — 5 карт, глубокий стек
S2: 5_green (один) — цель для стекинга
S3: d_red (один)
S4: d_red (один)
S5: flower, d_red (top)
```

### Проверка вариативности по шагам

| Шаг | Видимые карты | Ход | Почему единственный |
|---|---|---|---|
| 0 | 2_red, 5_green, d_red×3 | 2_red → foundation | 2→5 не консекутивно, нет других ходов |
| 1 | 3_red, 5_green, d_red×3 | 3_red → foundation | 3→5 не консекутивно |
| 2 | 7_green, 5_green, d_red×3 | 7_green → free cell | 7→found нет 6g, 7→5g same color |
| 3 | 4_blue, 5_green, d_red×3 | 4_blue → 5_green | 4→found нет 3b, стекинг единственный |
| 4 | d_red×4 видны | Dragon button | Все 4 красных дракона на виду |

После dragon button: flower авто-улетает → Victory!

### Подход к валидации

Ходы НЕ блокируются. Все валидные ходы в солитере разрешены. Шаг продвигается ТОЛЬКО при совпадении с ожидаемым ходом. Хинт остаётся пока юзер не сделает правильный ход.

```lua
M.EXPECTED_MOVES = {
    [0] = {card_id = "2_red", target = "base"},
    [1] = {card_id = "3_red", target = "base"},
    [2] = {card_id = "7_green", target = "free"},
    [3] = {card_id = "4_blue", target = "tableau_card", target_card_id = "5_green"},
    -- step 4 = dragon button, validated by button activation
}
```

## Подсказки (i18n)

Хинты через `i18n.t("tutorial_hint_N")`, счётчик шагов "1/5" ... "5/5".

Шрифт hint bar и step counter: "default" (Defold built-in) — единственный шрифт с нормальными цифрами. CocomatLight (main_font, second) рендерит цифры как серебряные иконки.

**TODO:** Добавить TTF с поддержкой кириллицы и турецких символов (Noto Sans или аналог) для полноценной локализации.

## UI во время туториала

- RESTART и TUTORIAL кнопки скрыты
- SKIP кнопка (красная, слева от hint bar) — выход из туториала
- Overlay полностью прозрачный (alpha=0) — карты видны без затемнения
- Victory после туториала: "Well done!" / "PLAY NOW"

## Критерии приёмки

- [x] Безвариативная раскладка (один очевидный ход на каждом шаге)
- [x] 5 шагов: foundation → foundation → free cell → стекинг → dragon button
- [x] Ходы не блокируются, шаг продвигается только при правильном ходе
- [x] Cross-collection коммуникация через shared state polling
- [x] i18n модуль (en/ru/tr)
- [x] SKIP выходит из туториала
- [x] Victory туториала → "Well done! PLAY NOW"
- [x] Overlay не затемняет поле
- [ ] Полноценный шрифт с кириллицей/турецким
- [ ] Тестирование обычной игры не сломано

## Ветка

`feature/tutorial-v2` (от master)
