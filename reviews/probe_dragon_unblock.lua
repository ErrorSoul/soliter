-- probe_dragon_unblock.lua — G7: хватит ли «сдвинуть дракона», чтобы доиграть
-- партию до буквально пустого стола?
--
-- Контекст. На foundation=27 в игре остаются только драконы (все 27 номиналов
-- уже разложены, цветок в своём слоте). Кнопка сбора масти горит, только когда
-- все ЧЕТЫРЕ дракона масти открыты (верхушки колонок + незапечатанные ячейки),
-- поэтому дракон, лежащий ПОД драконом, счётчик не поднимает. Замер
-- probe_win27.lua: из 57 решённых раздач 15 доходят до foundation=27 при живых
-- драконах, и в 4 из них не горит ни одна кнопка. Сейчас игра в этой точке
-- объявляет победу поверх драконов (auto_collect_none → declare_victory).
--
-- Вопрос замера: если научить авто-сбор СДВИГАТЬ верхнего дракона на пустую
-- колонку, сколько из 15 доигрываются до нуля драконов? От ответа зависит
-- дизайн: 15/15 — уступку с победой поверх драконов можно убирать; меньше —
-- уступка остаётся хвостом, а сдвиг лишь сокращает разрыв.
--
-- Меряем ТРИ политики плюс потолок:
--   A. только сбор (сегодняшнее поведение) — базовая линия;
--   B. сбор, иначе сдвинуть верхнего дракона на пустую колонку (жадно);
--   C. то же плюс сдвиг в свободную ячейку, когда пустых колонок нет;
--   ★ полный перебор по тем же трём типам ходов — потолок достижимого.
--
-- Легальность НЕ переизобретаем: берём rules.legal_moves. Гейт на сбор там
-- уже per-suit (compute_free_slots_counter), то есть ровно та семантика
-- «ячейка со своей мастью либо пустая», что и cursor.collect_slot_for. Если
-- бы мы проверяли общий счётчик, замер завысил бы успех ровно там, где жил
-- блокер G4.
--
-- Запуск: /opt/homebrew/bin/lua reviews/probe_dragon_unblock.lua [--seeds N]

package.path = "./solver/?.lua;" .. package.path
local rules = require("rules")
io.stdout:setvbuf("line")

local SEEDS = 60
for i = 1, #arg - 1 do
   if arg[i] == "--seeds" then SEEDS = tonumber(arg[i + 1]) or SEEDS end
end

local function foundation_full(s)
   return s.foundation_top.red == 10 and s.foundation_top.blue == 10 and s.foundation_top.green == 10
end

local function dragons_alive(s)
   local n = 0
   for i = 1, 8 do
      for _, c in ipairs(s.tableau[i]) do
         if c.value == "d" then n = n + 1 end
      end
   end
   for _, fc in ipairs(s.free_cells) do
      if fc.card and fc.card.value == "d" and not fc.is_blocked then n = n + 1 end
   end
   return n
end

-- ---------------------------------------------------------------- ходы

local function collects(s)
   local out = {}
   for _, mv in ipairs(rules.legal_moves(s)) do
      if mv.type == "dragon_collect" then out[#out + 1] = mv end
   end
   return out
end

local function col_empty(s, i) return #s.tableau[i] == 0 end

-- Сдвиг верхнего дракона на ПУСТУЮ колонку. Именно этот ход умеет сделать
-- палец, значит его же должен делать авто-сбор.
local function moves_to_empty(s)
   local out = {}
   for _, mv in ipairs(rules.legal_moves(s)) do
      if mv.type == "tableau_to_tableau" and col_empty(s, mv.to_col) then
         local col = s.tableau[mv.from_col]
         local top = col[#col]
         if top and top.value == "d" then
            out[#out + 1] = { mv = mv, depth = #col }
         end
      end
   end
   return out
end

local function moves_to_cell(s)
   local out = {}
   for _, mv in ipairs(rules.legal_moves(s)) do
      if mv.type == "to_free_cell" then
         local col = s.tableau[mv.from_col]
         local top = col[#col]
         if top and top.value == "d" then out[#out + 1] = mv end
      end
   end
   return out
end

-- ---------------------------------------------------------------- политики

local STEP_CAP = 60

-- Жадная политика: сначала всё, что собирается; иначе — сдвинуть верхнего
-- дракона с САМОЙ ВЫСОКОЙ колонки (это монотонно уменьшает глубину закопанных).
--
-- Правило выбора здесь ДОСЛОВНО повторяет main.dragon_relocation: колонки
-- перебираются слева направо, берётся первая строго более глубокая (то есть при
-- равной глубине выигрывает младший номер), цель — первая пустая колонка по
-- порядку. Иначе замер подтверждал бы «какую-нибудь жадную политику», а не ту,
-- что уехала в игру. Порядок сбора мастей в игре как раз произвольный (курсор
-- обходит кнопки через pairs), но это покрыто строкой «потолок»: полный перебор
-- пробует все порядки и даёт тот же результат.
local function pick_like_game(s)
   local to_col = nil
   for i = 1, 8 do
      if col_empty(s, i) then to_col = i break end
   end
   if not to_col then return nil end
   local from_col, best_depth = nil, 1
   for i = 1, 8 do
      local col = s.tableau[i]
      if #col >= 2 and #col > best_depth and col[#col].value == "d" then
         from_col, best_depth = i, #col
      end
   end
   if not from_col then return nil end
   return { type = "tableau_to_tableau", from_col = from_col, to_col = to_col }
end

-- Ревью блока H (grok-4.5), находка 1: auto_collect_give_up объявляет победу,
-- не глядя на свободные ячейки, хотя комментарий рядом обещает «ни пустой
-- колонки, ни ячейки». Вопрос замера: бывает ли вообще состояние, где политика
-- игры (B) встала, драконы живы, а ячейка свободна — то есть где уступка
-- срабатывает РАНЬШЕ, чем игрок исчерпал ходы.
-- Возвращает: драконов осталось, свободных ячеек, пустых колонок.
local function give_up_snapshot(s0)
   local s = s0
   for _ = 1, STEP_CAP do
      local c = collects(s)
      if #c > 0 then
         s = rules.apply_move(s, c[1])
      else
         local mv = pick_like_game(s)
         if not mv then break end
         s = rules.apply_move(s, mv)
      end
   end
   local cells = 0
   for _, fc in ipairs(s.free_cells) do
      if not fc.card and not fc.is_blocked then cells = cells + 1 end
   end
   local empty_cols = 0
   for i = 1, 8 do if col_empty(s, i) then empty_cols = empty_cols + 1 end end
   return dragons_alive(s), cells, empty_cols
end

local function greedy(s0, allow_cell)
   local s = s0
   for _ = 1, STEP_CAP do
      local c = collects(s)
      if #c > 0 then
         s = rules.apply_move(s, c[1])
      else
         local mv = pick_like_game(s)
         if mv then
            s = rules.apply_move(s, mv)
         elseif allow_cell then
            local mc = moves_to_cell(s)
            if #mc == 0 then break end
            s = rules.apply_move(s, mc[1])
         else
            break
         end
      end
   end
   return dragons_alive(s)
end

-- Потолок: полный перебор по тем же трём типам ходов.
local function key(s)
   local parts = {}
   for i = 1, 8 do
      local t = {}
      for j, c in ipairs(s.tableau[i]) do t[j] = tostring(c.value) .. (c.suit or "") end
      parts[#parts + 1] = table.concat(t, ",")
   end
   for _, fc in ipairs(s.free_cells) do
      parts[#parts + 1] = fc.card
         and (tostring(fc.card.value) .. (fc.card.suit or "") .. (fc.is_blocked and "!" or ""))
         or "-"
   end
   return table.concat(parts, "|")
end

local function best_reachable(s0)
   local seen, best, budget = {}, dragons_alive(s0), 20000
   local stack = { s0 }
   seen[key(s0)] = true
   while #stack > 0 and budget > 0 do
      local s = table.remove(stack)
      budget = budget - 1
      local n = dragons_alive(s)
      if n < best then best = n end
      if best == 0 then return 0 end
      local cand = {}
      for _, mv in ipairs(collects(s)) do cand[#cand + 1] = mv end
      for _, m in ipairs(moves_to_empty(s)) do cand[#cand + 1] = m.mv end
      for _, mv in ipairs(moves_to_cell(s)) do cand[#cand + 1] = mv end
      for _, mv in ipairs(cand) do
         local ns = rules.apply_move(s, mv)
         local k = key(ns)
         if not seen[k] then
            seen[k] = true
            stack[#stack + 1] = ns
         end
      end
   end
   return best
end

-- ---------------------------------------------------------------- прогон

local cases = 0
local statA, statB, statC, statBest = 0, 0, 0, 0
local give_ups, give_ups_with_cell, give_ups_hopeless = 0, 0, 0
local give_up_rows = {}
local rows = {}

for seed = 1, SEEDS do
   local state = rules.deal(seed)
   local moves, verdict = rules.solve(state, { node_budget = 200000 })
   if verdict == "solved" then
      local s = state
      local hit = nil
      for _, mv in ipairs(moves) do
         s = rules.apply_move(s, mv)
         if foundation_full(s) then hit = s break end
      end
      if hit and dragons_alive(hit) > 0 then
         cases = cases + 1
         local a = greedy(hit, false)
         -- политика A = только сбор: отдельная петля без сдвигов
         local only = hit
         for _ = 1, STEP_CAP do
            local c = collects(only)
            if #c == 0 then break end
            only = rules.apply_move(only, c[1])
         end
         local nA = dragons_alive(only)
         local nB = a
         local nC = greedy(hit, true)
         local nBest = best_reachable(hit)
         local gd, gcells, gcols = give_up_snapshot(hit)
         if gd > 0 then
            give_ups = give_ups + 1
            if gcells > 0 then give_ups_with_cell = give_ups_with_cell + 1 end
            if nBest > 0 then give_ups_hopeless = give_ups_hopeless + 1 end
            give_up_rows[#give_up_rows + 1] = string.format(
               "  seed %3d: уступка при %d драконах, свободных ячеек %d, пустых колонок %d, потолок %d (%s)",
               seed, gd, gcells, gcols, nBest,
               nBest > 0 and "безнадёжно — уступка честная" or "ПОЛНЫЙ ПЕРЕБОР ДОИГРЫВАЕТ — уступка ранняя")
         end
         if nA == 0 then statA = statA + 1 end
         if nB == 0 then statB = statB + 1 end
         if nC == 0 then statC = statC + 1 end
         if nBest == 0 then statBest = statBest + 1 end
         rows[#rows + 1] = string.format(
            "  seed %2d: драконов на foundation=27 %2d → A(только сбор) %d · B(+пустая колонка) %d · C(+ячейка) %d · потолок %d",
            seed, dragons_alive(hit), nA, nB, nC, nBest)
      end
   end
end

print(string.format("партий с живыми драконами на foundation=27: %d (из сидов 1..%d)", cases, SEEDS))
for _, r in ipairs(rows) do print(r) end
print("")
print(string.format("доигрывается до НУЛЯ драконов:"))
print(string.format("  A. только сбор (сегодня)          : %d из %d", statA, cases))
print(string.format("  B. + сдвиг на пустую колонку      : %d из %d", statB, cases))
print(string.format("  C. + сдвиг в свободную ячейку     : %d из %d", statC, cases))
print(string.format("  ★ потолок (полный перебор)        : %d из %d", statBest, cases))
if statB < statBest then
   print("  ⚠ жадная политика B хуже потолка — порядок ходов имеет значение")
end
if statC > statB then
   print("  ⚠ без сдвига в ячейку часть партий не доигрывается")
end
print("")
print(string.format("уступка (политика игры встала при живых драконах): %d из %d", give_ups, cases))
print(string.format("  из них со СВОБОДНОЙ ЯЧЕЙКОЙ на руках: %d", give_ups_with_cell))
print(string.format("  из них безнадёжных и по полному перебору: %d", give_ups_hopeless))
for _, r in ipairs(give_up_rows) do print(r) end
if give_ups_with_cell == 0 then
   print("  → ветка «сдвинуть дракона в ячейку» на этой выборке не спасла бы ни одной партии")
end
