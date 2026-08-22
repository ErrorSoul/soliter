-- test_layout.lua — геометрический инвариант раскладки (G6).
--
-- Проверяем не «кнопка стоит в точке X», а то, ЧЕГО мы на самом деле хотим:
-- ни одна кнопка интерфейса не перекрывает ни одну карту. Именно это и было
-- сломано до G6 — restart_button (855,30) размером 150x40 лежал поверх низа
-- колонок 6–8, и нижняя карта длинной колонки (единственная, которую можно
-- взять) оказывалась под кнопкой.
--
-- Числа берутся из НАСТОЯЩИХ файлов проекта (gui/ui.gui и коллекции), а не из
-- копии в тесте: иначе тест зазеленеет на своей копии, пока игра разъезжается.
-- Запускать из корня репозитория (как и весь run_all.lua).

local new_harness = require("solver.tests.harness")
local stub = require("solver.tests.defold_stub")
local H = new_harness()

stub.install()
local config = require("main.Scripts.config")

local CARD_W, CARD_H = 90, 150
local MAX_COLUMN = 12   -- потолок длины колонки, замерено в reviews/probe_stack_len.lua
local RAIL_LEFT = 868   -- рельс дизайна: right:14px, width:78px

local function read(path)
   local f = io.open(path, "r")
   if not f then error("не открывается " .. path .. " (тест запускают из корня репозитория)") end
   local s = f:read("*a")
   f:close()
   return s
end

-- ---------------------------------------------------------------- парсеры

-- Инстансы коллекции: id + position{x,y}
local function parse_collection(path)
   local out = {}
   for id, x, y in read(path):gmatch('id: "([^"]+)"%s*\n%s*prototype: "[^"]*"%s*\n%s*position%s*{%s*\n%s*x: ([-%d.]+)%s*\n%s*y: ([-%d.]+)') do
      out[id] = { x = tonumber(x), y = tonumber(y) }
   end
   return out
end

-- Ноды gui: id + position{} + size{}. Пропущенная координата в protobuf-text
-- означает 0, поэтому x/y читаем по отдельности и подставляем 0.
local function parse_gui(path)
   local src = read(path)
   local out = {}
   for chunk in src:gmatch("\nnodes%s*{(.-)\n}") do
      local id = chunk:match('\n%s*id: "([^"]+)"')
      if id then
         local pos = chunk:match("position%s*{(.-)}") or ""
         local size = chunk:match("size%s*{(.-)}") or ""
         out[id] = {
            x = tonumber(pos:match("x:%s*([-%d.]+)")) or 0,
            y = tonumber(pos:match("y:%s*([-%d.]+)")) or 0,
            w = tonumber(size:match("x:%s*([-%d.]+)")) or 0,
            h = tonumber(size:match("y:%s*([-%d.]+)")) or 0,
            parent = chunk:match('\n%s*parent: "([^"]+)"'),
         }
      end
   end
   return out
end

-- ---------------------------------------------------------------- геометрия

local function rect(cx, cy, w, h, name)
   return { l = cx - w / 2, r = cx + w / 2, b = cy - h / 2, t = cy + h / 2, name = name }
end

local function overlap(a, b)
   local dx = math.min(a.r, b.r) - math.max(a.l, b.l)
   local dy = math.min(a.t, b.t) - math.max(a.b, b.b)
   if dx > 0 and dy > 0 then return dx, dy end
   return nil
end

-- Прямоугольник, который заметает колонка длиной n карт: от верха первой карты
-- до низа последней при том шаге, который выдаст игра на этой длине.
local function column_rect(slot, n, name)
   local pitch = config.stack_offset_y(n, slot.y)   -- отрицательный
   local top = slot.y + CARD_H / 2
   local bottom = slot.y + (n - 1) * pitch - CARD_H / 2
   return { l = slot.x - CARD_W / 2, r = slot.x + CARD_W / 2, b = bottom, t = top, name = name }
end

-- Всё, что игрок должен видеть и хватать: 8 колонок на максимальной длине,
-- служебный ряд и кнопки драконов.
local function board_rects(coll)
   local out = {}
   for i = 1, 8 do
      local slot = coll["tableau_slot" .. i]
      if not slot then error("нет tableau_slot" .. i .. " в коллекции") end
      out[#out + 1] = column_rect(slot, MAX_COLUMN, "колонка " .. i)
   end
   for _, id in ipairs({ "free_slot1", "free_slot2", "free_slot3",
                         "base_slot1", "base_slot2", "base_slot3", "flower_slot" }) do
      local s = coll[id]
      if s then out[#out + 1] = rect(s.x, s.y, CARD_W, CARD_H, id) end
   end
   for i = 1, 3 do
      local s = coll["dragon_button" .. i]
      if s then out[#out + 1] = rect(s.x, s.y, config.BTN_SIZE.x, config.BTN_SIZE.y, "dragon_button" .. i) end
   end
   return out
end

local UI_NODES = { "restart_button", "tutorial_button", "hud_rail" }

local function ui_rects(gui)
   local out = {}
   for _, id in ipairs(UI_NODES) do
      local n = gui[id]
      if not n then error("нет ноды " .. id .. " в gui/ui.gui") end
      if n.parent then error(id .. " стал дочерним у " .. n.parent ..
         " — тест считает координаты как абсолютные, проверку надо переписать") end
      out[#out + 1] = rect(n.x, n.y, n.w, n.h, id)
   end
   return out
end

-- ---------------------------------------------------------------- тесты

H.test("G6 ни одна кнопка интерфейса не перекрывает карту", function()
   local coll = parse_collection("main/Levels/soliter.collection")
   local board = board_rects(coll)
   local ui = ui_rects(parse_gui("gui/ui.gui"))
   local hits = {}
   for _, u in ipairs(ui) do
      for _, b in ipairs(board) do
         local dx, dy = overlap(u, b)
         if dx then
            hits[#hits + 1] = string.format("%s перекрывает %s на %.0fx%.0f px", u.name, b.name, dx, dy)
         end
      end
   end
   if #hits > 0 then return false, table.concat(hits, "; ") end
   return true
end)

H.test("G6 обе коллекции раскладывают слоты одинаково", function()
   local a = parse_collection("main/Levels/soliter.collection")
   local b = parse_collection("main/Levels/soliter1.collection")
   for id, pa in pairs(a) do
      local pb = b[id]
      if pb then
         if math.abs(pa.x - pb.x) > 0.01 or math.abs(pa.y - pb.y) > 0.01 then
            return false, string.format("%s: soliter (%g,%g) vs soliter1 (%g,%g)", id, pa.x, pa.y, pb.x, pb.y)
         end
      elseif id ~= "background" then
         return false, id .. " есть в soliter.collection, но нет в soliter1.collection"
      end
   end
   return true
end)

H.test("G6 поле не залезает в рельс, а рельс не залезает в поле", function()
   local coll = parse_collection("main/Levels/soliter.collection")
   local right = -math.huge
   for _, r in ipairs(board_rects(coll)) do
      if r.r > right then right = r.r end
   end
   if right > RAIL_LEFT then
      return false, string.format("правый край поля %g заходит за левый край рельса %d", right, RAIL_LEFT)
   end
   local gui = parse_gui("gui/ui.gui")
   for _, id in ipairs(UI_NODES) do
      local n = gui[id]
      if n.x - n.w / 2 < RAIL_LEFT then
         return false, string.format("%s начинается на x=%g, левее рельса (%d)", id, n.x - n.w / 2, RAIL_LEFT)
      end
      if n.x + n.w / 2 > config.DISPLAY_WIDTH then
         return false, string.format("%s уезжает за правую кромку: x=%g", id, n.x + n.w / 2)
      end
   end
   return true
end)

H.test("G6 колонка на 12 карт целиком помещается по вертикали", function()
   local coll = parse_collection("main/Levels/soliter.collection")
   for i = 1, 8 do
      local r = column_rect(coll["tableau_slot" .. i], MAX_COLUMN, "колонка " .. i)
      if r.b < 0 then
         return false, string.format("%s: низ последней карты на y=%.1f, за нижней кромкой", r.name, r.b)
      end
      if r.t > config.DISPLAY_HEIGHT then
         return false, string.format("%s: верх колонки на y=%.1f, за верхней кромкой", r.name, r.t)
      end
   end
   return true
end)

H.test("G6 элементы поля не наезжают друг на друга", function()
   -- Сетку сжимали вручную, а служебный ряд ещё и переставляли (цветок уехал
   -- в колонку 4, кнопки драконов — в 5). Ошибка на одну колонку даст наложение,
   -- которое глазами на скриншоте легко не заметить.
   local board = board_rects(parse_collection("main/Levels/soliter.collection"))
   for i = 1, #board do
      for j = i + 1, #board do
         local dx, dy = overlap(board[i], board[j])
         if dx then
            return false, string.format("%s и %s накладываются на %.0fx%.0f px",
               board[i].name, board[j].name, dx, dy)
         end
      end
   end
   return true
end)

H.test("G6 клик по игровой кнопке не проваливается в игру", function()
   local src = read("gui/ui.gui_script")
   -- Ветка кнопки обязана и проверять is_enabled (pick_node — чистая геометрия,
   -- по выключенной ноде он тоже попадает), и возвращать true, иначе тот же тап
   -- уедет в курсор и начнёт драг карты под кнопкой.
   local block = src:match("(Игровые кнопки.*)$")
   if not block then return false, "не нашёл блок «Игровые кнопки» в on_input" end
   for _, id in ipairs({ "restart_button", "tutorial_button" }) do
      local branch = block:match('(gui%.get_node%("' .. id .. '"%).-\n%s*end)')
      if not branch then return false, "не нашёл ветку " .. id end
      if not branch:match("is_enabled") then
         return false, id .. ": нет проверки gui.is_enabled — тап по выключенной кнопке сработает"
      end
      if not branch:match("return true") then
         return false, id .. ": нет return true — клик уйдёт и в кнопку, и в карту"
      end
   end
   return true
end)

return H
