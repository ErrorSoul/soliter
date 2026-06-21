Проверяю исправленный солвер и игровой код по трём P0 из прошлого раунда.
**Вердикт: три P0 устранены; рабочее дерево + oracle-тест сильнее SYNTHESIS-метрик. Новых P0 в ядре нет.**

Проверено: `25/25` тестов, oracle deal seeds `1/42/12345`, стабильные прогоны (3× идентичны).

---

### P0 — статус

| # | Фикс | Статус |
|---|------|--------|
| **1** column-major deal | ✅ `rules.lua:97-103` = `main.script:110-117` (outer col, inner 5×`table.remove`). Oracle bit-for-bit в `test_fixes.lua:49-88`. |
| **2** dragon counter tops-only | ✅ `rules.lua:185-201` — только `col[#col].is_dragon`; FC не считаются. Совпадает с `tableau_script.script:43-44` → `dragon_button.script:24-25`. Тесты fix#2 зелёные. |
| **3** state_hash канонизация | ✅ **SOUND** — `rules.lua:626-662`: sort 8 col-строк + 3 FC-строк; foundation/flower/`dragons_collected` позиционно. Слоты/колонки взаимозаменяемы → дедуп без потери reachability. Hash только для `visited`. |

---

### Сознательные решения

- **#3 (цветок не гардим):** ✅ Верно. `free_cell.script:46-50` — любая карта (B5). `apply_mandatory_tracked` (`rules.lua:781-791`) улетает **до** `legal_moves`/ветвления (`rules.lua:946`) → цветок не топ на search-узле; гард = мёртвый код, противоречит B5.
- **#8 (safe-foundation mandatory):** ✅ Обосновано. `can_move_to_foundation_safe` (`rules.lua:579-594`) + цикл в `apply_mandatory_tracked:828-857`. Предикат solution-preserving: при `V` safe обе другие масти уже ≥`V−1` в foundation → `V` не нужен как bottom для stacking. Обрезает поиск, не теряет существование решений.

---

### Бюджет-кривая (перезамер, текущий `rules.lua` с per-suit deck)

| Бюджет | solved | proven-unsolvable | timeout |
|--------|--------|-------------------|---------|
| 15k | **14/50 (28%)** | **2** (seeds 1, 11) | 34 |
| 60k | **23/50 (46%)** | **2** (seeds 1, 11) | 25 |

Числа SYNTHESIS (36%/54%, 0 proven-unsolvable) — от **старого** `build_deck` (all-numerics→all-dragons). С per-suit deck (как `main.script:65-72`): **18→14**, **27→23**, появились 2 proven-unsolvable.

Рост 28%→46% с бюджетом подтверждает: канонизация #4 не режет решения; timeout ≠ нерешаемость. **Пол** — да: strict tops-dc (SPEC §3.4) + бюджет DFS.

---

### Новые находки (файл:строка)

| Severity | Находка |
|----------|---------|
| **P1** | `solver/rules.lua:49-61` — uncommitted fix per-suit `build_deck`; без него shuffle расходится с `main.script:65-72` (26/40 карт на seed 42). P0 fidelity, не в SYNTHESIS-таблице. |
| **P1** | `reviews/solver-SYNTHESIS.md:60` — «proven-unsolvable=0 на всех бюджетах» **ложно**: old deck 60k → seeds 10/18/27; new deck → 1/11 на обоих бюджетах. |
| **P1** | `solver/rules.lua:601-614` — `is_goal` ≠ `is_win` (#5 пропущен). Для полных раздач ок при `run.lua` replay-check; риск ложного solved на mini-board без цветка. |
| **P2** | `solver/rules.lua:684-769` — мёртвый `apply_mandatory(state,path)`, не вызывается (живой: `apply_mandatory_tracked`). |
| **P2** | `solver/rules.lua:522-532` — `to_empty_tableau` в `apply_move`, не генерится в `legal_moves`. |
| **P2** | `solver/golden/*.txt` — частично устарели после deck-reorder; 14 golden на последнем 15k-прогоне. |

**P0/P1 регрессий в can_stack, multi-run B7, foundation, FC, dragon, flower/2 auto, apply, DFS — нет.**

---

**Итог:** P0 #1–#3 закрыты и верифицированы по коду игры. #3/#8 — корректные trade-offs. Перед мержем: закоммитить per-suit `build_deck` + oracle-тест, поправить SYNTHESIS-метрики, разобрать seeds 1/11 (false negative vs реальная нерешаемость).
истинная решаемость.
