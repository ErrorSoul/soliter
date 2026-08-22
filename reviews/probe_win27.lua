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

-- Кнопка сбора горит, когда 4 дракона масти ОТКРЫТЫ: верхушки колонок плюс
-- незапечатанные ячейки (rules.compute_dragon_counter, C1). Авто-сбор жмёт
-- только горящие кнопки и НЕ умеет сдвинуть дракона, чтобы открыть следующего.
-- Значит вопрос: бывает ли на foundation=27 масть, у которой открыто < 4?
-- Если да — авто-сбор один партию не доигрывает, и без запасного выхода игрок
-- останется без победы вообще (регрессия хуже исходного бага).
local function exposed_by_suit(s)
   local dc = { red = 0, blue = 0, green = 0 }
   for i = 1, 8 do
      local col = s.tableau[i]
      if #col > 0 and col[#col].value == "d" then
         dc[col[#col].suit] = dc[col[#col].suit] + 1
      end
   end
   for _, fc in ipairs(s.free_cells) do
      if fc.card and fc.card.value == "d" and not fc.is_blocked then
         dc[fc.card.suit] = dc[fc.card.suit] + 1
      end
   end
   return dc
end

local function dragons_by_suit(s)
   local n = { red = 0, blue = 0, green = 0 }
   for i = 1, 8 do
      for _, c in ipairs(s.tableau[i]) do
         if c.value == "d" then n[c.suit] = n[c.suit] + 1 end
      end
   end
   for _, fc in ipairs(s.free_cells) do
      if fc.card and fc.card.value == "d" and not fc.is_blocked then
         n[fc.card.suit] = n[fc.card.suit] + 1
      end
   end
   return n
end

local checked, solved, early_win = 0, 0, 0
local stalled, no_button = 0, 0
local stall_examples = {}
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
            hit = { step = i, dragons = dragons_alive(s), total = #moves,
                    exposed = exposed_by_suit(s), left = dragons_by_suit(s) }
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
         -- масть, у которой драконы остались, но открыто меньше четырёх:
         -- её кнопка не горит, авто-сбор эту масть не возьмёт
         local any_button = false
         local dark = {}
         for _, suit in ipairs({ "red", "blue", "green" }) do
            if hit.left[suit] > 0 then
               if hit.exposed[suit] >= 4 then
                  any_button = true
               else
                  dark[#dark + 1] = string.format("%s: открыто %d из %d",
                     suit, hit.exposed[suit], hit.left[suit])
               end
            end
         end
         if #dark > 0 then
            stalled = stalled + 1
            if #stall_examples < 6 then
               stall_examples[#stall_examples + 1] = string.format(
                  "seed %d: %s%s", seed, table.concat(dark, "; "),
                  any_button and " (но другая масть собирается)" or " — НИ ОДНОЙ горящей кнопки")
            end
         end
         if not any_button then no_button = no_button + 1 end
      end
   end
end

print(string.format("раздач проверено: %d, решено: %d", checked, solved))
print(string.format("из решённых: %d партий доходят до foundation=27 ПРИ ЖИВЫХ драконах", early_win))
for _, e in ipairs(examples) do print("  " .. e) end
print(string.format("из них: %d партий с мастью, у которой кнопка НЕ горит (открыто <4)", stalled))
print(string.format("из них: %d партий, где не горит НИ ОДНА кнопка — авто-сбор не сделает ничего", no_button))
for _, e in ipairs(stall_examples) do print("  " .. e) end
if early_win == 0 then
   print("ВЫВОД: недостижимо на этой выборке — находка теоретическая")
else
   print("ВЫВОД: достижимо — игра объявит победу, пока драконы ещё на столе")
end
