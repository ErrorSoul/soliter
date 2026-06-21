**Пере-ревью солвера (post-fix, по SYNTHESIS.md «Применение фиксов»):** 25/25 тестов зелёные, 40/40 golden replay PASS (is_win после apply), все три P0 устранены без регрессий в правилах/apply/DFS. Сверка с main/Scripts/ проведена.

### 1. Deal column-major (main.script:105-148)
**Фикс применён верно, бит-в-бит.**

- solver/deal: outer `for col=1..8`, inner 5× `table.remove(deck)` + `table.insert(col)` (bottom-first). Shuffle (seed + 20 warmup + 3×FY) идентичен `shuffle_deck`.
- Reimpl game-логики (create_deck + shuffle + deal_cards с `cards_per_stack=5, rem=0`) даёт 100% совпадение всех 8 колонок на seeds 42/1/12345/99/7/50.
- Snapshot в `test_fixes.lua:53` (`seed=42` col1=`g6,b4,g5,b2,g3`, col2=`rd,b5,r8,rd,rd`) проходит.
- Ранее был round-robin (5×8) — 37/40 mismatch; теперь устранён. Детерминизм и состав (27 numeric 2-10 +12d +1f) сохранены.

### 2. compute_dragon_counter — только вершины tableau
**Фикс применён верно, совпадает с игрой.**

- `rules.lua:185-201`: только `for i=1..8`, `top=col[#col]`, `if top.is_dragon` (явный комментарий «TABLEAU-TOPS ONLY», ссылка на dragon_button.script:25 + tableau_script.script:44).
- Free cells **не** считаются (старая версия считала → ложный collect).
- `legal_moves`/`apply_mandatory_tracked`/`solve` всегда используют **derived** `compute_*` (stored значения игнорируются).
- Тесты `test_fixes:70` (3 tops + 1 в FC → **нет** `dragon_collect`) и `86` (4 tops → есть) зелёные.
- Игра: `send_counter_to_button` только из tableau (при expose вершины), free_cell только `change_free_slots...` (decrement). Counter в кнопке — аккумулятор, но collect eligibility в модели теперь по **текущим** tops (физически корректно; 4 dragons должны быть одновременно exposed).

### 3. state_hash — сортировка колонок + free cells
**Канонизация sound, решений не теряет.**

- `rules.lua:618-675`: `col_strs` (8 строк `suit:val,...`) → `table.sort`, то же для 3 FC (`B` / `C:s:v` / `_`). Foundation (per-suit), flower, `dragons_collected` (битмаска) — не сортируются.
- Обоснование: колонки и FC-слоты неразличимы (нет per-column свойств). Мультимножество piles одинаково → futures эквивалентны под переименованием индексов. Hash только для visited/transposition.
- В пределах **одного** solve от фиксированного initial deal: разные пути могут привести к одному мультимножеству в разных индексах → дедуп. Из одной лейблинговки можно таргетить нужные текущие piles по их col#, воспроизводя любую перестановку. Цель (`is_goal`) и win — по содержимому.
- Эффект: transposition стала работать (снижение таймаутов). После фикса — 0 golden-replay FAIL. 40/40 PASS сейчас. Решения не склеиваются (разные foundation/flower/collected — разный hash), не теряются.

### Сознательные решения
- **#3 (flower не гардим в ручных ходах, в т.ч. to_free_cell):** корректно. `free_cell.script:46-49` принимает любую карту (B5 в `test_moves.lua:410` явно требует `to_free_cell` для flower + dragon + numeric). `apply_mandatory*` (flower_auto первым в цикле) улетает **до** `legal_moves`/`ветвления` на любом state, где flower на вершине tableau. В поиске flower никогда не топ tableau → ручной ход по нему не генерится на практике. Гард противоречил бы B5 и не менял поведение. (Код + комментарий в rules:299 и test_fixes:100.)
- **#5 (is_goal оставлен as-is):** корректно. `is_goal` = tableau пуст + FC empty-or-blocked (работает для mini-deal без flower/dragons). Полный `is_win` (3×10 + flower) сломал бы `test_solvable.lua` (mini-борд из main.script:deal_auto_finish_test, flower отсутствует). Для полных раздач `run.lua:191` (replay_and_verify) + `is_win` после последовательности. Комментарий в rules:601-603 точный.

### Новые баги / регрессии (кратко)
- **solver/SPEC.md:184**: stale текст — «The solver's `compute_dragon_counter` adds free-cell dragons for convenience» (и «deviates... functionally safe»). После фикса #2 солвер считает **только** tops (как и должен). (doc, низкий severity, но сбивает с толку.)
- Мёртвый код (P2, отложено в синтезе): `apply_mandatory(state, path)` (не вызывается, портит path), обработка типа `to_empty_tableau` в `apply_move` + `move_to_str/str_to_move` (legal_moves больше не генерит, всегда `tableau_to_tableau` для single), хранимые `dragon_counter`/`free_slots_counter` в state (всегда recompute). Комментарии-артефакты в `legal_moves:334-352`.
- Safe-foundation всё ещё в `apply_mandatory*` (принудительно до ветвления). #8 был «отложено» — поведение consistent с текущими golden, но это conscious trade-off (может влиять на длину путей/метрики).
- Нет P0/P1 регрессий в ядре (can_stack, multi-run только maximal+валидные суффиксы B7, foundation, free cell, dragon, flower/2 auto, is_win, apply, DFS+transpo+budget, 23+ golden replay). 1..5/42 решают/реплеят чисто; honest-лейблы в run.lua на месте.

**Вывод:** P0 устранены, canonicalization sound, conscious решения обоснованы кодом+тестами+игрой. Готово к следующему этапу (кроме мелкой чистки SPEC + dead code).
