-- solver/hint.lua — следующий ход для туториала, посчитанный ОТ ДОСКИ.
--
-- Зачем отдельный поиск, а не rules.solve. У solve цель is_goal: пустые колонки
-- и пустые ячейки. Туториальная раздача такой цели не имеет ФИЗИЧЕСКИ: в ней
-- лежат 4_blue, 5_green, 7_green, а тузов в колоде нет (номиналы 2..10), так что
-- ни один из этих трёх никогда не уйдёт в foundation и стол не опустеет.
-- Замер: rules.solve на стартовой доске туториала возвращает "unsolvable".
-- Победа в туториале объявляется по ДРУГОМУ условию — main.script на сообщении
-- dragons_collected в tutorial_mode сразу ставит WIN. Поэтому и цель здесь —
-- «сбор драконов состоялся», а не «стол пуст».
--
-- Поиск в ширину: первый ход КРАТЧАЙШЕГО пути к цели. Ширина, а не глубина,
-- потому что подсказка обязана быть лучшим ходом, а не первым найденным —
-- DFS увёл бы игрока по длинной ветке, которая формально тоже приводит к победе.
--
-- Дедупликация — rules.state_hash, тот же ключ, что у солвера (колонки и ячейки
-- в нём отсортированы, то есть перестановки схлопываются). Без канонизации обход
-- взрывается: замер на той же доске — >200000 рёбер без ответа против 9192 с ней.

local rules = require("solver.rules")

local M = {}

-- Полный обход достижимых состояний туториальной раздачи — 415 состояний и
-- 9192 ребра (замер, solver/tests/test_tutorial_hint.lua держит это число).
-- Бюджет с запасом вдвое: он страховка от чужой раздачи, а не рабочий предел.
M.DEFAULT_BUDGET = 20000

local function collected_count(state)
   local n = 0
   for _, suit in ipairs({ "red", "blue", "green" }) do
      if state.dragons_collected[suit] then n = n + 1 end
   end
   return n
end

-- Тип хода -> ярлык для текста подсказки. Ярлык, а не строка: локализация
-- живёт в i18n/ui, юнит-тесты не должны знать про язык.
--   foundation   — карта уходит наверх, в основание
--   free_cell    — карта паркуется в свободную ячейку
--   stack        — карта ложится на другую карту в колонке
--   empty_column — карта уходит в пустую колонку
--   dragon       — все четыре дракона открыты, жать кнопку
function M.kind(state, move)
   local t = move.type
   if t == "to_foundation" then return "foundation" end
   if t == "to_free_cell" then return "free_cell" end
   if t == "dragon_collect" then return "dragon" end
   if t == "from_free_cell" or t == "tableau_to_tableau" or t == "multi_to_tableau" then
      local col = state.tableau[move.to_col]
      if col and #col == 0 then return "empty_column" end
      return "stack"
   end
   return "stack"
end

-- Приоритет МЕЖДУ РАВНЫМИ ходами — теми, что лежат на кратчайших путях одной и
-- той же длины. Игроку он ничего не стоит (все кандидаты одинаково быстро ведут
-- к победе), но решает, чему туториал успевает научить.
--
-- Замер, из-за которого он появился: на четвёртом ходу «положить 4_blue на
-- 5_green» и «убрать 4_blue во вторую ячейку» — оба ходы длины 2, и чистый BFS
-- брал тот, что раньше в списке (ячейку). Стекинг — главная механика пасьянса,
-- и туториал, ни разу её не показавший, свою работу не сделал.
--
-- Порядок ниже даёт на туториальной раздаче ровно ту же линию, что вёл
-- сценарный v2: основание, основание, ячейка, стопка, драконы — то есть все три
-- инструмента игры плюс кнопка. Пустая колонка стоит последней намеренно: в
-- мини-раздаче колонки 6-8 пусты просто потому, что раздача короткая
-- (get_tableau_slots помечает их is_empty при tutorial_mode), а в настоящей
-- партии пустых колонок в начале не бывает — учить ходу, которого в игре ещё
-- нет, значит учить не тому.
local TEACH_RANK = {
   dragon = 1,        -- сбор драконов = победа в туториале, его не откладываем
   foundation = 2,    -- ход, который нельзя сделать зря
   stack = 3,         -- ради него всё и затевалось
   free_cell = 4,     -- фирменная механика, показать обязательно
   empty_column = 5,  -- артефакт короткой раздачи
}

-- Найти ход-подсказку для позиции `state`.
-- Возвращает (hint, status):
--   hint = { move = <ход rules.lua>, kind = <ярлык>, distance = <ходов до цели> }
--   status = "found" | "won" | "stuck" | "timeout"
-- "won" — на доске УЖЕ собрана масть драконов, то есть туториал выигран.
-- Это не теоретический случай: сбор сажает четыре карты по очереди, зеркало
-- ячейки успевает стать blocked раньше, чем игра объявит победу, и пересчёт
-- подсказки попадает ровно в это окно (замерено на стенде — там подсказка
-- печатала "stuck" и UI на миг показывал «ходов не осталось» перед экраном
-- победы). Без отдельного статуса такая доска неотличима от тупика: цель
-- «собрать ЕЩЁ одну масть» на туториальной раздаче недостижима.
-- "stuck" и "timeout" РАЗНЫЕ намеренно: первый — доска встала и надо начинать
-- заново, второй — не хватило бюджета, и звонящий обязан оставить старую
-- подсказку, а не врать игроку про тупик.
function M.find(state, opts)
   opts = opts or {}
   local budget = opts.budget or M.DEFAULT_BUDGET
   local start_collected = collected_count(state)
   if start_collected > 0 then return nil, "won" end

   local function is_goal(st)
      return collected_count(st) > start_collected
   end

   local seen = { [rules.state_hash(state)] = true }
   local frontier = { { state = state, first = nil, first_state = nil } }
   local edges, depth = 0, 0

   while #frontier > 0 do
      local next_frontier = {}
      local candidates = {}
      depth = depth + 1
      for _, node in ipairs(frontier) do
         for _, move in ipairs(rules.legal_moves(node.state)) do
            edges = edges + 1
            if edges > budget then return nil, "timeout" end
            local next_state = rules.apply_move(node.state, move)
            -- Первый ход ветки помним вместе с ПОЗИЦИЕЙ, из которой он делался:
            -- ярлык хода (стопка или пустая колонка) читается только там.
            local first_move, first_state = node.first, node.first_state
            if not first_move then first_move, first_state = move, node.state end
            if is_goal(next_state) then
               -- Кандидат записывается ДО дедупликации: две разные первые ветки
               -- могут прийти в одну и ту же цель, и вторую нельзя терять —
               -- именно между такими равными ходами и выбирает приоритет ниже.
               candidates[#candidates + 1] = { move = first_move, state = first_state }
            else
               local h = rules.state_hash(next_state)
               if not seen[h] then
                  seen[h] = true
                  next_frontier[#next_frontier + 1] =
                     { state = next_state, first = first_move, first_state = first_state }
               end
            end
         end
      end
      if #candidates > 0 then
         local best, best_rank
         for _, c in ipairs(candidates) do
            local kind = M.kind(c.state, c.move)
            local rank = TEACH_RANK[kind] or 99
            if not best_rank or rank < best_rank then
               best, best_rank = { move = c.move, kind = kind, distance = depth }, rank
            end
         end
         return best, "found"
      end
      frontier = next_frontier
   end

   return nil, "stuck"
end

return M
