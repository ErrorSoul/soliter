-- test_tutorial_hint.lua — подсказка туториала (solver/hint.lua).
--
-- Проверяется ровно то, ради чего v3 затевался: подсказка считается ОТ ДОСКИ,
-- а не от номера шага, поэтому любой ход игрока — даже «неправильный» — не
-- ломает обучение, а просто меняет следующую подсказку.

local new_harness = require("solver.tests.harness")
local bridge = require("solver.bridge")
local hint = require("solver.hint")
local H = new_harness()

-- Доска туториала в том виде, в каком её отдаёт snapshot_and_go_map: цветок с
-- верхушки col5 УЖЕ улетел (config.auto_flies_from_tableau пускает его и в
-- туториале), поэтому в снапшоте он не карта, а flower = true.
local function tutorial_snapshot()
   local t = {}
   for i = 1, 8 do t[i] = {} end
   t[1] = { { value = "d", suit = "red" }, { value = 4, suit = "blue" },
            { value = 7, suit = "green" }, { value = 3, suit = "red" }, { value = 2, suit = "red" } }
   t[2] = { { value = 5, suit = "green" } }
   t[3] = { { value = "d", suit = "red" } }
   t[4] = { { value = "d", suit = "red" } }
   t[5] = { { value = "d", suit = "red" } }
   return { tableau = t, foundation = { red = 1, blue = 1, green = 1 },
            free_cells = { {}, {}, {} }, flower = true }
end

local function tutorial_state()
   return bridge.from_game(tutorial_snapshot())
end

-- ============================================================
-- 1. Почему не rules.solve
-- ============================================================

H.test("hint: rules.solve на туториальной доске НЕразрешима — отсюда отдельный поиск", function(rules)
   local moves, status = rules.solve(tutorial_state(), { node_budget = 50000 })
   if status == "solved" then
      return false, "solve() внезапно решает мини-раздачу — значит hint.lua можно упростить до solve"
   end
   if status ~= "unsolvable" then
      return false, "ожидался unsolvable (стол не опустеет: 4_blue/5_green/7_green некуда деть), получено " .. tostring(status)
   end
   return moves == false
end)

-- ============================================================
-- 2. Стартовая доска и вся учебная линия
-- ============================================================

H.test("hint: на старте подсказка — 2_red из первой колонки в основание", function()
   local h, status = hint.find(tutorial_state())
   if status ~= "found" then return false, "status = " .. tostring(status) end
   if h.kind ~= "foundation" then return false, "kind = " .. h.kind end
   if h.move.type ~= "to_foundation" or h.move.from_col ~= 1 then
      return false, "ход = " .. h.move.type .. " from_col=" .. tostring(h.move.from_col)
   end
   return true
end)

-- Линия, которую подсказка выстраивает сама. Она обязана совпасть со сценарием
-- v2 (основание, основание, ячейка, стопка, драконы): это и есть проверка, что
-- пересчёт от доски НЕ ХУЖЕ рукописного сценария и показывает все три
-- инструмента игры. Если приоритет TEACH_RANK перепутать, тест падает здесь.
H.test("hint: линия подсказок учит всем механикам и приводит к сбору драконов", function(rules)
   local state = tutorial_state()
   local kinds = {}
   for _ = 1, 10 do
      local h, status = hint.find(state)
      if status ~= "found" then return false, "оборвалось на " .. tostring(status) .. " после " .. #kinds .. " ходов" end
      kinds[#kinds + 1] = h.kind
      state = rules.apply_move(state, h.move)
      if state.dragons_collected.red then break end
   end
   if not state.dragons_collected.red then return false, "драконы так и не собрались" end
   local got = table.concat(kinds, ",")
   local want = "foundation,foundation,free_cell,stack,dragon"
   if got ~= want then return false, "линия = " .. got .. ", ожидалась " .. want end
   return true
end)

H.test("hint: расстояние до победы убывает на каждом ходу линии", function(rules)
   local state = tutorial_state()
   local prev
   for _ = 1, 10 do
      local h, status = hint.find(state)
      if status ~= "found" then break end
      if prev and h.distance >= prev then
         return false, "расстояние не убыло: " .. prev .. " -> " .. h.distance
      end
      prev = h.distance
      state = rules.apply_move(state, h.move)
      if state.dragons_collected.red then return true end
   end
   return false, "линия не дошла до сбора драконов"
end)

-- ============================================================
-- 3. Отклонения игрока — тот самый софтлок v2
-- ============================================================

-- v2 привязывал подсказку к номеру шага, и увод 5_green в ячейку на первом ходу
-- делал третий шаг («положи 4_blue на 5_green») невыполнимым навсегда.
H.test("hint: 5_green уведён в ячейку — подсказка НЕ ломается", function()
   local snap = tutorial_snapshot()
   snap.tableau[2] = {}
   snap.free_cells[1] = { card = { value = 5, suit = "green" } }
   local h, status = hint.find(bridge.from_game(snap))
   if status ~= "found" then return false, "status = " .. tostring(status) end
   return h.move.type == "to_foundation" and h.move.from_col == 1,
      "ожидался вывод 2_red в основание, получен " .. h.move.type
end)

H.test("hint: все три ячейки заняты — ход всё равно находится", function()
   local snap = tutorial_snapshot()
   snap.tableau[1] = { { value = "d", suit = "red" }, { value = 4, suit = "blue" } }
   snap.tableau[2] = {}
   snap.free_cells[1] = { card = { value = 5, suit = "green" } }
   snap.free_cells[2] = { card = { value = 7, suit = "green" } }
   snap.free_cells[3] = { card = { value = 3, suit = "red" } }
   snap.foundation.red = 2
   local h, status = hint.find(bridge.from_game(snap))
   if status ~= "found" then return false, "status = " .. tostring(status) end
   return h ~= nil
end)

-- Главный вывод полного обхода: у этой раздачи тупиков НЕТ. 415 достижимых
-- состояний, из каждого сбор драконов ещё возможен. Число зафиксировано: если
-- раздачу или правила поменяют, тест обязан упасть и заставить пересчитать.
H.test("hint: полный обход раздачи — 415 состояний, ни одного тупика", function(rules)
   local start = tutorial_state()
   local nodes = { [rules.state_hash(start)] = start }
   local order = { rules.state_hash(start) }
   local head = 1
   while head <= #order do
      local st = nodes[order[head]]
      head = head + 1
      if not st.dragons_collected.red then   -- цель терминальна, дальше туториал кончился
         for _, mv in ipairs(rules.legal_moves(st)) do
            local nxt = rules.apply_move(st, mv)
            local h = rules.state_hash(nxt)
            if not nodes[h] then
               nodes[h] = nxt
               order[#order + 1] = h
            end
         end
      end
   end
   if #order ~= 415 then return false, "достижимых состояний " .. #order .. ", ожидалось 415" end
   for _, h in ipairs(order) do
      local st = nodes[h]
      if not st.dragons_collected.red then
         local _, status = hint.find(st)
         if status ~= "found" then
            return false, "из достижимого состояния подсказки нет: " .. status
         end
      end
   end
   return true
end)

-- ============================================================
-- 4. Тупик и бюджет — их нельзя путать
-- ============================================================

-- Доска без единого хода: ячейки заняты неподвижными картами, все восемь
-- колонок заняты, стекать нечего, дракон один и закопан.
local function dead_snapshot()
   local t = {}
   t[1] = { { value = "d", suit = "red" }, { value = 4, suit = "red" } }
   for i = 2, 8 do t[i] = { { value = 4, suit = "red" } } end
   return { tableau = t, foundation = { red = 1, blue = 1, green = 1 },
            free_cells = { { card = { value = 5, suit = "red" } },
                           { card = { value = 5, suit = "blue" } },
                           { card = { value = 5, suit = "green" } } },
            flower = true }
end

H.test("hint: мёртвая доска даёт stuck, а не пустую подсказку", function(rules)
   local state = bridge.from_game(dead_snapshot())
   if #rules.legal_moves(state) ~= 0 then
      return false, "доска-оракул перестала быть мёртвой — тест проверяет не то"
   end
   local h, status = hint.find(state)
   return h == nil and status == "stuck", "status = " .. tostring(status)
end)

-- Разница между «встал» и «не хватило бюджета» — продуктовая: на первом надо
-- предложить начать заново, на втором оставить прежнюю подсказку.
H.test("hint: нехватка бюджета даёт timeout, а не stuck", function()
   local h, status = hint.find(tutorial_state(), { budget = 50 })
   return h == nil and status == "timeout", "status = " .. tostring(status)
end)

-- Найдено стендом: сбор драконов сажает четыре карты по очереди, ячейка
-- становится blocked раньше, чем игра объявит победу, и пересчёт подсказки
-- попадает в это окно. Без отдельного статуса он читался как тупик, и поверх
-- выигранной партии на миг всплывало «ходов не осталось».
H.test("hint: собранная масть — это won, а не stuck", function()
   local snap = tutorial_snapshot()
   snap.tableau[1] = {}
   snap.tableau[3], snap.tableau[4], snap.tableau[5] = {}, {}, {}
   snap.free_cells[1] = { card = { value = "d", suit = "red" }, blocked = true }
   local h, status = hint.find(bridge.from_game(snap))
   if status ~= "won" then return false, "status = " .. tostring(status) end
   return h == nil
end)

H.test("hint: бюджета по умолчанию хватает на стартовую доску", function()
   local _, status = hint.find(tutorial_state())
   return status == "found", "status = " .. tostring(status)
end)

-- ============================================================
-- 5. Ярлык хода — источник текста подсказки
-- ============================================================

H.test("hint.kind: стопка и пустая колонка различаются", function()
   local snap = tutorial_snapshot()
   local state = bridge.from_game(snap)
   local onto_card = hint.kind(state, { type = "tableau_to_tableau", from_col = 1, to_col = 2 })
   local onto_empty = hint.kind(state, { type = "tableau_to_tableau", from_col = 1, to_col = 6 })
   if onto_card ~= "stack" then return false, "на карту -> " .. onto_card end
   if onto_empty ~= "empty_column" then return false, "в пустую -> " .. onto_empty end
   return true
end)

H.test("hint.kind: остальные типы ходов", function()
   local state = tutorial_state()
   local cases = {
      { { type = "to_foundation", from_col = 1 }, "foundation" },
      { { type = "to_foundation", from_free_cell = 2 }, "foundation" },
      { { type = "to_free_cell", from_col = 1, to_slot = 1 }, "free_cell" },
      { { type = "dragon_collect", suit = "red" }, "dragon" },
      { { type = "from_free_cell", from_slot = 1, to_col = 2 }, "stack" },
      { { type = "multi_to_tableau", from_col = 1, to_col = 7, run_start = 4, run_size = 2 }, "empty_column" },
   }
   for _, c in ipairs(cases) do
      local got = hint.kind(state, c[1])
      if got ~= c[2] then return false, c[1].type .. " -> " .. got .. ", ожидалось " .. c[2] end
   end
   return true
end)

-- ============================================================
-- 6. Канонический ключ, который экспортирует rules
-- ============================================================

-- hint.lua дедуплицирует состояния rules.state_hash. Своя копия хэша молча
-- разошлась бы с солверской при первом новом поле состояния — здесь держится
-- сам факт экспорта и то, ради чего он нужен: перестановка колонок схлопывается.
H.test("rules.state_hash: экспортирован и канонизирует перестановку колонок", function(rules)
   if type(rules.state_hash) ~= "function" then return false, "rules.state_hash не экспортирован" end
   local a = tutorial_snapshot()
   local b = tutorial_snapshot()
   b.tableau[3], b.tableau[7] = b.tableau[7], b.tableau[3]
   local ha = rules.state_hash(bridge.from_game(a))
   local hb = rules.state_hash(bridge.from_game(b))
   if ha ~= hb then return false, "перестановка колонок дала разные ключи" end
   local c = tutorial_snapshot()
   c.foundation.red = 2
   if ha == rules.state_hash(bridge.from_game(c)) then
      return false, "разные основания дали ОДИН ключ — ключ слеп"
   end
   return true
end)

return H
