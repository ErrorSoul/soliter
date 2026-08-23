# INDEX.md — навигационная карта (символ → файл)

Цель: прыгать в нужный файл/символ без чтения всего проекта. Номеров строк нет —
точную строку добирать `grep`'ом по имени символа. Архитектуру/z-index/респонсив см.
[architecture.md](./architecture.md). Этот файл — только «что где лежит».

## Раскладка

- `main/` — игровой рантайм (логика, слоты, ввод). `gui/` — UI. `solver/` — pure-Lua солвер + тесты.
- Точка входа: `main/main.collection` → `game_manager.script` → грузит level proxy (`soliter.collection`).
- `soliter.collection` / `soliter1.collection` — идентичны; содержат слоты + `card_table` (в нём `main.script`, фабрики `card_factory`, `cursor_factory`). **Это единственный источник координат слотов** — скрипты читают их в рантайме через `go.get_position(slot_id)`, хардкода нет. Сетка (G6, по дизайну): центры колонок 65, 169, 273, 377, 481, 585, 689, 793; служебный ряд y=457 — свободные ячейки 1–3, цветок 4, кнопки драконов 5, foundation red/green/blue 6–8; правее x=868 идёт GUI-рельс с кнопками, туда поле заходить не должно (пин — `solver/tests/test_layout.lua`).
- **Cross-collection через polling** (proxy-коллекции не шлют msg наружу): `sfx.pending`, `tutorial_state.*_dirty`, `tutorial_state.show_victory` — опрашиваются в update'ах `main.script` / `cursor.script` / `ui.gui_script`.

## Игровой рантайм — файл → роль → ключевые символы

| Файл (`main/Scripts/` если не указано) | Роль | Ключевые символы |
|---|---|---|
| `main.script` | Ядро состояния: колода, раздача, авто-финиш, победа, солвер-дебаг | `create_deck` `shuffle_deck` `deal_cards` `deal_tutorial_cards` `deal_dragon_test` `deal_auto_finish_test` `can_auto_finish` `find_next_auto_card` `auto_finish_step` `start_auto_finish` `live_cells` `dragons_left` `board_cleared` `dragon_relocation` `auto_collect_give_up` `declare_victory` `build_solver_snapshot` `snapshot_and_go_map` `debug_solve` `debug_replay` · поля: `foundation_top` `suit_to_base` `base_cards_count` |
| `cursor.script` | Хаб ввода: touch, hit-test, валидация дропа, drag-состояние, tutorial-хайлайты | hit-test: `check_tableau_slots` `check_last_cards` `check_free_slots` `check_flower_slot` `check_base_slots` `check_free_tableau_slots` `check_dragon_buttons` `screen_to_world` · tutorial: `find_card_by_data_id` `clear_tutorial_highlights` `apply_tutorial_highlights` `fly_card_arc` |
| `card.script` | Карта: drag, анимации, тинты | `set_card` `is_correct_card` |
| `base_slot.script` | Foundation (2→10, одна масть) | `check_correct_cards` |
| `free_cell.script` | Free cell (1 карта / blocked-пайл драконов) | `check_dragon` `send_to_dragon_buttons` `change_button_counter` `mirror_to_main` (→ `free_cell_changed`, C4) · заблокированная ячейка ничего не возвращает счётчику (C10); уведомление cursor уходит и на занятую ячейку (C11) |
| `tableau_script.script` | Колонка tableau: видимый стек, авто-отправка верхней карты | `can_stack_cards` `update_visible_cards` `last_card_to_slot` `contains` |
| `flower_slot.script` | Слот цветка (только `'f'`, авто-победа) | — (`check_slot`/`occupy_slot` → `flower_collected` в main, C5) |
| `dragon_button.script` | Сбор драконов (актив при 4 + free slot) | `check_state` `free_slot_any` |
| `game_manager.script` | Загрузка/перезагрузка уровня через collectionproxy + жизненный цикл SDK Я.Игр (D1) | (msg: `start_game` `restart_level` `unload_level` `gameplay_over`) · `update` опрашивает `yandex.state()` до ответа SDK, потом `loading_ready` + `language_ready` → `/main#ui` |
| `sfx.lua` | Звук: прямой `sound.play` или очередь | `M.pending` `M.play` `M.queue` `M.clear` + `card_pick/card_drop/card_error/card_deal/dragon_collect/button_click/victory/flower_auto/auto_finish` |
| `debug_flags.lua` | Вариант сборки: dev-клавиши S/R/Space | `M.enabled` (= `sys.get_engine_info().is_debug`) |
| `i18n.lua` | Локализация en/ru/tr | `M.lang` `M.strings` `M.t` `M.set_lang` `M.detect` (**SDK Я.Игр** → ?lang= → язык системы → en) |
| `yandex.lua` | Мост к SDK Я.Игр (D1): тонкая Lua-обёртка над `html5.run` | `M.available` `M.state` `M.lang` `M.loading_ready` `M.gameplay` `M.trace` · вся асинхронность и парность start/stop — в JS, блок `ya-bridge` в `html5/engine_template.html` |
| `tutorial_state.lua` | Состояние туториала (polling-флаги) | `M.is_tutorial` `M.step` `M.ui_dirty` `M.show_victory` `M.highlight_dirty` `M.block_play_input` `M.EXPECTED_MOVES` `M.HIGHLIGHTS` `M.check_move` `M.advance` `M.reset` `M.request_victory` `M.is_play_input_blocked` |
| `gui/ui.gui_script` | Главный UI: старт-экран, victory overlay, tutorial-хинты, язык | `restart_level` `update_tutorial_hint` `apply_language` `STATIC_LABELS` |

### Game Objects → скрипт
`card.go`→card · `cursor.go`→cursor · `base_slot.go`→base_slot · `free_slot.go`→free_cell · `tableau_slot.go`→tableau_script · `flower_slot.go`→flower_slot · `dragon_button.go`→dragon_button · `background.go`/`sound_manager.go`→спрайт/звук без скрипта.

## Message-passing (sender → id → receiver), сжато

- **Инициализация:** `main` → `set_cards/set_free_slots/set_base_slots/set_flower_slot/set_tableau_slots/set_dragon_buttons` → cursor; `main` → `update_stack` → tableau; `main` → `set_button` → dragon_button.
- **Ввод/драг:** cursor → `start_drag/drag_update/drop_success/drop_failed/can_move_card` → card; card → `valid_card/invalid_card` → cursor.
- **Валидация дропа:** cursor → `set_cursor/check_slot/can_pick_card` → слоты; слот → `slot_valid/slot_invalid` → cursor; free_slot → `slot_with_card/update_free_slot` → cursor; base_slot → `base_slot_full` → cursor.
- **Дроп-результат:** card → `occupy_slot` → целевой слот; card → `remove_card` → слот-владелец.
- **Авто-полёт (tableau детектит верх):** tableau → `send_to_flower_slot/send_to_base_slot` → cursor; tableau → `send_counter_to_button` → dragon_button.
- **Дельта-зеркало tableau→main (auto-finish/snapshot):** tableau → `tableau_card_added/tableau_card_removed` → main (`main.tableau_stacks` всегда свежее; оценка `check_auto_finish` отложена на 2 кадра в `update`).
- **Драконы:** free_slot → `change_free_slots_button_counter` → dragon_button; cursor → `set_button_state/get_dragon_cards` → dragon_button; dragon_button → `dragons_collected` (через 1.5с) → main.
- **В main:** base_slot → `card_to_base` → main; cursor → `check_auto_finish/send_auto_finish_check` → main; free_cell → `free_cell_changed` → main (C4); flower_slot → `flower_collected` → main (C5); main → `auto_collect_dragons` → cursor (G2: дожать кнопки сбора за игрока); cursor → `auto_collect_none` → main (не горит ни одна кнопка) → main → `auto_move_dragon` → cursor (G7: сдвинуть верхнего дракона на пустую колонку) → `auto_collect_moved` → main.
- **Сбор драконов мимо кнопки (реплей):** main → `collect_done` → dragon_button (C6; `is_enable=false` + `check_state` — то же состояние, что после клика).
- **Уровень/UI:** ui → `start_game/restart_level/unload_level` → game_manager; game_manager ↔ proxy: `async_load/enable` → proxy, `proxy_loaded/proxy_unloaded` → game_manager.
- **Render:** main → `use_fixed_fit_projection` → `@render:`.

## Солвер (`solver/`) — pure Lua 5.4, без Defold

| Файл | Роль | API |
|---|---|---|
| `rules.lua` | Движок правил + DFS-солвер (IDDFS, транспозиции, node-budget) | `deal(seed)` `legal_moves(state)` `apply_move(state,move)` `is_win(state)` `can_auto_finish(state)` `can_move_to_foundation_safe(card,top)` `forced_moves(state)` `solve(state,opts)` |
| `bridge.lua` | Снапшот игры → состояние солвера (только game→solver) | `card(gc)` `from_game(snap)` |
| `board_view.lua` | Рендер состояния в текст (без IO) | `card_str(card)` `render(state,info)` `describe(move)` |
| `run.lua` | CLI: solve диапазона сидов, golden-файлы, self-verify | вход: `lua solver/run.lua --seeds A..B [--budget N]`; пишет `solver/golden/<seed>.txt` |
| `watch.lua` | Терминальный аниматор разбора партии | вход: `lua solver/watch.lua [--seed N --delay S --budget N --no-color]`; ре-экспорт `card_str/render/describe` |
| `replay.lua` | Pure director: `plan(state, moves, go_map)` → список директив для in-game авто-реплея (stage 2b). Без Defold — полностью unit-тестируем. | `M.plan(state,moves,go_map)` `M.BLOCKED`; директивы используются `debug_replay` в `main.script` |

**Типы ходов** (`rules.legal_moves`): `to_foundation` `to_free_cell` `from_free_cell` `tableau_to_tableau` `multi_to_tableau` `dragon_collect` `flower_auto` (+ `to_empty_tableau` в apply).
**state** = `{tableau, foundation_top, free_cells, flower_slot, dragons_collected, dragon_counter, free_slots_counter}`.
**Snapshot-контракт (вход bridge):** `snap.tableau[1..8]` (низ→верх), `snap.foundation{red,blue,green}`, `snap.free_cells[1..3]` (nil / `{card}` / `{card,blocked=true}`), `snap.flower` (bool). Живой снапшот собирает `main.snapshot_and_go_map` из зеркал `tableau_card_added/removed`, `free_cell_changed` и `flower_collected`; 4-й возврат — строка отказа (нечестный снапшот ⇒ не решаем). Гарды отказа: цветок в ячейке · заблокированная ячейка без дракона · один GO в двух местах · недоигранный сбор драконов · **перепись карт** (C5: настоящая раздача = 40 карт, мультимножество по номиналу+масти; только при `self.is_full_deal`).

### Тесты (`solver/tests/`)
Запуск: `lua solver/tests/run_all.lua` (из корня; exit 0/1). Харнесс — `harness.lua` (`new_harness`, `H.test/report/assert_eq`).
`test_deal` (d1-d8 раздача/детерминизм) · `test_win` (w1-w6; w2/w3 — защита от бага `base_cards_count>=27`) · `test_moves` (B1-B8 паритет ходов) · `test_solvable` (мини-борд из `main.script` `deal_auto_finish_test`) · `test_fixes` (fix#1 oracle, C1 счётчик драконов = верхушки **+ незаблокированные free cells**; закопанный дракон не считается) · `test_watch` (рендер) · `test_bridge` (game→solver, round-trip) · `test_replay` (директивы `replay.plan`: desync, go-reuse, double-book, terminal-win) · `test_review_bugs` (F3–F7, F10, C3) · `test_game_scripts` (F1, F2, F3 леттербокс, F4, F9, A3, A6 + дедуп драконов в обе стороны, C2 контракт `drop_success`/двойной `remove_card`, C4 зеркало free cells + `snapshot_and_go_map`, C5 перепись карт + зеркало цветка, C10 blocked-ячейка ничего не возвращает, C11 уведомление cursor на занятой ячейке, C6 `collect_done`, G1 ложная победа при карте в ячейке, G2 победа = пустой стол + авто-сбор драконов, FX математика болтания карты — .script под Defold-stub, включая `main.script`) · `test_layout` (G6 геометрия: парсит настоящие `gui/ui.gui` и обе коллекции, проверяет, что кнопки не перекрывают карты, что поле не заходит в правый рельс (x≥868) и что колонка на 12 карт влезает по вертикали) · `test_yandex_sdk` (D1: последовательность вызовов SDK из Lua и приоритет языка; парность start/stop живёт в JS-мосту и проверяется сценарием `yasdk`, а не здесь; сюда же — победа шлёт `gameplay_over`, `ui.gui_script` грузится под gui-заглушкой). **152/152.**
Симуляции под ручную проверку message-flow (не в run_all): `reviews/repro/{f2,a6,f10}_sim.lua` — грузят настоящие `.script` в изолированные окружения с движком сообщений и `update`.

### Браузерный play-test (`tools/browser-test.py`)
Гоняет настоящий js-web бандл в headless Chromium (SwiftShader WebGL) и правит его реальными мышью/клавишами; `print` игры виден в консоли браузера. Сценарии: `boot` · `hittest` (драг карты во free cell, вердикт по яркости пикселей — **единственная проверка не-16:9 канваса**) · `win` (солвер ведёт настоящие карты, `debug_replay` сам печатает `[REPLAY] WIN ✓`; **здесь же единственная сквозная проверка D1 «победа гасит геймплей»** — в `yasdk` единственный `stop` приходит от `visibilitychange`, то есть изнутри JS, и мутация «мост глотает `gameplay(false)`» проходила и юниты, и стенд) · `stuck` (драг-машина; честная область — в докстринге) · `freecell` (C4: припарковать карту в ячейку, потом `R` — единственный сценарий, который различает честный снапшот free cells; `win` его НЕ различает, там ячейки пусты) · `focus` (D2: вычисленные браузером `overscroll-behavior`/`touch-action`, подавление контекстного меню НА ВСЕЙ странице — движок сам давит его только на канвасе — и suspend/resume AudioContext при уходе вкладки в фон) · `i18n` (H2/H3: язык из `?lang=`, снимки одной кнопки на en/ru обязаны различаться — лог о языке ничего не доказывает) · `audiobg` (D2: фокус снят ДО первого скрипта страницы, то есть AudioContext рождается уже в фоне — единственная проверка `apply()` в конструкторе; `focus` этого не видит) · `debugkeys` (блок D: dev-клавиши S/R/Space живут только в debug-сборке; **гонять на ОБОИХ бандлах** — в release движок молчит в консоль, поэтому там вердикт по пикселям стола) · `restartrace` (очередь нажатий RESTART; гонка прокси не воспроизвелась, сценарий висит сетью) · `yasdk` (D1: фальшивый `YaGames` ставится через `add_init_script` и отвечает НАМЕРЕННО ПОЗДНО, 20 с — иначе язык приезжает до отрисовки подписей и сценарий зеленеет без перекраски по `language_ready`. Вердикты по ПИКСЕЛЯМ и по счётчику вызовов в самой фальшивке, без единого print движка, поэтому **гоняется на ОБОИХ бандлах**. Проверяет: цепочку `ready,start,stop,start`, порядок ready→start при раннем PLAY, приоритет языка SDK над `?lang=` и то, что потеря ФОКУСА геймплей не гасит, в отличие от звука — 4 мутации) · `resize` (требование Я.Игр §2: ресайз окна как СОБЫТИЕ по ходу партии — `hittest` гоняется на разных вьюпортах, но каждый раз с нуля и сброса раздачи не увидел бы. Оракул — вектор глубин восьми колонок до и после трёх ресайзов; в конце негативный контроль: принудительная пересдача обязана этот вектор сломать) · `census` (C5: `R` на доске, где цветок УЖЕ приземлился — единственный сценарий, где видно зеркало `flower_collected` и перепись карт; `win`/`freecell` не различают, там цветок обычно ещё закопан). Как собрать бандл и две ловушки (ввод сэмплится раз в кадр; `--no-coi` грузит ДРУГОЙ wasm) — в скилле `build`. `tools/browser-test-selfcheck.py` — оффлайн-проверка самого харнесса (`wait_for_log` не должен переиспользовать съеденную строку лога).

## Где править частые задачи
- **Правила хода/стекинга** → `tableau_script.can_stack_cards`, `card.is_correct_card`, `base_slot.check_correct_cards` (и зеркало в `rules.legal_moves`).
- **Авто-финиш** → `main.script` (`can_auto_finish`/`find_next_auto_card`/`auto_finish_step`) + `rules.can_auto_finish`.
- **Сбор драконов** → `dragon_button.script` + `free_cell.send_to_dragon_buttons` + `cursor` `get_dragon_cards`. Счётчик кнопки = ВЫСТАВЛЕННЫЕ драконы (верхушки + free cells), декремента нет; зеркало — `rules.compute_dragon_counter`. Припаркованные драконы тоже улетают в стопку, и **явно освобождать их ячейки не надо**: `card.script` на `drop_success` шлёт `remove_card` прежнему владельцу. Второй `remove_card` в ту же ячейку роняет игру (`check_dragon(nil)`) — пин-тесты в `test_game_scripts` (C2).
- **Авто-сбор драконов на победе** (G2/G4/G7) → main `begin_auto_collect` → cursor `auto_collect_dragons` (жмёт РОВНО ОДНУ горящую кнопку за вызов). Не горит ни одна → cursor `auto_collect_none` → main `dragon_relocation` выбирает верхушку самой высокой колонки и пустую колонку → cursor `auto_move_dragon` (fly_card_arc → `drop_success`, тот же путь, что и все автоотправки) → `auto_collect_moved` → main ждёт 4 кадра и заказывает следующий шаг. Сдвигать нечего/некуда → `auto_collect_give_up`: вернуть ввод и засчитать победу. Числа — `reviews/probe_dragon_unblock.lua`.
- **Победа** → `main.script` (`board_cleared` = 27 номиналов + пустые ячейки + 0 драконов + **цветок в слоте**; `declare_victory`; точки входа — `card_to_base` и `dragons_collected`) + `tutorial_state.show_victory` (UI poll). Совпадает с `rules.is_goal`. **Третья точка — `auto_collect_give_up`, условие там намеренно слабее** (27 номиналов + пустые ячейки, без чистого стола): запасной выход G2a от софт-лока, см. блок L в `plans/review-fixes.md`.
- **Звук** → `sfx.lua` (+ poll `sfx.pending` в `main.script` update).
- **Туториал** → `tutorial_state.lua` (`EXPECTED_MOVES`/`HIGHLIGHTS`) + `cursor` хайлайты + `ui.gui_script` хинты.
- **Текст/языки** → `i18n.lua`.
