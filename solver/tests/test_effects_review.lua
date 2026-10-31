local H = require("solver.tests.harness")()
local stub = require("solver.tests.defold_stub")

local function script(path)
   stub.install()
   assert(loadfile(path))()
   local self = {}
   init(self)
   return self
end

H.test("Review: tutorial round trip preserves the normal saved game", function()
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

H.test("Review: clearing a hint does not flatten a card held in the hand", function()
   local self = script("main/Scripts/card.script")
   on_message(self, hash("highlight"), {})
   on_message(self, hash("start_drag"), {})
   stub.go_props.scale = vmath.vector3(1.1, 1.1, 1)
   on_message(self, hash("unhighlight"), {})
   assert(stub.go_props.scale.x == 1.1, "hint cleanup flattened dragged card")
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
