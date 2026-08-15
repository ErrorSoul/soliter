-- A6-extension differential sim for `pending_top_check = true` in tableau occupy_slot.
--
--   Scenario 1 — does it RE-COUNT a dragon that is moved to an empty column?
--   Scenario 2 — does it fix auto-send of a 2 / flower PLACED onto a column?
--
-- Usage: lua reviews/repro/a6_sim.lua <path-to-tableau_script.script> <label>
package.path = "/Users/abu/works/ShenzenSolitare/?.lua;" .. package.path

local TABLEAU = arg[1]
local LABEL   = arg[2] or "?"
local BUTTON  = "/Users/abu/works/ShenzenSolitare/main/Scripts/dragon_button.script"

_G.hash  = function(s) return "#" .. tostring(s) end
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

local entities, queue = {}, {}
_G.msg = {}
function _G.msg.post(to, id, data)
   queue[#queue + 1] = { to = tostring(to), id = tostring(id), data = data or {} }
end

-- cursor sink: records everything the tableau/buttons send to the cursor
local cursor_log = {}
entities["cursor"] = { env = { on_message = function(_, id, data)
   cursor_log[#cursor_log + 1] = { id = tostring(id):gsub("^#", ""), data = data }
end }, self = {} }
local function cursor_got(id)
   for _, m in ipairs(cursor_log) do if m.id == id then return true end end
   return false
end

local function spawn(id, path)
   local env = setmetatable({}, { __index = _G })
   assert(loadfile(path, "t", env))()
   local s = {}
   if env.init then env.init(s) end
   entities[id] = { env = env, self = s, id = id }
   return entities[id]
end

local function dispatch()
   for _ = 1, #queue do
      local m = table.remove(queue, 1)
      local t = entities[m.to] or entities[(m.to:gsub("^#", ""))]
      if t and t.env.on_message then t.env.on_message(t.self, hash(m.id), m.data, "sim") end
   end
end

-- one Defold-ish frame: flush messages, run every update(), flush again
local function frame()
   for _ = 1, 6 do dispatch() end
   for _, e in pairs(entities) do
      if e.env.update then e.env.update(e.self, 1 / 60) end
   end
   for _ = 1, 6 do dispatch() end
end

for i = 1, 4 do spawn("tableau" .. i, TABLEAU) end
for suit, id in pairs({ red = "dragon_button1", blue = "dragon_button2", green = "dragon_button3" }) do
   local e = spawn(id, BUTTON)
   e.self.sprite = suit; e.self.default_sprite = suit .. "_grey"
   e.self.cursor = "cursor"; e.self.slot_id = id
end

local function counter() return entities["dragon_button1"].self.counter end
local function send(col, id, data)
   entities[col].env.on_message(entities[col].self, hash(id), data, "sim")
end

local dragon = { id = "d_red_1", data = { value = "d", suit = "red" } }
local five   = { id = "5_green", data = { value = 5, suit = "green" } }
local two    = { id = "2_red",   data = { value = 2, suit = "red" } }
local flower = { id = "flower",  data = { value = "f", suit = "flower" } }

print(("==== %s ===="):format(LABEL))

-- ---------------- Scenario 1: dragon re-count ----------------
send("tableau1", "update_stack", { stack = { five, dragon }, index = 1, cursor = "cursor" })
send("tableau3", "update_stack", { stack = {}, index = 3, cursor = "cursor" })
frame()
local c_after_deal = counter()

-- player drags that same dragon from col1 onto the EMPTY col3
-- (legal: can_stack_cards rejects dragons, so an empty column is the only target)
send("tableau3", "occupy_slot", { card = dragon })
send("tableau1", "remove_card", { id = dragon.id })
frame()
local c_after_move = counter()

print(("S1 dragon counter: after deal=%d  after moving the SAME dragon=%d")
   :format(c_after_deal, c_after_move))
if c_after_move > c_after_deal then
   print("   -> BUG: one dragon counted twice (check_state needs `counter == 4` EXACTLY)")
else
   print("   -> OK: counted once")
end

-- ---------------- Scenario 2: auto-send of a PLACED 2 / flower ----------------
-- Simulates dropping a 2 (and a flower) from a free cell onto an empty column.
-- Only occupy_slot arrives at the target column -- no remove_card, no update_stack.
send("tableau2", "update_stack", { stack = {}, index = 2, cursor = "cursor" })
send("tableau4", "update_stack", { stack = {}, index = 4, cursor = "cursor" })
frame()
cursor_log = {}

send("tableau2", "occupy_slot", { card = two })
send("tableau4", "occupy_slot", { card = flower })
frame()

local got_two    = cursor_got("send_to_base_slot")
local got_flower = cursor_got("send_to_flower_slot")
print(("S2 placed 2 -> send_to_base_slot: %s | placed flower -> send_to_flower_slot: %s")
   :format(tostring(got_two), tostring(got_flower)))
if got_two and got_flower then
   print("   -> auto-send fires on placement")
else
   print("   -> auto-send does NOT fire on placement (card just sits there)")
end
