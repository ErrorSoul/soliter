-- F10 lifecycle sim: is `block_play_input` really sticky, and is it always cleared?
-- Drives the REAL cursor.script on_input against the REAL tutorial_state module.
--
-- Observable: cursor.on_input updates self.cursor_pos from action.x/y *after* the guard
-- (cursor.script:38-44). So "cursor_pos moved" == input was accepted.
--
-- Usage: lua reviews/repro/f10_sim.lua
package.path = "/Users/abu/works/ShenzenSolitare/?.lua;" .. package.path

_G.hash = function(s) return "#" .. tostring(s) end
local v3mt = {}
_G.vmath = {
   vector3 = function(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, v3mt) end,
   vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
}
v3mt.__add = function(a, b) return _G.vmath.vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
v3mt.__sub = function(a, b) return _G.vmath.vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
_G.sprite = { set_constant = function() end }
_G.sound  = { play = function() end }
_G.timer  = { delay = function() end }
_G.window = { get_size = function() return 960, 540 end }
_G.go = {
   get_id = function() return "cursor" end,
   get_position = function() return _G.vmath.vector3(0, 0, 0) end,
   set_position = function() end,
   animate = function() end,
   cancel_animations = function() end,
   set = function() end,
}
local posted = {}
_G.msg = { post = function(to, id, data) posted[#posted + 1] = { to = tostring(to), id = tostring(id) } end }
_G.factory = { create = function() return "go" end }

local T = require("main.Scripts.tutorial_state")

local env = setmetatable({}, { __index = _G })
assert(loadfile("/Users/abu/works/ShenzenSolitare/main/Scripts/cursor.script", "t", env))()

local function fresh_self()
   return {
      input_disabled = false,
      cursor_pos = _G.vmath.vector3(0, 0, 0),
      is_dragging = false,
      flying_count = 0,
      base_slots = {}, free_slots = {}, dragon_buttons = {},
      tableau_stacks = {}, tableau_slots = {}, last_cards = {},
      flower_slot = {},
   }
end

-- returns true if the input was ACCEPTED (cursor position followed the pointer)
local function try_input(self, x, y)
   posted = {}
   local before_x = self.cursor_pos.x
   pcall(function()
      env.on_input(self, hash("touch"), { x = x, y = y, pressed = true })
   end)
   return self.cursor_pos.x ~= before_x or self.cursor_pos.x == x
end

local fails = 0
local function check(label, got, want)
   local ok = (got == want)
   if not ok then fails = fails + 1 end
   print(("  [%s] %-58s got=%s want=%s"):format(ok and "OK" or "FAIL", label, tostring(got), tostring(want)))
end

print("=== F10 block_play_input lifecycle (real cursor.script + tutorial_state) ===")

-- 1. baseline: input accepted
T.reset()
local s = fresh_self()
check("до победы ввод принимается", try_input(s, 100, 200), true)

-- 2. victory pulse -> blocked
T.request_victory()
check("после request_victory ввод заблокирован", try_input(s, 300, 400), false)
check("show_victory выставлен для UI", T.show_victory, true)

-- 3. UI consumes the pulse (ui.gui_script:122-123) -> must STAY blocked
T.show_victory = false
check("после того как UI съел show_victory — всё ещё блок", try_input(s, 310, 410), false)

-- 4. reset() clears it (ui.gui_script: 4 call sites)
T.reset()
check("reset() снимает блок", try_input(s, 500, 500), true)

-- 5. the other clear path: main.script init assignment (main.script:38)
T.request_victory()
check("блок снова стоит", try_input(s, 600, 600), false)
T.block_play_input = false           -- exactly what main.script init does
check("main.init снимает блок", try_input(s, 700, 700), true)

-- 6. grok-4.6's residual hole: drag in flight when victory lands
--    dragon collect arms a 1.5s timer (dragon_button.script:36-38); victory arrives only
--    then, so the player can still start a drag inside that window.
print("\n=== окно 1.5с: драг начат до победы ===")
T.reset()
local d = fresh_self()
try_input(d, 100, 100)
d.is_dragging = true                 -- player is holding a card
T.request_victory()                  -- dragons_collected lands 1.5s later
posted = {}
pcall(function()
   env.on_input(d, hash("touch"), { x = 120, y = 120, released = true })
end)
local got_resolution = false
for _, m in ipairs(posted) do
   local id = m.id:gsub("^#", "")
   if id == "drop_success" or id == "drop_failed" then got_resolution = true end
end
check("released разрешает драг (drop_success/drop_failed)", got_resolution, true)
check("карта осталась в состоянии is_dragging", d.is_dragging, true)

print(("\n%d проверок провалено"):format(fails))
print("(последние две — ожидаемо FAIL/true: это и есть дыра, найденная grok-4.6;")
print(" последствие косметическое — выгрузка коллекции при рестарте уничтожает GO)")
