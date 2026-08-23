-- Есть ли доска на foundation=27, где НИ одна кнопка масти не горит И
-- dragon_relocation не находит хода? Конструируем худший случай руками.
--
-- Идея: 13 карт (12 драконов + цветок) размазаны по ВСЕМ восьми колонкам, чтобы
-- не осталось ни одной пустой (тогда сдвигать некуда), а по мастям открытых
-- драконов было 3/3/2 — ни одной четвёрки, ни одна кнопка не горит.
package.path = "./?.lua;./?/init.lua;" .. package.path
local stub = require("solver.tests.defold_stub")
stub.install()
assert(loadfile("main/Scripts/main.script"))()

local function d(suit) return { id = "go_d" .. suit .. math.random(1e6), data = { value = "d", suit = suit, is_dragon = true } } end
local function flower() return { id = "go_f", data = { value = "f", suit = "flower", is_flower = true } } end

local cols = {
   { flower(), d("red") },      -- цветок закопан под красным драконом
   { d("red") },
   { d("red") },
   { d("red"), d("blue") },     -- 4-й красный закопан
   { d("blue") },
   { d("blue") },
   { d("blue"), d("green") },   -- 4-й синий закопан
   { d("green"), d("green"), d("green") },
}

local self = {
   base_cards_count = 27,
   free_cell_state = { {}, {}, {} },      -- ячейки ПУСТЫ
   tableau_stacks = {},
   states = { WIN = "win" }, currentState = "play",
   auto_collecting = true, auto_collect_wait = 99,
   flower_collected = false, tutorial_mode = false, cursor = "cursor",
}
for i = 1, 8 do
   self.tableau_stacks[i] = { slot_id = "tableau_slot" .. i, cards = cols[i] }
end

-- Сколько драконов каждой масти ОТКРЫТО (верхушки колонок + живые ячейки)?
local exposed = { red = 0, blue = 0, green = 0 }
for i = 1, 8 do
   local c = cols[i][#cols[i]]
   if c.data.is_dragon then exposed[c.data.suit] = exposed[c.data.suit] + 1 end
end
print(string.format("открытых драконов: red=%d blue=%d green=%d  (кнопка горит при 4)",
   exposed.red, exposed.blue, exposed.green))

local empty = 0
for i = 1, 8 do if #cols[i] == 0 then empty = empty + 1 end end
print("пустых колонок: " .. empty)

local card, slot = dragon_relocation(self)
print("dragon_relocation → " .. tostring(card and (card.data.suit .. " дракон") or "НЕЧЕГО СДВИНУТЬ")
   .. (slot and (" на " .. slot) or ""))

print("dragons_left = " .. dragons_left(self) .. ", live_cells = " .. live_cells(self)
   .. ", board_cleared = " .. tostring(board_cleared(self)))

auto_collect_give_up(self)
print("после уступки: currentState = " .. tostring(self.currentState))

-- А есть ли у ИГРОКА ход на этой доске? Ячейки пусты — значит, любого верхнего
-- дракона можно положить в ячейку, открыв то, что под ним.
local player_move = (live_cells(self) < 3)
print("у игрока есть ход (свободная ячейка + верхний дракон): " .. tostring(player_move))
