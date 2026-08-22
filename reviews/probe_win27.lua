-- Зонд к находке grok-4.5 #1: игра объявляет победу по 27 числовым картам
-- (main.script:995), а цель солвера строже — пустой стол + собранные драконы
-- (rules.lua:643). Вопрос НЕ «есть ли расхождение в коде» (оно есть), а
-- «достижимо ли состояние foundation=27 при живых драконах на столе».
-- Меряем: прогоняем решённые раздачи и ищем ПЕРВОЕ состояние, где все три
-- foundation дошли до 10. Если в нём остались драконы — находка настоящая.
package.path = "./solver/?.lua;" .. package.path
local rules = require("rules")

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

local checked, solved, early_win = 0, 0, 0
local examples = {}

for seed = 1, 60 do
   local state = rules.deal(seed)
   local moves, verdict = rules.solve(state, { node_budget = 200000 })
   checked = checked + 1
   if verdict == "solved" then
      solved = solved + 1
      local s = state
      local hit = nil
      for i, mv in ipairs(moves) do
         s = rules.apply_move(s, mv)
         if foundation_full(s) then
            hit = { step = i, dragons = dragons_alive(s), total = #moves }
            break
         end
      end
      if hit and hit.dragons > 0 then
         early_win = early_win + 1
         if #examples < 5 then
            examples[#examples + 1] = string.format(
               "seed %d: foundation=27 на ходу %d/%d, драконов ещё на столе: %d",
               seed, hit.step, hit.total, hit.dragons)
         end
      end
   end
end

print(string.format("раздач проверено: %d, решено: %d", checked, solved))
print(string.format("из решённых: %d партий доходят до foundation=27 ПРИ ЖИВЫХ драконах", early_win))
for _, e in ipairs(examples) do print("  " .. e) end
if early_win == 0 then
   print("ВЫВОД: недостижимо на этой выборке — находка теоретическая")
else
   print("ВЫВОД: достижимо — игра объявит победу, пока драконы ещё на столе")
end
