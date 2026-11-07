local H = require("solver.tests.harness")()
local stub = require("solver.tests.defold_stub")

local function script(path)
   stub.install()
   assert(loadfile(path))()
   local self = {}
   init(self)
   return self
end

H.test("Review: game_manager keeps the save when restart_level carries preserve_save", function()
   local self = script("main/Scripts/game_manager.script")
   local path = sys.get_save_file("shenzhen_solitaire", "progress")
   sys.save(path, {v = 1, data = "saved-board"})
   for _ = 1, 2 do
      on_message(self, hash("restart_level"), {preserve_save = true}, "ui")
      assert(sys.load(path).data == "saved-board", "tutorial erased progress")
   end
   on_message(self, hash("restart_level"), {}, "ui")
   assert(sys.load(path).data == "", "explicit restart must still redeal")
   return true
end)

-- The flag above is only half of the fix: the UI must send it. Real ui.gui_script,
-- real enabled-state of nodes; a tap "hits" exactly the named node.
H.test("Review: TUTORIAL, SKIP and PLAY NOW keep the save; RESTART redeals", function()
   stub.install()
   local tutorial_state = require("main.Scripts.tutorial_state")
   local enabled = {}
   _G.gui = setmetatable({
      EASING_OUTQUAD = 0, EASING_OUTBACK = 1,
      get_node = function(name) return name end,
      set_enabled = function(node, on) enabled[node] = on end,
      is_enabled = function(node) return enabled[node] ~= false end,
      new_box_node = function() return {} end,
   }, {__index = function() return function() end end})
   _G.html5 = nil
   assert(loadfile("gui/ui.gui_script"))()
   local self = {}
   init(self)
   local function tap(node)
      msg.clear()
      gui.pick_node = function(n) return n == node end
      on_input(self, hash("touch"), {pressed = true, x = 0, y = 0})
      on_input(self, hash("touch"), {released = true, x = 0, y = 0})
      local sent = {}
      for _, e in ipairs(msg.log) do
         if e.id == "restart_level" then sent[#sent + 1] = e.data.preserve_save end
      end
      if #sent ~= 1 then return tostring(#sent) .. " restart_level" end
      return sent[1]
   end
   local function win(tutorial)
      tutorial_state.is_tutorial = tutorial
      tutorial_state.show_victory = true
      update(self, 0.016)
   end
   local ok, err = pcall(function()
      assert(tap("play_button") == "0 restart_level", "PLAY must not redeal")
      assert(tap("tutorial_button") == true, "TUTORIAL erased the saved game")
      assert(tap("tutorial_skip_btn") == true, "SKIP erased the saved game")
      assert(tap("tutorial_button") == true, "second TUTORIAL erased the saved game")
      win(true)
      assert(tap("victory_restart") == true, "PLAY NOW after the tutorial erased the saved game")
      assert(tap("restart_button") == false, "RESTART must redeal")
      win(false)
      assert(tap("victory_restart") == false, "PLAY AGAIN after a real win must redeal")
   end)
   tutorial_state.reset()
   tutorial_state.is_tutorial = false
   _G.gui = nil
   assert(ok, err)
   return true
end)

H.test("Review: clearing a hint does not flatten a card held in the hand", function()
   local self = script("main/Scripts/card.script")
   on_message(self, hash("highlight"), {})
   on_message(self, hash("start_drag"), {})
   stub.go_props.scale = vmath.vector3(1.1, 1.1, 1)
   on_message(self, hash("unhighlight"), {})
   assert(stub.go_props.scale.x == 1.1, "hint cleanup flattened dragged card")
   return true
end)

H.test("Tutorial: focus ring clears on pickup and cannot reappear during drag", function()
   stub.install()
   local tint, old_set = nil, go.set
   go.set = function(url, prop, value)
      if url == "#hint" and prop == "tint.w" then tint = value end
      old_set(url, prop, value)
   end
   assert(loadfile("main/Scripts/card.script"))()
   local self = {}; init(self)
   assert(tint == 0, "focus ring visible on an ordinary card")
   on_message(self, hash("highlight"), {})
   assert(tint == 1, "hint failed to show focus ring")
   on_message(self, hash("unhighlight"), {})
   assert(tint == 0, "previous hint left its ring behind")
   on_message(self, hash("highlight"), {})
   on_message(self, hash("start_drag"), {})
   assert(tint == 0, "focus ring follows picked-up card")
   on_message(self, hash("highlight"), {})
   assert(tint == 0, "hint during drag restored focus ring")
   on_message(self, hash("drop_failed"), {position=vmath.vector3(65,159,0.03)})
   stub.flush_anims(8)
   assert(tint == 1, "rejected move lost the active tutorial hint")
   on_message(self, hash("unhighlight"), {})
   assert(tint == 0)
   return true
end)

H.test("Review: completed flower flight lands immediately", function()
   local self = script("main/Scripts/flower_slot.script")
   on_message(self, hash("occupy_slot"), {
      card = {id = "flower"}, position = vmath.vector3(377, 457, 0.2), animation = true,
   })
   assert(#stub.anim_log == 0, "flower starts a second flight after its arc")
   assert(stub.go_positions.flower and stub.go_positions.flower.z == 0.2,
      "flower was left in the flight layer")
   return true
end)

H.test("Review: simultaneous foundation arrivals have distinct final heights", function()
   local self = script("main/Scripts/base_slot.script")
   self.cursor, self.slot_id = "cursor", "base_slot1"
   for value = 2, 3 do
      on_message(self, hash("occupy_slot"), {
         card = {id = "card" .. value, data = {value = value, suit = "red"}}, animation = true,
      })
   end
   stub.flush_anims()
   assert(stub.go_positions.card2.z < stub.go_positions.card3.z,
      "arrival callbacks assigned the same height to different cards")
   return true
end)

H.test("Review: victory particles clean up on expiry, hide and final without consuming deal randomness", function()
   stub.install()
   local live, next_id, visible = {}, 0, true
   _G.gui = {
      get_node = function() return "overlay" end,
      new_box_node = function()
         next_id = next_id + 1
         live[next_id] = true
         return next_id
      end,
      delete_node = function(id) assert(live[id]); live[id] = nil end,
      is_enabled = function() return visible end,
   }
   for _, name in ipairs({"set_parent", "set_layer", "set_inherit_alpha",
      "set_enabled", "set_position", "set_rotation", "set_scale", "set_color"}) do
      gui[name] = function() end
   end
   local celebration = require("main.Scripts.celebration")
   local random = math.random
   math.random = function() error("cosmetic effect changed the deal RNG") end
   local ok, err = pcall(function()
      local self = {}
      celebration.start(self)
      assert(next_id > 0 and next_id <= 48, "particle budget exceeded")
      celebration.update(self, 0.5)
      celebration.start(self) -- repeated victory replaces the old burst
      celebration.update(self, 4)
      assert(next(live) == nil, "particles leaked after completion")
      celebration.start(self)
      visible = false
      celebration.update(self, 0.01)
      assert(next(live) == nil, "particles leaked when the overlay was hidden")
      visible = true
      celebration.start(self)
      assert(loadfile("gui/ui.gui_script"))()
      final(self)
      assert(next(live) == nil, "particles leaked in GUI final")
   end)
   math.random = random
   _G.gui = nil
   assert(ok, err)
   return true
end)

return H
