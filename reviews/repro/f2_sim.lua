-- F2 differential simulation: run the real free_cell.script + dragon_button.script
-- through BOTH dragon-collect landing orders and read the resulting free_slots_counter.
--
--   Ordering A — collect into an EMPTY free cell
--   Ordering B — collect into the cell that already holds a parked dragon of that suit
--                (cursor.script:533-539 prefers exactly this cell)
--
-- Usage: lua reviews/repro/f2_sim.lua <path-to-free_cell.script> <label>
package.path = "/Users/abu/works/ShenzenSolitare/?.lua;" .. package.path

local FREE_CELL = arg[1]
local LABEL     = arg[2] or "?"
local BUTTON    = "/Users/abu/works/ShenzenSolitare/main/Scripts/dragon_button.script"

-- ---------- Defold stubs ----------
_G.hash = function(s) return "#" .. tostring(s) end
local v3mt = {}
_G.vmath = {
   vector3 = function(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, v3mt) end,
   vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
}
v3mt.__add = function(a, b) return _G.vmath.vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
_G.sprite = { set_constant = function() end }
_G.sound  = { play = function() end }
_G.timer  = { delay = function() end }
_G.go = {
   get_id = function() return "self_go" end,
   get_position = function() return _G.vmath.vector3(0, 0, 0) end,
   set_position = function() end,
   animate = function() end,
   cancel_animations = function() end,
   set = function() end,
}

-- ---------- message bus ----------
local entities, queue = {}, {}
_G.msg = {}
function _G.msg.post(to, id, data)
   queue[#queue + 1] = { to = tostring(to), id = tostring(id), data = data or {} }
end
local function pump()
   local guard = 0
   while #queue > 0 do
      guard = guard + 1
      if guard > 10000 then error("message storm") end
      local m = table.remove(queue, 1)
      local t = entities[m.to] or entities[(m.to:gsub("^#", ""))]
      if t and t.env.on_message then
         -- Defold delivers the message id as a hash; msg.post takes a string
         t.env.on_message(t.self, hash(m.id), m.data, "sim")
      end
   end
end

local TRACE = { red = "dragon_button1", blue = "dragon_button2", green = "dragon_button3" }

local function spawn(id, path)
   local env = setmetatable({}, { __index = _G })
   assert(loadfile(path, "t", env))()
   local s = {}
   if env.init then env.init(s) end
   entities[id] = { env = env, self = s }
   return entities[id]
end

local function build_board()
   entities, queue = {}, {}
   for i = 1, 3 do
      local e = spawn("free_slot" .. i, FREE_CELL)
      e.self.cursor = "cursor"
      e.self.slot_id = "free_slot" .. i
      e.self.dragon_button_trace = TRACE
   end
   for suit, id in pairs(TRACE) do
      local e = spawn(id, BUTTON)
      e.self.sprite = suit; e.self.default_sprite = suit .. "_grey"
      e.self.cursor = "cursor"; e.self.slot_id = id
   end
end

local function counter(suit) return entities[TRACE[suit]].self.free_slots_counter end
local function dragon(suit, n) return { id = "d_" .. suit .. n, data = { value = "d", suit = suit } } end
local function land(cell, card, complete)
   entities[cell].env.on_message(entities[cell].self, hash("occupy_slot"),
      { card = card, position = _G.vmath.vector3(0, 0, 0), animation = false, complete = complete }, "card")
   pump()
end
local function row(tag)
   return ("   %-16s red=%d blue=%d green=%d"):format(tag, counter("red"), counter("blue"), counter("green"))
end

print(("==== %s ===="):format(LABEL))

-- ---------------- Ordering A: collect into an EMPTY cell ----------------
build_board()
print("Ordering A — 4 red dragons land in the EMPTY free_slot1")
print(row("start"))
for i = 1, 4 do land("free_slot1", dragon("red", i), true) end
print(row("after collect"))
land("free_slot2", dragon("blue", 1), nil)
print(row("after blue park"))
local gA = counter("green")

-- ---------------- Ordering B: collect into the parked dragon's own cell ----------------
build_board()
print("Ordering B — one red dragon is parked first, then all 4 land on that same cell")
print(row("start"))
land("free_slot1", dragon("red", 1), nil)             -- manual park (complete = nil)
print(row("after red park"))
for i = 1, 4 do land("free_slot1", dragon("red", i), true) end
print(row("after collect"))
land("free_slot2", dragon("blue", 1), nil)
print(row("after blue park"))
local gB = counter("green")

-- ---------------- verdict ----------------
-- Ground truth in both orderings: free_slot1 is blocked, free_slot2 holds a blue dragon,
-- free_slot3 is empty => green must still see >= 1 usable cell.
print(("\nfree_slot3 empty & unblocked -> green MUST have >=1 usable cell"))
print(("   ordering A: green=%d  %s"):format(gA, gA > 0 and "OK" or "BUG (button dead)"))
print(("   ordering B: green=%d  %s"):format(gB, gB > 0 and "OK" or "BUG (button dead)"))
if gA ~= gB then
   print("   -> the two landing orders DIVERGE")
else
   print("   -> the two landing orders converge")
end
