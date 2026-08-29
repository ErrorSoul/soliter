-- O2: авто-завершение должно спрашивать «доиграется ли доска ПОВТОРНЫМИ съёмами»,
-- а не «безопасна ли каждая карта по ТЕКУЩИМ основаниям».
--
-- Старый предикат делал один проход по всем оставшимся картам и требовал
-- v <= min_other + 1 по основаниям на момент проверки. Но сметание забирает
-- карты по одной и на каждом шаге ПОДНИМАЕТ основание, поэтому одноразовая
-- проверка отвергает доски, которые доигрываются полностью. Здесь это
-- зафиксировано на живой доске игрока (скриншот 2026-08-29).

local new_harness = require("solver.tests.harness")
local H = new_harness()

local R, G, B = "red", "green", "blue"

local function n(suit, v) return { value = v, suit = suit } end
local function dragon(suit) return { value = "d", suit = suit, is_dragon = true } end
local function flower() return { value = "f", suit = "flower", is_flower = true } end

-- state с восемью колонками; недостающие — пустые.
local function board(cols, cells, foundation)
   local tableau = {}
   for i = 1, 8 do tableau[i] = cols[i] or {} end
   return {
      tableau = tableau,
      free_cells = cells or { {}, {}, {} },
      foundation_top = foundation,
   }
end

-- Три собранные (запечатанные) стопки драконов — как на скриншоте.
local function sealed_cells()
   return {
      { card = dragon(B), is_blocked = true },
      { card = dragon(G), is_blocked = true },
      { card = dragon(R), is_blocked = true },
   }
end

-- ДОСКА-РЕГРЕССИЯ: скриншот пользователя. Драконы собраны, ячейки запечатаны,
-- цветок в своём слоте, основания 2/2/4, на столе 22 карты. Партия доигрывается
-- жадным съёмом верхушек целиком (замер: 22 хода, основания 10/10/10), но
-- старый предикат падал на первой же карте обхода — 10 синей в первой колонке
-- (min_other = 2, значит потолок 3).
local function screenshot_board()
   return board({
      { n(B, 10) },
      { n(R, 10), n(B, 9), n(R, 8), n(G, 7), n(R, 6), n(B, 5), n(R, 4), n(G, 3) },
      { n(G, 5) },
      { n(R, 5), n(G, 4), n(R, 3) },
      {},
      {},
      { n(G, 9), n(B, 8), n(R, 7), n(B, 6) },
      { n(G, 10), n(R, 9), n(G, 8), n(B, 7), n(G, 6) },
   }, sealed_cells(), { red = 2, green = 2, blue = 4 })
end

H.test("O2 доска со скриншота: авто-завершение обязано запуститься", function(rules)
   if not rules.can_auto_finish(screenshot_board()) then
      return false, "доигранная доска (22 карты, сметается подчистую) отвергнута предикатом"
   end
   return true
end)

-- Негатив, который начинает сметать и ЗАСТРЕВАЕТ. Тривиально-небезопасная доска
-- зеленела бы и при сломанной симуляции, поэтому здесь первые два хода честно
-- проходят: 2_red, 3_red уходят, а колонка [2_blue, 3_blue] встаёт — сверху
-- тройка, а основание синей ждёт двойку, и достать её нечем.
H.test("O2 сметание, которое застревает на середине, запускать нельзя", function(rules)
   local st = board({
      { n(R, 3), n(R, 2) },
      { n(B, 2), n(B, 3) },
   }, nil, { red = 1, green = 1, blue = 1 })
   if rules.can_auto_finish(st) then
      return false, "авто-финиш стартовал на доске, где сметание встаёт через два хода"
   end
   return true
end)

-- Тот же набор карт в порядке, который сметается: доказывает, что предыдущий
-- тест зеленеет не от «выключено всегда».
H.test("O2 те же карты в снимаемом порядке — запускается", function(rules)
   local st = board({
      { n(R, 3), n(R, 2) },
      { n(B, 3), n(B, 2) },
   }, nil, { red = 1, green = 1, blue = 1 })
   if not rules.can_auto_finish(st) then
      return false, "предикат отверг доску, которая снимается двумя парами верхушек"
   end
   return true
end)

-- Симуляция обязана поднимать ОСНОВАНИЕ по ходу дела. Колонка 2..10 одной масти
-- снимается только так: при проверке по стартовым основаниям 10 недостижима.
H.test("O2 длинный ран одной масти снимается за счёт роста основания", function(rules)
   local col = {}
   for v = 10, 2, -1 do col[#col + 1] = n(R, v) end   -- снизу 10, сверху 2
   local st = board({ col }, nil, { red = 1, green = 1, blue = 1 })
   if not rules.can_auto_finish(st) then
      return false, "ран 10..2 одной масти отвергнут — предикат всё ещё смотрит одним проходом"
   end
   return true
end)

-- Открытость обязательна (гард G3): все карты «безопасны», но верхушка не та.
H.test("O2 карта, закопанная под своей же старшей, не считается снимаемой", function(rules)
   local st = board({
      { n(R, 9), n(R, 10) },   -- сверху 10, основание ждёт 9
   }, nil, { red = 8, green = 9, blue = 9 })
   if rules.can_auto_finish(st) then
      return false, "предикат посчитал закопанную девятку доступной"
   end
   return true
end)

-- Живая карта в ячейке — такой же кандидат, как верхушка колонки (L2).
H.test("O2 номинал в живой ячейке досматривается до конца", function(rules)
   local st = board({
      { n(R, 3), n(R, 2) },
   }, {
      { card = n(R, 4) }, {}, {},
   }, { red = 1, green = 1, blue = 1 })
   if not rules.can_auto_finish(st) then
      return false, "четвёрка в ячейке снимается после колонки, но предикат сказал нет"
   end
   return true
end)

H.test("O2 несыгрываемый номинал в живой ячейке блокирует запуск", function(rules)
   local st = board({
      { n(R, 3), n(R, 2) },
   }, {
      { card = n(B, 5) }, {}, {},   -- синяя пятёрка: основание синей так и останется на 1
   }, { red = 1, green = 1, blue = 1 })
   if rules.can_auto_finish(st) then
      return false, "авто-финиш стартовал, хотя карту из ячейки девать некуда"
   end
   return true
end)

-- Цветок в живой ячейке победе мешает, а разбору колонок — нет (L2).
H.test("O2 цветок в живой ячейке не запрещает разбор колонок", function(rules)
   local st = board({
      { n(R, 3), n(R, 2) },
   }, {
      { card = flower() }, {}, {},
   }, { red = 1, green = 1, blue = 1 })
   if not rules.can_auto_finish(st) then
      return false, "припаркованный цветок запретил авто-финиш целиком"
   end
   return true
end)

H.test("O2 живой дракон в ячейке по-прежнему запрещает авто-финиш", function(rules)
   local st = board({
      { n(R, 3), n(R, 2) },
   }, {
      { card = dragon(R), is_blocked = false }, {}, {},
   }, { red = 1, green = 1, blue = 1 })
   if rules.can_auto_finish(st) then
      return false, "гард по живому дракону потерян"
   end
   return true
end)

H.test("O2 дракон на столе запрещает авто-финиш", function(rules)
   local st = board({
      { n(R, 2) },
      { dragon(G) },
   }, nil, { red = 1, green = 1, blue = 1 })
   if rules.can_auto_finish(st) then
      return false, "авто-финиш стартовал при неубранном драконе на столе"
   end
   return true
end)

H.test("O2 пустой стол авто-финиш не запускает", function(rules)
   local st = board({}, nil, { red = 10, green = 10, blue = 10 })
   if rules.can_auto_finish(st) then
      return false, "нечего доигрывать, а предикат разрешил"
   end
   return true
end)

return H
