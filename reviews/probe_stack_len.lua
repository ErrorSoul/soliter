-- probe_stack_len.lua — сколько карт может накопиться в одной колонке tableau
-- и влезает ли это в экран при текущей раскладке.
--
-- Запуск: lua reviews/probe_stack_len.lua [--seeds N] [--beam W] [--depth D]
--
-- Три независимых замера:
--   A. АНАЛИТИКА  — потолок по правилам (без перебора).
--   B. СЛУЧАЙНАЯ ИГРА — что реально набегает у обычного игрока.
--   C. ЛУЧЕВОЙ ПОИСК — целенаправленно строим самую длинную колонку.
--   D. ГЕОМЕТРИЯ  — где карта вылезает за экран при шаге 35 px.
--
-- ВАЖНО про модель форс-ходов: настоящая игра (tableau_script.last_card_to_slot)
-- авто-отправляет в foundation ТОЛЬКО двойку, цветок и дракона-в-счётчик. Она НЕ
-- играет «безопасные» карты сама, в отличие от rules.apply_mandatory. Поэтому
-- здесь свой forced() — иначе замер мерил бы не ту игру.

package.path = "solver/?.lua;" .. package.path
local rules = require("rules")
io.stdout:setvbuf("line")   -- иначе при запуске в фон вывод копится в буфере

local args = {}
for i = 1, #arg do args[#args + 1] = arg[i] end
local function opt(name, default)
   for i = 1, #args - 1 do
      if args[i] == name then return tonumber(args[i + 1]) or default end
   end
   return default
end
local SEEDS = opt("--seeds", 40)
local BEAM  = opt("--beam", 240)
local DEPTH = opt("--depth", 160)

-- ============================================================
-- Форс-ходы РЕАЛЬНОЙ игры: только верхняя двойка улетает в foundation,
-- цветок — в свой слот. Дракон в счётчик игру не меняет.
-- ============================================================
local function forced(state)
   local s = state
   local moved = true
   while moved do
      moved = false
      for col = 1, 8 do
         local c = s.tableau[col]
         local top = c[#c]
         if top then
            if type(top.value) == "number" and top.value == 2
               and s.foundation_top[top.suit] == 1 then
               s = rules.apply_move(s, { type = "to_foundation", from_col = col })
               moved = true
               break
            elseif top.is_flower and not s.flower_slot.occupied then
               s = rules.apply_move(s, { type = "to_flower", from_col = col })
               moved = true
               break
            end
         end
      end
   end
   return s
end

local function max_col(state)
   local m = 0
   for i = 1, 8 do
      local n = #state.tableau[i]
      if n > m then m = n end
   end
   return m
end

local function key(state)
   local parts = {}
   for i = 1, 8 do
      local col = state.tableau[i]
      local t = {}
      for j = 1, #col do
         t[j] = tostring(col[j].value) .. (col[j].suit or "")
      end
      parts[#parts + 1] = table.concat(t, ",")
   end
   parts[#parts + 1] = state.foundation_top.red .. "/" .. state.foundation_top.blue
                       .. "/" .. state.foundation_top.green
   for _, fc in ipairs(state.free_cells) do
      parts[#parts + 1] = fc.card
         and (tostring(fc.card.value) .. (fc.card.suit or "") .. (fc.is_blocked and "!" or ""))
         or "-"
   end
   return table.concat(parts, "|")
end

-- ============================================================
-- B. Случайная легальная игра
-- ============================================================
local function random_play(seed, steps)
   math.randomseed(seed * 7919 + 13)
   local s = forced(rules.deal(seed))
   local best = max_col(s)
   for _ = 1, steps do
      local mv = rules.legal_moves(s)
      if #mv == 0 then break end
      s = forced(rules.apply_move(s, mv[math.random(1, #mv)]))
      local m = max_col(s)
      if m > best then best = m end
   end
   return best
end

-- ============================================================
-- C. Лучевой поиск: максимизируем длину самой длинной колонки
-- ============================================================
local function beam_longest(seed)
   local start = forced(rules.deal(seed))
   local beam = { start }
   local best = max_col(start)
   local seen = { [key(start)] = true }

   for _ = 1, DEPTH do
      local next_states = {}
      for _, s in ipairs(beam) do
         for _, mv in ipairs(rules.legal_moves(s)) do
            -- Отправка числовой карты в foundation укорачивает стол — для нашей
            -- цели это шаг назад, но полностью запрещать нельзя: без разбора
            -- foundation не освободить карты. Разрешаем, поиск сам отсеет.
            local ns = forced(rules.apply_move(s, mv))
            local k = key(ns)
            if not seen[k] then
               seen[k] = true
               next_states[#next_states + 1] = ns
            end
         end
      end
      if #next_states == 0 then break end
      table.sort(next_states, function(a, b) return max_col(a) > max_col(b) end)
      beam = {}
      for i = 1, math.min(BEAM, #next_states) do beam[i] = next_states[i] end
      local m = max_col(beam[1])
      if m > best then best = m end
   end
   return best
end

-- ============================================================
-- D. Геометрия текущей раскладки
-- ============================================================
local SLOT_Y, CARD_H, PITCH, SCREEN_H = 299, 150, 35, 540
local function geometry()
   print("D. ГЕОМЕТРИЯ (slot y=" .. SLOT_Y .. ", карта " .. CARD_H
         .. " px, шаг " .. PITCH .. " px, экран 0.." .. SCREEN_H .. ")")
   print("  n | центр посл. | низ  | верх | состояние последней (=хватаемой) карты")
   for n = 5, 13 do
      local cy = SLOT_Y - PITCH * (n - 1)
      local bot, top = cy - CARD_H / 2, cy + CARD_H / 2
      local st
      if bot >= 0 then st = "видна целиком"
      elseif top <= 0 then st = "ПОЛНОСТЬЮ ЗА ЭКРАНОМ — не взять"
      else st = string.format("обрезана, видно %d px", math.floor(top)) end
      print(string.format("%3d | %11d | %4d | %4d | %s", n, cy, bot, top, st))
   end
   local span = SLOT_Y + CARD_H / 2   -- от верхнего края карты до y=0
   print(string.format("  Доступная высота под колонку: %d px", span))
   for _, n in ipairs({ 8, 10, 12, 13 }) do
      print(string.format("  Чтобы влезло %d карт, шаг должен быть <= %.2f px",
                          n, (span - CARD_H) / (n - 1)))
   end
end

-- ============================================================
print("A. АНАЛИТИКА")
print("  Раздача: 8 колонок по 5 карт. Ранги 2..10, 3 масти.")
print("  На верх колонки можно класть только строго убывающую последовательность")
print("  разных мастей (tableau_script.can_stack_cards).")
print("  Верхняя РАЗДАННАЯ карта не может быть двойкой: двойка, оказавшись сверху,")
print("  улетает в foundation сама (last_card_to_slot). По той же причине двойка")
print("  не может ЛЕЖАТЬ в конце достроенной последовательности.")
print("  => максимальная достройка: 9,8,7,6,5,4,3 на раздатую 10 = 7 карт.")
print("  ПОТОЛОК УСТОЙЧИВЫЙ: 5 + 7 = 12 карт.")
print("  ПОТОЛОК МГНОВЕННЫЙ: 13 — двойку можно положить на тройку, и она видна")
print("  на экране один кадр + время полёта, пока её не забрал foundation.")
print("")

print("B. СЛУЧАЙНАЯ ЛЕГАЛЬНАЯ ИГРА (" .. SEEDS .. " сидов x 400 ходов)")
local hist, bmax = {}, 0
for seed = 1, SEEDS do
   local m = random_play(seed, 400)
   hist[m] = (hist[m] or 0) + 1
   if m > bmax then bmax = m end
end
for n = 5, 13 do
   if hist[n] then print(string.format("  максимум %2d карт: %d партий", n, hist[n])) end
end
print("  худший случай при случайной игре: " .. bmax)
print("")

print("C. ЛУЧЕВОЙ ПОИСК на длину (beam=" .. BEAM .. ", depth=" .. DEPTH .. ")")
local cmax, cseed = 0, nil
local chist = {}
local nseeds = math.min(SEEDS, 12)
for seed = 1, nseeds do
   local m = beam_longest(seed)
   chist[m] = (chist[m] or 0) + 1
   if m > cmax then cmax, cseed = m, seed end
   io.write(string.format("  seed %2d -> %2d\n", seed, m))
end
print("  лучший найденный: " .. cmax .. " (seed " .. tostring(cseed) .. ")")
print("")

geometry()
