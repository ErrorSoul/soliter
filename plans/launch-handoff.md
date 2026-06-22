# Handoff — состояние запуска (для продолжения после compact)

Обновлено: 2026-06-22. Ветка: `feat/launch-readiness` (НЕ master).

> Правило компакта (см. CLAUDE.md §Compact): архитектурные решения — дословно;
> изменённые файлы + ключевые изменения; статус верификации pass/fail; открытые
> TODO + откат; вывод инструментов — только pass/fail.

---

## 0. ГДЕ МЫ СЕЙЧАС (самое важное)

**Stage 1 (Track A — solver решаемости) ЗАВЕРШЁН и прошёл гейт трёх советников.**
Закоммичен в ветку `feat/launch-readiness` (4 коммита), **master чист, игра не тронута**.

**Текущий шаг:** пользователь выбрал — СНАЧАЛА большой прогон solver на **tamagochi**
(честная цифра решаемости), ПОТОМ мерж solver в master. Мерж ждёт: (а) цифры с
tamagochi, (б) явного апрува пользователя (3 советника уже одобрили).

**Что делать после компакта:** довести прогон на tamagochi (см. §4), получить цифру,
показать пользователю, спросить апрув на мерж. Затем Stage 2 (§5).

---

## 1. Ветка и коммиты

`feat/launch-readiness`, поверх `feat/settings-menu`. Коммиты солвера:
- `e9dcd96` feat(solver): pure-Lua solvability tool + review fixes
- `06f9a11` fix(solver): build_deck per-suit + bit-for-bit deal oracle
- `795b74a` docs(solver): composer-v2 verdict + исправление proven-unsolvable
- `5cef7de` feat(solver): sweep.sh параллельный + nice (вежливый)

**Тронуты только:** `solver/**`, `reviews/**`, `plans/launch-*.md`, `.gitignore`, `CLAUDE.md`.
**НЕ тронуты игровые файлы** (main.script, cursor.script, gui/*, render*) — лежат как
WIP в рабочем дереве (uncommitted, не наши изменения, не стейджить).
**Секреты** (`debug.keystore`, `*.pass.txt`, `manifest.*.der`, `project.shared_editor_settings`)
добавлены в `.gitignore` — больше не попадут в коммит (был реальный риск утечки).

---

## 2. Solver — состояние и АРХИТЕКТУРНЫЕ РЕШЕНИЯ (дословно)

**Статус верификации: 25/25 тестов PASS, 0 golden-replay FAIL, 0 Defold-зависимостей.**
`lua solver/tests/run_all.lua` → зелёно. Файлы: `solver/{rules.lua, run.lua, sweep.sh,
SPEC.md, tests/*, golden/*}`. Канонический разбор правил — `solver/SPEC.md`.

Решения (не менять без причины):
- **Solver = чистый Lua**, правила ИЗВЛЕЧЕНЫ из игры (main/Scripts/*), не выдуманы из generic Shenzhen.
- **Победа = все 40 карт + цветок**, НЕ `base_count>=27`, НЕ `can_auto_finish`.
- **Раздача:** колода собирается **per-suit** (масть: 2..10 + 4 дракона, затем след.) —
  как `create_deck` (main.script:62-76); раздача **column-major** (5 карт в колонку,
  затем следующая) — как `deal_cards` (main.script:105-148). Сдвиг seed по Fisher-Yates
  (20 warmup + 3 прохода).
- **Счётчик драконов = ТОЛЬКО вершины tableau** (не free cells). Игровой счётчик
  (dragon_button.script:24-25) **монотонный** (инкремент на каждую экспозицию, без
  сброса) → солвер СТРОЖЕ (требует 4 одновременно на топах) → числа = **нижний порог**.
- **state_hash канонизирует** перестановочную симметрию: сортирует 8 строк-колонок и 3
  строки-free-cell. SOUND (колонки/ячейки взаимозаменяемы; hash только для visited-set).
  Это рычаг % (снижает timeout).
- **#3 цветок НЕ гардим** в ручных ходах: `free_cell.script:46-49` принимает любую карту
  (parity-тест B5), а цветок авто-улетает в `apply_mandatory` ДО ветвления → в поиске
  никогда не на вершине. Гард противоречил бы B5 и не менял поведение.
- **#5 is_goal оставлен as-is** (tableau пуст + free cells пусты/blocked): для полных
  раздач ⟹ is_win; буквальный is_win сломал бы mini-deal (нет цветка). run.lua
  дополнительно replay-проверяет полные раздачи через is_win.
- **#8 safe-foundation остаётся mandatory:** доказуемо solution-preserving (предикат
  `can_move_to_foundation_safe`, rules.lua:578: срабатывает только когда foundation
  других мастей ≥ V−1 → ни одной V на tableau не нужно). Не плодим A/B-флаг.
- **run.lua:** `--seeds A..B [--budget N]`; честные ярлыки solved-within-budget /
  timeout-NOT-proven-unsolvable / proven-unsolvable; golden replay self-check.

## 2a. Честные числа (это ПОЛ, не истинная доля)
- Бюджет-кривая (старый deck, seeds 1..50): 15k → 36%, 60k → 54%. Рост доказывает:
  (а) канонизация SOUND, (б) timeout = ограничение бюджета, НЕ нерешаемость.
- После фикса build_deck (другой sample, та же дистрибуция): 15k → 28%, 2 proven-unsolvable.
- **Поправка (была ошибка):** НЕ «0 proven-unsolvable на всех бюджетах» — при большем
  бюджете часть досок исчерпывается; «proven-unsolvable» = нерешаемо под КОНСЕРВАТИВНОЙ
  моделью солвера (строгий счётчик драконов), не обязательно в реальной игре.
- Lua-PRNG ≠ Defold → метрика репрезентативна ПО РАСПРЕДЕЛЕНИЮ, не по конкретным in-game seeds.
- Истинная доля ≥54% и растёт с бюджетом; точную даст большой прогон (§4).

---

## 3. Ревью (гейт 3 советников ПРОЙДЕН на исправленном коде)

Запись: `reviews/solver-SYNTHESIS.md` (главный документ). Сырьё:
`solver-grok-build.md` + `-v2.md`, `solver-composer.md` + `-v2.md`.
- **advisor** ✅ — track sound; внёс caveat'ы и формулировки.
- **grok-build v2** ✅ — «P0 устранены, канонизация sound».
- **composer v2** ✅ (перепрогон по исправленному дереву) — «три P0 устранены, новых P0
  в ядре нет; #3/#8 — корректные trade-offs». (Именно composer нашёл P0 build_deck,
  который advisor и grok пропустили → исправлено + oracle-тест.)

Остаточное (P2, не блок мержа): мёртвый код (`apply_mandatory` untracked, тип
`to_empty_tableau`, stored counter-поля, коммент «DFS/IDDFS») — в чистку (Stage E).

---

## 4. PENDING: большой прогон на tamagochi (текущий шаг)

**ssh из Bash Claude ЖЁСТКО БЛОКИРУЕТСЯ** (6+ отказов, несмотря на allow-rule
`Bash(ssh homepc:*)` — это sandbox/network-политика, не паттерн). Агенты воркфлоу тоже
в песочнице → наружу по ssh не ходят. **Запуск — только через `!` пользователя.**

tamagochi = `homepc` (~/.ssh/config: 192.168.0.103, user abu). **4 ядра, 16 ГБ RAM.**
Также будет считать МАТРИЦЫ → наш sweep должен быть ВТОРЫМ приоритетом + оставить буфер.
`lua5.4` там ЕЩЁ НЕ УСТАНОВЛЕН (проверено: `lua` не найден).

`sweep.sh` уже вежливый: `nice -n 19` + `ionice -c3`, дефолт ядер = `nproc−2` (=2 на 4-яд).
RAM не ограничение (~50–130 МБ/воркер при большом бюджете на фоне 16 ГБ).

**Три команды пользователю (каждая с префиксом `!`):**
1. Установить: `! ssh homepc 'command -v lua5.4 || (sudo apt-get update -qq && sudo apt-get install -y lua5.4); lua5.4 -v'` (sudo пароль в терминале; если не Debian/Ubuntu — спросить dnf/pacman).
2. Синк: `! rsync -az --delete /Users/abu/works/ShenzenSolitare/solver/ homepc:~/shz/solver/`
3. Калибровка: `! ssh homepc 'cd ~/shz && bash solver/sweep.sh 200 60000 lua5.4 2'`
   (+ опц. `! ssh homepc 'top -bn1 | head -15'` для footprint).

После калибровки → большой прогон в nohup+лог, напр.:
`! ssh homepc 'cd ~/shz && nohup bash solver/sweep.sh 3000 300000 lua5.4 2 > ~/shz/sweep_big.log 2>&1 &'`
затем поллить `! ssh homepc 'tail -5 ~/shz/sweep_big.log'`.
**Структура путей:** sweep.sh ждёт запуск из репо-рута (`cd ~/shz`, вызывает `solver/run.lua`).

Цифра с прогона → показать пользователю → спросить апрув на МЕРЖ solver в master.

---

## 5. Stage 2 — P0-зеркало в main.script (НЕ потерять)

Defold-файл, верификация В ИГРЕ (не headless), отдельная гейт-стадия:
- 🐛 `main.script:605` победа при `base_cards_count >= 27` → требовать все 40 + цветок.
- 🐛 `can_auto_finish` (main.script:464) слабее safe-предиката из `plans/auto-finish.md`.
Каноничные предикаты уже есть в `solver/rules.lua` (is_win, can_move_to_foundation_safe)
— main.script их ЗЕРКАЛИТ. Мирор-правка headless не верифицируется → флаг «проверить в игре».

---

## 6. Остальные треки запуска (ещё не начаты) — из launch-global.md

- **B** ревью кода (общий, частично сделан на solver) ; **C** ассеты (генерация→апрув юзера) ;
- **D** Yandex SDK (D1 SDK→D2 template→D3 save) — критпуть, нужна песочница (юзер) ;
- **G** туториал (понятность, по логике+грок) ; **H** i18n (шрифт H1, детекция H2, тексты H3) ;
- **E** чистка debug — ПОСЛЕДНЕЙ (camera debug UI, ~59 print, bundle id, опечатка названия) ;
- **F** публикация (аккаунт, метаданные, модерация 3-5 дн).

## 7. Открытые решения пользователя (не блок старта)
1. Responsive (PLAN §5) — включать в запуск или отложить?
2. D3 save-schema — централизованный снапшот (пересечение с plans/refactoring.md).

## 8. Уроки процесса
- Воркфлоу-агенты ТРИЖДЫ падали по «idle timeout» и ВРАЛИ об успехе; независимый
  schema'd verify-агент это ловил. Держать verify-агента всегда. Для точечных фиксов
  main-loop (ручные правки) надёжнее длинных агентов.
- Мерж в master: только 3 советника (✅) + апрув пользователя (⏳).
