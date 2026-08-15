-- Load Defold .script files under stubs and pin the game-script review bugs.

local new_harness = require("solver.tests.harness")
local stub = require("solver.tests.defold_stub")
local H = new_harness()

stub.install()

local function load_script(rel)
   local chunk, err = loadfile(rel)
   if not chunk then error(err) end
   -- .script files declare globals (init, on_message, …); isolate per load
   -- by running in this environment's _G after stubs are installed.
   chunk()
end

-- F1: foundation must reject a dragon even if value would be the next rank.
-- Today `id_dragon` is a typo (always nil) so a malformed {is_dragon, value=5}
-- on a 4 would be accepted. Guard must key off is_dragon.
H.test("F1 foundation rejects is_dragon even when value == last+1", function()
   load_script("main/Scripts/base_slot.script")
   local self = { last_card = { data = { suit = "red", value = 4 } } }
   local new_card = { data = { is_dragon = true, value = 5, suit = "red" } }
   if check_correct_cards(self, new_card) then
      return false, "dragon with is_dragon=true accepted — typo id_dragon is masking the guard"
   end
   -- numeric next-rank of same suit still accepted
   if not check_correct_cards(self, { data = { value = 5, suit = "red" } }) then
      return false, "legitimate 5_red on 4_red was rejected"
   end
   return true
end)

-- F2: complete-landing on an already occupied cell must NOT notify / decrement
H.test("F2 collect occupy on parked card does not double-notify", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = true,  -- dragon already parked here
      is_blocked = false,
      cursor = "cursor",
      slot_id = "free_slot1",
      dragon_button_trace = { red = "dragon_button1", blue = "dragon_button2", green = "dragon_button3" },
   }
   msg.clear()
   on_message(self, hash("occupy_slot"), {
      complete = true,
      animation = false,
      card = { data = { value = "d", suit = "red" }, id = "d1" },
      position = { x = 0, y = 0, z = 0 },
   }, "card")
   if stub.msg_count("update_free_slot") > 0 then
      return false, "occupied slot re-sent update_free_slot — counters would decrement twice"
   end
   if stub.msg_count("change_free_slots_button_counter") > 0 then
      return false, "occupied slot re-decremented dragon button counters"
   end
   if not self.is_blocked then
      return false, "first complete landing should still mark the cell blocked"
   end
   return true
end)

H.test("F2 collect occupy on empty cell still notifies once", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = false,
      is_blocked = false,
      cursor = "cursor",
      slot_id = "free_slot1",
      dragon_button_trace = { red = "dragon_button1", blue = "dragon_button2", green = "dragon_button3" },
   }
   msg.clear()
   on_message(self, hash("occupy_slot"), {
      complete = true,
      animation = false,
      card = { data = { value = "d", suit = "red" }, id = "d1" },
      position = { x = 0, y = 0, z = 0 },
   }, "card")
   if stub.msg_count("update_free_slot") ~= 1 then
      return false, "empty cell must notify cursor exactly once on collect land"
   end
   if not self.is_blocked or not self.is_occupied then
      return false, "empty collect land must set is_blocked and is_occupied"
   end
   return true
end)

-- F9: disabled button must ignore a stale get_dragon_cards
H.test("F9 get_dragon_cards is a no-op when is_enable is false", function()
   load_script("main/Scripts/dragon_button.script")
   local self = {
      is_enable = false,
      cursor = "cursor",
      cards = { { id = "d1" } },
      sprite = "red",
      default_sprite = "red_grey",
      slot_id = "dragon_button1",
      counter = 4,
      free_slots_counter = 1,
   }
   msg.clear()
   on_message(self, hash("get_dragon_cards"), {}, "cursor")
   if stub.msg_count("get_dragon_cards") > 0 then
      return false, "disabled button re-dispatched get_dragon_cards"
   end
   return true
end)

-- A6 regression: occupy_slot also runs last_card_to_slot, so the SAME dragon can be
-- announced twice (move an exposed dragon onto an empty column). check_state compares
-- `counter == 4` EXACTLY, so a re-count either lights the button early with a duplicate
-- in self.cards, or overshoots 4 and kills the button for the rest of the game.
H.test("A6 send_counter_to_button ignores a dragon it already counted", function()
   load_script("main/Scripts/dragon_button.script")
   local self = {
      is_enable = true, counter = 0, cards = {},
      sprite = "red", default_sprite = "red_grey",
      cursor = "cursor", slot_id = "dragon_button1", free_slots_counter = 3,
   }
   local d1 = { id = "d_red_1", data = { value = "d", suit = "red" } }
   local d2 = { id = "d_red_2", data = { value = "d", suit = "red" } }

   on_message(self, hash("send_counter_to_button"), d1, "tableau")
   on_message(self, hash("send_counter_to_button"), d1, "tableau") -- same dragon re-placed
   if self.counter ~= 1 then
      return false, "same dragon counted twice: counter=" .. tostring(self.counter)
   end
   if #self.cards ~= 1 then
      return false, "duplicate entry in self.cards: #cards=" .. tostring(#self.cards)
   end

   on_message(self, hash("send_counter_to_button"), d2, "tableau") -- a different dragon
   if self.counter ~= 2 then
      return false, "a distinct dragon was swallowed by the dedup: counter=" .. tostring(self.counter)
   end
   return true
end)

-- Guards the INVERSE failure of the dedup above: all four dragons of a suit share the
-- same deck id ("d_red", main.script:89) and differ only by the factory GO id stored in
-- record.id (main.script:150). Deduping on the wrong field would swallow dragons 2-4 and
-- the button could never reach `counter == 4`.
H.test("A6 dedup keys on the GO id, so 4 distinct dragons still reach counter 4", function()
   load_script("main/Scripts/dragon_button.script")
   local self = {
      is_enable = true, counter = 0, cards = {},
      sprite = "red", default_sprite = "red_grey",
      cursor = "cursor", slot_id = "dragon_button1", free_slots_counter = 3,
   }
   -- four separate game objects, all carrying the SAME deck data (id = "d_red")
   local deck_data = { id = "d_red", value = "d", suit = "red", is_dragon = true }
   for i = 1, 4 do
      on_message(self, hash("send_counter_to_button"),
         { id = "go_card_" .. i, data = deck_data, slot_id = "tableau_slot" .. i }, "tableau")
   end
   if self.counter ~= 4 then
      return false, "4 distinct dragons must reach counter==4, got " .. tostring(self.counter)
         .. " — dedup is keying on the shared deck id instead of the GO id"
   end
   if #self.cards ~= 4 then
      return false, "self.cards must hold all 4 dragons, got " .. tostring(#self.cards)
   end
   return true
end)

-- F4 regression: the queued GUI click must survive a level load -- only unloading may
-- drop it. Clearing on load silences PLAY/restart entirely (main.script polls sfx.pending).
H.test("F4 level load keeps the queued click, unload drops it", function()
   local sfx = require("main.Scripts.sfx")
   load_script("main/Scripts/game_manager.script")
   local self = { current_proxy = nil, current_level = "soliter" }

   sfx.queue("button_click")
   on_message(self, hash("start_game"), {}, "ui")
   if sfx.pending ~= "button_click" then
      return false, "level load wiped the queued click -- PLAY/restart become silent"
   end

   on_message(self, hash("unload_level"), {}, "ui")
   if sfx.pending ~= nil then
      return false, "unload must drop the pending click so it cannot leak into the next deal"
   end
   return true
end)

-- A6: placing a card onto a column must defer last_card_to_slot (2/f/d auto)
H.test("A6 occupy_slot sets pending_top_check", function()
   load_script("main/Scripts/tableau_script.script")
   local self = {
      is_empty = true,
      pending_top_check = false,
      stack = {},
      index = 1,
      cursor = "cursor",
   }
   on_message(self, hash("occupy_slot"), {
      card = { id = "c2", data = { value = 2, suit = "red" } },
   }, "card")
   if not self.pending_top_check then
      return false, "occupy_slot did not set pending_top_check — a 2/flower from free cell will not auto-fly"
   end
   if self.is_empty then
      return false, "occupy_slot left is_empty=true"
   end
   return true
end)

-- A3: auto-2 to foundation must take a flying_count slot so it cannot be grabbed
H.test("A3 send_to_base_slot increments flying_count until the flight ends", function()
   load_script("main/Scripts/cursor.script")
   local self = {
      flying_count = 0,
      base_slots = {
         base_slot1 = { is_empty = true, pos = { x = 1, y = 2, z = 0 } },
         base_slot2 = { is_empty = true, pos = { x = 0, y = 0, z = 0 } },
         base_slot3 = { is_empty = true, pos = { x = 0, y = 0, z = 0 } },
      },
      flower_slot = { flower_slot = { x = 0, y = 0, z = 0 } },
      free_slots = {},
      dragon_buttons = {},
      input_disabled = false,
   }
   on_message(self, hash("send_to_base_slot"), {
      id = "card2",
      data = { value = 2, suit = "red" },
   }, "tableau")
   if (self.flying_count or 0) < 1 then
      return false, "send_to_base_slot did not increment flying_count — 2 is grabbable in flight"
   end
   timer.flush()
   if self.flying_count ~= 0 then
      return false, "flying_count leaked after base-slot flight finished: " .. tostring(self.flying_count)
   end
   return true
end)

-- F3: action.x/y arrive linearly stretched into 960x540 with no letterbox
-- compensation, while the world is drawn fixed-FIT (scaled by min(), centred).
-- The two agree only at 16:9. Numbers below were measured in a real browser
-- (tools/browser-test.py, probe print inside cursor.on_input), not derived.
H.test("F3 screen_to_world is identity at the authored 16:9 resolution", function()
   local coords = require("main.Scripts.coords")
   stub.set_window(960, 540)
   local x, y = coords.screen_to_world(77, 159)
   if math.abs(x - 77) > 0.5 or math.abs(y - 159) > 0.5 then
      return false, ("960x540 must pass through unchanged, got %.1f,%.1f"):format(x, y)
   end
   return true
end)

H.test("F3 screen_to_world undoes the horizontal letterbox (20:9 canvas)", function()
   local coords = require("main.Scripts.coords")
   stub.set_window(1200, 540)
   -- browser measurement: pressing the card at world x=77 delivered action.x=158
   local x, y = coords.screen_to_world(158, 158.5)
   if math.abs(x - 77) > 1.5 then
      return false, ("action.x=158 on a 1200x540 canvas must map to world x~77, got %.1f"):format(x)
   end
   if math.abs(y - 158.5) > 1.0 then
      return false, ("y has no letterbox at 20:9 and must pass through, got %.1f"):format(y)
   end
   return true
end)

H.test("F3 screen_to_world undoes the vertical letterbox (4:3 canvas)", function()
   local coords = require("main.Scripts.coords")
   stub.set_window(800, 600)
   -- browser measurement: pressing the card at world y=159 delivered action.y=187
   local x, y = coords.screen_to_world(77.4, 186.8)
   if math.abs(y - 159) > 1.5 then
      return false, ("action.y=187 on a 800x600 canvas must map to world y~159, got %.1f"):format(y)
   end
   if math.abs(x - 77.4) > 1.0 then
      return false, ("x has no letterbox at 4:3 and must pass through, got %.1f"):format(x)
   end
   stub.set_window(960, 540)
   return true
end)

return H
