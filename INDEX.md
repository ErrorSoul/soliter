# INDEX.md — навигационная карта (символ → файл)

Цель: прыгать в нужный файл/символ без чтения всего проекта. Номеров строк нет —
точную строку добирать `grep`'ом по имени символа. Архитектуру/z-index/респонсив см.
[architecture.md](./architecture.md). Этот файл — только «что где лежит».

## Раскладка

- `main/` — игровой рантайм (логика, слоты, ввод). `gui/` — UI. `solver/` — pure-Lua солвер + тесты.
- Точка входа: `main/main.collection` → `game_manager.script` → грузит level proxy (`soliter.collection`).
- `soliter.collection` / `soliter1.collection` — идентичны; содержат слоты + `card_table` (в нём `main.script`, фабрики `card_factory`, `cursor_factory`).
- **Cross-collection через polling** (proxy-коллекции не шлют msg наружу): `sfx.pending`, `tutorial_state.*_dirty`, `tutorial_state.show_victory` — опрашиваются в update'ах `main.script` / `cursor.script` / `ui.gui_script`.

## Игровой рантайм — файл → роль → ключевые символы

| Файл (`main/Scripts/` если не указано) | Роль | Ключевые символы |
|---|---|---|
| `main.script` | Ядро состояния: колода, раздача, авто-финиш, победа, солвер-дебаг | `create_deck` `shuffle_deck` `deal_cards` `deal_tutorial_cards` `deal_dragon_test` `deal_auto_finish_test` `can_auto_finish` `find_next_auto_card` `auto_finish_step` `start_auto_finish` `build_solver_snapshot` `snapshot_and_go_map` `debug_solve` `debug_replay` · поля: `foundation_top` `suit_to_base` `base_cards_count` |
| `cursor.script` | Хаб ввода: touch, hit-test, валидация дропа, drag-состояние, tutorial-хайлайты | hit-test: `check_tableau_slots` `check_last_cards` `check_free_slots` `check_flower_slot` `check_base_slots` `check_free_tableau_slots` `check_dragon_buttons` `screen_to_world` · tutorial: `find_card_by_data_id` `clear_tutorial_highlights` `apply_tutorial_highlights` `fly_card_arc` |
| `card.script` | Карта: drag, анимации, тинты | `set_card` `is_correct_card` |
| `base_slot.script` | Foundation (2→10, одна масть) | `check_correct_cards` |
| `free_cell.script` | Free cell (1 карта / blocked-пайл драконов) | `check_dragon` `send_to_dragon_buttons` `change_button_counter` |
| `tableau_script.script` | Колонка tableau: видимый стек, авто-отправка верхней карты | `can_stack_cards` `update_visible_cards` `last_card_to_slot` `contains` |
| `flower_slot.script` | Слот цветка (только `'f'`, авто-победа) | — (`check_slot`/`occupy_slot`) |
| `dragon_button.script` | Сбор драконов (актив при 4 + free slot) | `check_state` `free_slot_any` |
| `game_manager.script` | Загрузка/перезагрузка уровня через collectionproxy | (msg: `start_game` `restart_level` `unload_level`) |
| `Game.script` (`main/`) | Чистый Lua-класс правил (НЕ привязан к Defold; похоже legacy) | `Game.new` `Game:canMoveCard` `Game:checkWin` `Game:init` `Card.new` |
| `sfx.lua` | Звук: прямой `sound.play` или очередь | `M.pending` `M.play` `M.queue` + `card_pick/card_drop/card_error/card_deal/dragon_collect/button_click/victory/flower_auto/auto_finish` |
| `i18n.lua` | Локализация en/ru/tr | `M.lang` `M.strings` `M.t` `M.set_lang` |
| `tutorial_state.lua` | Состояние туториала (polling-флаги) | `M.is_tutorial` `M.step` `M.ui_dirty` `M.show_victory` `M.highlight_dirty` `M.EXPECTED_MOVES` `M.HIGHLIGHTS` `M.check_move` `M.advance` `M.reset` |
| `gui/ui.gui_script` | Главный UI: старт-экран, victory overlay, tutorial-хинты | `restart_level` `update_tutorial_hint` |
| `gui/game.gui_script` | Респонсив-раскладка нод (частично legacy) | `adjust_layout` `update_dragon_buttons` |
| `gui/test.gui_script` | Утилита позиций tableau (вне основного флоу) | — |

### Game Objects → скрипт
`card.go`→card · `cursor.go`→cursor · `base_slot.go`→base_slot · `free_slot.go`→free_cell · `tableau_slot.go`→tableau_script · `flower_slot.go`→flower_slot · `dragon_button.go`→dragon_button · `background.go`/`sound_manager.go`→спрайт/звук без скрипта.

## Message-passing (sender → id → receiver), сжато

- **Инициализация:** `main` → `set_cards/set_free_slots/set_base_slots/set_flower_slot/set_tableau_slots/set_dragon_buttons` → cursor; `main` → `update_stack` → tableau; `main` → `set_button` → dragon_button.
- **Ввод/драг:** cursor → `start_drag/drag_update/drop_success/drop_failed/can_move_card` → card; card → `valid_card/invalid_card` → cursor.
- **Валидация дропа:** cursor → `set_cursor/check_slot/can_pick_card` → слоты; слот → `slot_valid/slot_invalid` → cursor; free_slot → `slot_with_card/update_free_slot` → cursor; base_slot → `base_slot_full` → cursor.
- **Дроп-результат:** card → `occupy_slot` → целевой слот; card → `remove_card` → слот-владелец.
- **Авто-полёт (tableau детектит верх):** tableau → `send_to_flower_slot/send_to_base_slot` → cursor; tableau → `send_counter_to_button` → dragon_button.
- **Драконы:** free_slot → `change_free_slots_button_counter` → dragon_button; cursor → `set_button_state/get_dragon_cards` → dragon_button; dragon_button → `dragons_collected` (через 1.5с) → main.
- **В main:** base_slot → `card_to_base` → main; cursor → `check_auto_finish/send_auto_finish_check` → main.
- **Уровень/UI:** ui → `start_game/restart_level/unload_level` → game_manager; game_manager ↔ proxy: `async_load/enable` → proxy, `proxy_loaded/proxy_unloaded` → game_manager.
- **Render:** main → `use_fixed_fit_projection` → `@render:`.

## Солвер (`solver/`) — pure Lua 5.4, без Defold

| Файл | Роль | API |
|---|---|---|
| `rules.lua` | Движок правил + DFS-солвер (IDDFS, транспозиции, node-budget) | `deal(seed)` `legal_moves(state)` `apply_move(state,move)` `is_win(state)` `can_auto_finish(state)` `can_move_to_foundation_safe(card,top)` `solve(state,opts)` |
| `bridge.lua` | Снапшот игры → состояние солвера (только game→solver) | `card(gc)` `from_game(snap)` |
| `board_view.lua` | Рендер состояния в текст (без IO) | `card_str(card)` `render(state,info)` `describe(move)` |
| `run.lua` | CLI: solve диапазона сидов, golden-файлы, self-verify | вход: `lua solver/run.lua --seeds A..B [--budget N]`; пишет `solver/golden/<seed>.txt` |
| `watch.lua` | Терминальный аниматор разбора партии | вход: `lua solver/watch.lua [--seed N --delay S --budget N --no-color]`; ре-экспорт `card_str/render/describe` |
| `replay.lua` | Pure director: `plan(state, moves, go_map)` → список директив для in-game авто-реплея (stage 2b). Без Defold — полностью unit-тестируем. | `M.plan(state,moves,go_map)` `M.BLOCKED`; директивы используются `debug_replay` в `main.script` |

**Типы ходов** (`rules.legal_moves`): `to_foundation` `to_free_cell` `from_free_cell` `tableau_to_tableau` `multi_to_tableau` `dragon_collect` `flower_auto` (+ `to_empty_tableau` в apply).
**state** = `{tableau, foundation_top, free_cells, flower_slot, dragons_collected, dragon_counter, free_slots_counter}`.
**Snapshot-контракт (вход bridge):** `snap.tableau[1..8]` (низ→верх), `snap.foundation{red,blue,green}`, `snap.free_cells[1..3]` (nil / `{card}` / `{card,blocked=true}`), `snap.flower` (bool).

### Тесты (`solver/tests/`)
Запуск: `lua solver/tests/run_all.lua` (из корня; exit 0/1). Харнесс — `harness.lua` (`new_harness`, `H.test/report/assert_eq`).
`test_deal` (d1-d8 раздача/детерминизм) · `test_win` (w1-w6; w2/w3 — защита от бага `base_cards_count>=27`) · `test_moves` (B1-B8 паритет ходов) · `test_solvable` (мини-борд из `main.script` `deal_auto_finish_test`) · `test_fixes` (fix#1 oracle, fix#2a/2b счётчик драконов = только tableau-tops) · `test_watch` (рендер) · `test_bridge` (game→solver, round-trip) · `test_replay` (директивы `replay.plan`: desync, go-reuse, double-book, terminal-win).

## Где править частые задачи
- **Правила хода/стекинга** → `tableau_script.can_stack_cards`, `card.is_correct_card`, `base_slot.check_correct_cards` (и зеркало в `rules.legal_moves`).
- **Авто-финиш** → `main.script` (`can_auto_finish`/`find_next_auto_card`/`auto_finish_step`) + `rules.can_auto_finish`.
- **Сбор драконов** → `dragon_button.script` + `free_cell.send_to_dragon_buttons` + `cursor` `get_dragon_cards`.
- **Победа** → `main.script` (`card_to_base` → `base_cards_count`) + `tutorial_state.show_victory` (UI poll).
- **Звук** → `sfx.lua` (+ poll `sfx.pending` в `main.script` update).
- **Туториал** → `tutorial_state.lua` (`EXPECTED_MOVES`/`HIGHLIGHTS`) + `cursor` хайлайты + `ui.gui_script` хинты.
- **Текст/языки** → `i18n.lua`.
