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

-- F2: complete-landing on an already occupied cell must NOT decrement the button
-- counters a second time (the parking already spent this cell's -1).
-- C11 split the two halves of the old guard: the cursor notification now DOES go
-- out on this path (see the C11 tests below); only the counter stays untouched.
H.test("F2 collect occupy on parked card does not re-decrement the counters", function()
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

-- C2: why the dragon-collect directive carries no "release these cells" list.
-- A dragon of the collected suit may be parked in a free cell; when the pile
-- flies onto the host cell, that source cell has to stop counting as occupied.
-- It already does: card.script posts remove_card to its PREVIOUS owner on every
-- drop_success. Sending a second remove_card from cursor/main "to be safe" is
-- not safe — free_cell nils card_data on the first one and check_dragon then
-- indexes nil (that is a crash, pinned by the second test below).
H.test("C2 drop_success releases the card's previous owner", function()
   load_script("main/Scripts/card.script")
   local self = { owner = "free_slot2", is_dragging = true }
   msg.clear()
   on_message(self, hash("drop_success"), {
      slot_id = "free_slot1",
      position = vmath.vector3(0, 0, 0),
      card = { data = { value = "d", suit = "red" }, id = "d1" },
      animation = false,
      complete = true,
   }, "cursor")

   local freed = false
   for _, e in ipairs(msg.log) do
      if e.id == "remove_card" and e.to == "free_slot2" then freed = true end
   end
   if not freed then
      return false, "no remove_card to the previous owner — the source free cell would stay occupied by a card that flew away"
   end
   if self.owner ~= "free_slot1" then
      return false, "owner must advance to the new slot"
   end
   return true
end)

H.test("C2 a SECOND remove_card on the same cell crashes — do not send one", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = true, is_blocked = false, cursor = "cursor", slot_id = "free_slot1",
      card_data = { data = { value = "d", suit = "red" }, id = "d1" },
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   msg.clear()
   local ok1 = pcall(on_message, self, hash("remove_card"), { id = "d1" }, "card")
   if not ok1 then
      return false, "the first remove_card must work"
   end
   local ok2 = pcall(on_message, self, hash("remove_card"), { id = "d1" }, "card")
   if ok2 then
      return false, "free_cell.remove_card became idempotent — good, but then this test's premise (and the comment in replay.lua about not emitting release_cells) is stale: update both"
   end
   return true
end)

-- ============================================================
-- C4: main.script must snapshot the REAL free cells. Until now
-- snapshot_and_go_map hardcoded `{{},{},{}}`, so after C1 (a parked dragon makes
-- a collect legal) the solver was handed a board that differs from the screen.
-- The contents travel by delta mirror, free_cell -> main, same shape as the
-- tableau mirror.
-- ============================================================
local function last_msg(id)
   local found
   for _, e in ipairs(msg.log) do
      if e.id == tostring(id) then found = e end
   end
   return found
end

H.test("C4 free_cell mirrors a parked card and its release to main", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = false, is_blocked = false, cursor = "cursor", slot_id = "free_slot2",
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   local card = { id = "go_5b", data = { value = 5, suit = "blue" } }

   msg.clear()
   on_message(self, hash("occupy_slot"), { card = card, position = vmath.vector3(0, 0, 0) }, "card")
   local m = last_msg("free_cell_changed")
   if not m then
      return false, "parking a card told main nothing — snapshot_and_go_map would still call the cell empty"
   end
   if m.data.slot_id ~= "free_slot2" or m.data.card ~= card or m.data.is_blocked then
      return false, "mirror payload wrong: " .. tostring(m.data.slot_id) .. " blocked=" .. tostring(m.data.is_blocked)
   end

   msg.clear()
   on_message(self, hash("remove_card"), { id = "go_5b" }, "card")
   m = last_msg("free_cell_changed")
   if not m or m.data.card ~= nil then
      return false, "picking the card back up must mirror an EMPTY cell, otherwise the snapshot keeps a ghost"
   end
   return true
end)

-- The nastiest sub-case, and exactly the C1/C2 path: the collected pile lands on
-- a cell that already held a parked dragon. free_cell.script:70-77 skips
-- update_free_slot there (is_occupied is already true), so a mirror hooked to
-- that notification would miss it. We post after `self.is_occupied = true`,
-- reading final state, so all four sub-cases are covered by one call.
H.test("C4 mirror fires on a collect landing onto an already occupied cell", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = true,        -- red dragon already parked here
      is_blocked = false, cursor = "cursor", slot_id = "free_slot1",
      card_data = { id = "go_dr1", data = { value = "d", suit = "red" } },
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   local pile = { id = "go_dr2", data = { value = "d", suit = "red" } }
   msg.clear()
   on_message(self, hash("occupy_slot"),
      { card = pile, complete = true, position = vmath.vector3(0, 0, 0) }, "card")

   -- C11 изменил этот пин осознанно: раньше здесь было 0 сообщений (гард
   -- `is_occupied` глушил уведомление целиком) — ровно это и было багом C11.
   -- Зеркало в main при этом по-прежнему НЕ навешено на `update_free_slot`:
   -- оно шлётся безусловно в конце `occupy_slot`, по финальному состоянию.
   if stub.msg_count("update_free_slot") ~= 1 then
      return false, "cursor must learn the cell became blocked (C11), exactly once"
   end
   local u = last_msg("update_free_slot")
   if not (u and u.data.is_blocked) then
      return false, "the notification must say is_blocked=true, else cursor keeps serving a loose dragon"
   end
   local m = last_msg("free_cell_changed")
   if not m or not m.data.is_blocked or m.data.card ~= pile then
      return false, "the collected pile did not reach main — the snapshot would report a loose parked dragon in a cell that is actually blocked"
   end
   return true
end)

H.test("C4 snapshot_and_go_map reports the real free cells", function()
   load_script("main/Scripts/main.script")
   local solver_replay = require("solver.replay")
   local parked = { id = "go_5b",  data = { value = 5,   suit = "blue" } }
   local pile   = { id = "go_dr2", data = { value = "d", suit = "red" } }
   local self = {
      tableau_stacks = {},
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cell_state = {
         { card = parked, is_blocked = false },
         {},
         { card = pile,   is_blocked = true },
      },
   }
   local snap, go_map, card_by_go, err = snapshot_and_go_map(self)
   if err then return false, "an honest board was refused: " .. tostring(err) end

   local fc1 = snap.free_cells[1]
   if not (fc1 and fc1.card and fc1.card.value == 5 and fc1.card.suit == "blue") then
      return false, "parked 5_blue is missing from the snapshot — the solver plans on an emptier board than the screen shows"
   end
   if go_map.free_cells[1] ~= "go_5b" or card_by_go["go_5b"] ~= parked then
      return false, "parked card's GO is not in the go_map — replay could not fly it out of the cell"
   end
   if snap.free_cells[2] and snap.free_cells[2].card then
      return false, "an empty cell must stay empty"
   end
   local fc3 = snap.free_cells[3]
   if not (fc3 and fc3.blocked and fc3.card and fc3.card.suit == "red") then
      return false, "a collected pile must be reported with blocked=true (bridge derives dragons_collected from it)"
   end
   if go_map.free_cells[3] ~= solver_replay.BLOCKED then
      return false, "a blocked cell must carry the BLOCKED sentinel, not a GO — replay.step asserts on exactly that"
   end

   -- end-to-end through the bridge: the shape above must be the shape it expects
   local state = require("solver.bridge").from_game(snap)
   if not (state.free_cells[1].card and state.free_cells[1].card.value == 5) then
      return false, "bridge dropped the parked card — snapshot field names disagree with the contract"
   end
   if not state.dragons_collected.red or not state.free_cells[3].is_blocked then
      return false, "bridge did not read the blocked pile as a collected red suit"
   end
   return true
end)

-- Seam between the two halves above: the message free_cell actually sends must be
-- the message main actually stores. Tested separately they can drift (a renamed
-- field would pass both and break the pair).
H.test("C4 the mirror message main receives becomes the snapshot it produces", function()
   load_script("main/Scripts/free_cell.script")
   local cell = {
      is_occupied = false, is_blocked = false, cursor = "cursor", slot_id = "free_slot3",
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   local card = { id = "go_7g", data = { value = 7, suit = "green" } }
   msg.clear()
   on_message(cell, hash("occupy_slot"), { card = card, position = vmath.vector3(0, 0, 0) }, "card")
   local parked_msg = last_msg("free_cell_changed")

   load_script("main/Scripts/main.script")
   local main = {
      tableau_stacks = {},
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cell_state = { {}, {}, {} },
   }
   on_message(main, hash("free_cell_changed"), parked_msg.data, "free_slot3")
   local snap = snapshot_and_go_map(main)
   if not (snap.free_cells[3] and snap.free_cells[3].card and snap.free_cells[3].card.value == 7) then
      return false, "free_cell's own message did not survive the trip into the snapshot — the two sides disagree on field names"
   end

   -- ...and picking the card back up must empty it again (occupied -> empty is
   -- written as {card=nil}, not back to {}; the snapshot must read that as empty)
   load_script("main/Scripts/free_cell.script")
   msg.clear()
   on_message(cell, hash("remove_card"), { id = "go_7g" }, "card")
   local empty_msg = last_msg("free_cell_changed")
   load_script("main/Scripts/main.script")
   on_message(main, hash("free_cell_changed"), empty_msg.data, "free_slot3")
   snap = snapshot_and_go_map(main)
   if snap.free_cells[3] and snap.free_cells[3].card then
      return false, "the released cell still reports a card — a ghost stays in every later snapshot"
   end
   return true
end)

-- C11: the host cell of a collected pile never tells cursor it became blocked
-- (the update_free_slot branch is skipped when the cell was already occupied), so
-- cursor keeps serving {dragon=..., is_blocked=false} for it. This test measures
-- what that costs downstream instead of leaving it derived: can_auto_finish
-- refuses forever on a board it would otherwise finish.
H.test("C11 a stale 'parked dragon' entry disables auto-finish for the rest of the game", function()
   load_script("main/Scripts/main.script")
   local function board()
      return {
         tutorial_mode = false, auto_finishing = false, debug_replaying = false,
         states = { PLAYING = "playing", WIN = "win" }, currentState = "playing",
         foundation_top = { red = 5, blue = 5, green = 5 },
         tableau_stacks = { { cards = { { id = "c6r", data = { value = 6, suit = "red" } } } } },
      }
   end
   if not can_auto_finish(board(), { free_cells = {} }) then
      return false, "premise broken: this board must be auto-finishable with empty cells"
   end
   local stale = { { slot_id = "free_slot1", dragon = "red", is_blocked = false } }
   if can_auto_finish(board(), { free_cells = stale }) then
      return false, "C11 is fixed or the guard moved — update plans/review-fixes.md, the entry claims this returns false"
   end
   return true
end)

-- The plan's "refuse rather than solve garbage" guard. A flower in a cell is
-- genuinely unmodelled: cells accept any card, but rules only ever auto-flies the
-- flower off a tableau top.
H.test("C4 a flower parked in a cell makes the snapshot refuse", function()
   load_script("main/Scripts/main.script")
   local self = {
      tableau_stacks = {},
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cell_state = { { card = { id = "go_f", data = { value = "f", suit = "flower" } } }, {}, {} },
   }
   local _, _, _, err = snapshot_and_go_map(self)
   if not err then
      return false, "a flower in a free cell must be refused, not silently solved as if the board were normal"
   end
   return true
end)

-- Review finding (grok-4.6, low): the dragon collect lands its four cards with a
-- 0.1s stagger. After the FIRST one the cell is already blocked, so the bridge
-- reads the suit as collected while three dragons of it are still on the table.
-- That hybrid is not the board on screen — refuse it. Before this guard the case
-- below returned err == nil (measured, that is why the guard exists).
H.test("C4 snapshot refuses mid-collect: suit blocked while its dragons are still out", function()
   load_script("main/Scripts/main.script")
   local self = {
      tableau_stacks = {
         { cards = { { id = "go_dr3", data = { value = "d", suit = "red" } } } },
      },
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cell_state = {
         { card = { id = "go_dr1", data = { value = "d", suit = "red" } }, is_blocked = true },
         {}, {},
      },
   }
   local _, _, _, err = snapshot_and_go_map(self)
   if not err then
      return false, "a half-landed collect must be refused — the solver would plan on 'red collected' with a red dragon still in a column"
   end

   -- Once the collect has finished, the same shape must still be ACCEPTED, or
   -- the guard would kill every solve after any collect. This is the board
   -- DEBUG_DRAGONS (deal_dragon_test) leaves behind: red collected into a
   -- blocked cell, blue and green dragons still stacked in the columns.
   self.tableau_stacks = {
      { cards = { { id = "go_db1", data = { value = "d", suit = "blue" } } } },
      { cards = { { id = "go_dg1", data = { value = "d", suit = "green" } } } },
   }
   local _, _, _, err2 = snapshot_and_go_map(self)
   if err2 then
      return false, "a finished collect was refused: " .. err2
   end
   return true
end)

-- ============================================================
-- C5 — перепись карт снапшота (и зеркало приземлившегося цветка)
-- ============================================================

-- Настоящая раздача, разложенная по 8 столбцам. Порядок произволен — переписи
-- важно только мультимножество, — но набор обязан быть настоящим: по одному
-- номиналу 2..10 на масть, по 4 дракона на масть, один цветок. Цветок кладём на
-- ДНО столбца: на верхушке снапшот считает его улетевшим (окно полёта), а здесь
-- нужен обычный случай.
local function full_deal_stacks()
   local cards = { { id = "flower", data = { value = "f", suit = "flower" } } }
   for _, suit in ipairs({ "red", "blue", "green" }) do
      for v = 2, 10 do
         cards[#cards + 1] = { id = v .. "_" .. suit, data = { value = v, suit = suit } }
      end
      for i = 1, 4 do
         cards[#cards + 1] = { id = "d" .. i .. "_" .. suit, data = { value = "d", suit = suit } }
      end
   end
   assert(#cards == 40, "the test deal itself must be 40 cards, got " .. #cards)
   local stacks = {}
   for c = 1, 8 do stacks[c] = { cards = {} } end
   for i, card in ipairs(cards) do
      table.insert(stacks[((i - 1) % 8) + 1].cards, card)
   end
   return stacks
end

local function full_deal_self()
   return {
      tableau_stacks = full_deal_stacks(),
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cell_state = { {}, {}, {} },
      is_full_deal = true,
   }
end

-- Гвоздь C5. Доска без одной карты внутренне непротиворечива: солвер доводит её
-- до конца и рапортует SOLVED, а партия встаёт (замерено на чистом солвере: сиды
-- 2/5/9 без 10_green дают is_goal=true при R10 B10 G9 — ровно то, что показал
-- браузерный A/B до C4). Ни один инвариант, выведенный ИЗ снапшота, этого не
-- видит; ловит только абсолютное ожидание «настоящая раздача = 40 карт».
H.test("C5 census catches a card the mirrors lost", function()
   load_script("main/Scripts/main.script")
   local self = full_deal_self()
   local _, _, _, err_ok = snapshot_and_go_map(self)
   if err_ok then
      return false, "an intact 40-card deal was refused: " .. tostring(err_ok)
   end

   -- потеряли ровно одну карту — как теряла её несинхронная ячейка до C4
   for c = 1, 8 do
      for i = #self.tableau_stacks[c].cards, 1, -1 do
         if self.tableau_stacks[c].cards[i].id == "10_green" then
            table.remove(self.tableau_stacks[c].cards, i)
         end
      end
   end
   local _, _, _, err = snapshot_and_go_map(self)
   if not err then
      return false, "a board missing 10_green was accepted — the solver would report SOLVED and the game would stall at G9"
   end
   if not tostring(err):find("10_green", 1, true) then
      return false, "the refusal must name the missing card, got: " .. tostring(err)
   end
   return true
end)

-- Собранная стопка — это ЧЕТЫРЕ карты в одной ячейке, а в снапшот попадает один
-- представитель (контракт bridge). Считать её за одну — значит объявить честную
-- доску после каждого сбора недостоверной.
H.test("C5 census counts a collected pile as four dragons, not one", function()
   load_script("main/Scripts/main.script")
   local self = full_deal_self()
   -- красные драконы ушли со стола в ячейку 2 одной стопкой
   for c = 1, 8 do
      for i = #self.tableau_stacks[c].cards, 1, -1 do
         local card = self.tableau_stacks[c].cards[i]
         if card.data.value == "d" and card.data.suit == "red" then
            table.remove(self.tableau_stacks[c].cards, i)
         end
      end
   end
   self.free_cell_state[2] = { card = { id = "d1_red", data = { value = "d", suit = "red" } }, is_blocked = true }
   local _, _, _, err = snapshot_and_go_map(self)
   if err then
      return false, "a board with a finished red collect was refused: " .. tostring(err)
   end
   return true
end)

-- Foundation тоже часть переписи: сыгранные карты уже не на столе, но с доски не
-- исчезли. Иначе перепись отказывала бы на каждой доске после первого хода в базу.
H.test("C5 census counts cards already played to the foundation", function()
   load_script("main/Scripts/main.script")
   local self = full_deal_self()
   for c = 1, 8 do
      for i = #self.tableau_stacks[c].cards, 1, -1 do
         local card = self.tableau_stacks[c].cards[i]
         if card.data.suit == "blue" and card.data.value == 2 then
            table.remove(self.tableau_stacks[c].cards, i)
         end
      end
   end
   self.foundation_top.blue = 2
   local _, _, _, err = snapshot_and_go_map(self)
   if err then
      return false, "a board with 2_blue already in the foundation was refused: " .. tostring(err)
   end
   return true
end)

H.test("C5 census catches a duplicated card", function()
   load_script("main/Scripts/main.script")
   local self = full_deal_self()
   -- та же карта числится и в столбце, и в ячейке, но с ДРУГИМ GO — card_by_go
   -- такую пару не ловит, перепись ловит.
   self.free_cell_state[1] = { card = { id = "go_dup", data = { value = 7, suit = "red" } } }
   local _, _, _, err = snapshot_and_go_map(self)
   if not err then
      return false, "two 7_red on the board were accepted"
   end
   if not tostring(err):find("7_red", 1, true) then
      return false, "the refusal must name the duplicated card, got: " .. tostring(err)
   end
   return true
end)

-- Перепись не должна убивать дев-раскладки: DEBUG_DRAGONS/DEBUG_AUTO_FINISH и
-- туториал — не 40 карт, и именно на них проверяется всё остальное.
H.test("C5 census is off when the deal is not a real 40-card one", function()
   load_script("main/Scripts/main.script")
   local self = {
      tableau_stacks = { { cards = { { id = "go_2r", data = { value = 2, suit = "red" } } } } },
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cell_state = { {}, {}, {} },
      -- is_full_deal не выставлен: так main.init помечает отладочную раздачу
   }
   local _, _, _, err = snapshot_and_go_map(self)
   if err then
      return false, "a debug layout was refused by the census: " .. tostring(err)
   end
   return true
end)

-- Цветок. До этой правки snap.flower ставился ТОЛЬКО пока цветок лежит на
-- верхушке столбца; после приземления карта уходила из зеркала tableau, и
-- снапшот забывал её насовсем (is_win в консольном solve врал, а перепись C5
-- отказывала бы на каждой доске после цветка).
H.test("C5 a landed flower stays in the snapshot", function()
   load_script("main/Scripts/main.script")
   local self = full_deal_self()
   -- цветок улетел в свой слот: зеркало tableau его сняло
   for c = 1, 8 do
      for i = #self.tableau_stacks[c].cards, 1, -1 do
         if self.tableau_stacks[c].cards[i].id == "flower" then
            table.remove(self.tableau_stacks[c].cards, i)
         end
      end
   end
   on_message(self, hash("flower_collected"), {}, "flower_slot")
   local snap, _, _, err = snapshot_and_go_map(self)
   if not snap.flower then
      return false, "the snapshot forgot the collected flower — bridge would build a state with flower_slot.occupied=false and is_win could never be true"
   end
   if err then
      return false, "a board whose flower has landed was refused: " .. tostring(err)
   end
   return true
end)

-- ============================================================
-- C10 / C11 / C6 — живая бухгалтерия сбора драконов
-- ============================================================

-- C10. Единственный путь, на котором `remove_card` приходит в заблокированную
-- ячейку: карта, чей owner уже эта ячейка, получила новый drop_success в неё же
-- (сбор на ячейку с ранее припаркованным драконом той же масти). Ячейка при этом
-- НЕ освобождается, а старый код возвращал +1 всем трём кнопкам.
H.test("C10 a blocked cell credits nothing back to the dragon buttons", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = true, is_blocked = true,
      cursor = "cursor", slot_id = "free_slot1",
      card_data = { id = "go_dr1", data = { value = "d", suit = "red" } },
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   msg.clear()
   on_message(self, hash("remove_card"), {}, "card")
   if stub.msg_count("change_free_slots_button_counter") > 0 then
      return false, "the blocked cell handed back a free slot it never freed — a button can light up with no cell to fly into"
   end
   if not self.is_blocked then
      return false, "remove_card must not unblock a collected pile"
   end
   return true
end)

-- C10, вторая половина: обычная ячейка обязана возвращать +1, иначе счётчик
-- уедет в другую сторону и кнопка не загорится там, где место есть.
H.test("C10 an ordinary cell still credits the buttons back", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = true, is_blocked = false,
      cursor = "cursor", slot_id = "free_slot1",
      card_data = { id = "go_5b", data = { value = 5, suit = "blue" } },
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   msg.clear()
   on_message(self, hash("remove_card"), {}, "card")
   -- не дракон ⇒ во все три кнопки
   if stub.msg_count("change_free_slots_button_counter") ~= 3 then
      return false, "freeing a normal cell must credit all three buttons once"
   end
   for _, e in ipairs(msg.log) do
      if e.id == "change_free_slots_button_counter" and e.data.num ~= 1 then
         return false, "credit must be +1, got " .. tostring(e.data.num)
      end
   end
   return true
end)

-- C11. Тот же путь, что в C10, но со стороны cursor: пока уведомление глушилось,
-- у него навсегда оставалась запись «в ячейке лежит незаблокированный дракон».
H.test("C11 cursor learns the cell became blocked even when it was occupied", function()
   load_script("main/Scripts/free_cell.script")
   local self = {
      is_occupied = true,   -- дракон той же масти уже припаркован здесь
      is_blocked = false, cursor = "cursor", slot_id = "free_slot1",
      card_data = { id = "go_dr1", data = { value = "d", suit = "red" } },
      dragon_button_trace = { red = "b1", blue = "b2", green = "b3" },
   }
   msg.clear()
   on_message(self, hash("occupy_slot"), {
      card = { id = "go_dr2", data = { value = "d", suit = "red" } },
      complete = true, position = vmath.vector3(0, 0, 0),
   }, "card")

   local u = last_msg("update_free_slot")
   if not u then
      return false, "cursor was never told — its free_slots entry stays {dragon=red, is_blocked=false} for the rest of the game"
   end
   if not u.data.is_blocked or u.data.is_empty then
      return false, "the notification must describe a blocked, non-empty cell"
   end
   -- и при этом счётчик кнопок не трогаем второй раз (F2)
   if stub.msg_count("change_free_slots_button_counter") > 0 then
      return false, "the counters were decremented twice for one cell"
   end
   return true
end)

-- C11, последствие. Зеркальная пара к тесту «stale entry disables auto-finish»:
-- та же доска с ПРАВИЛЬНОЙ записью должна доигрываться.
H.test("C11 with the corrected entry that same board auto-finishes", function()
   load_script("main/Scripts/main.script")
   local self = {
      tableau_stacks = {
         { cards = { { id = "go_2r", data = { value = 2, suit = "red" } } } },
         { cards = { { id = "go_2b", data = { value = 2, suit = "blue" } } } },
         { cards = { { id = "go_2g", data = { value = 2, suit = "green" } } } },
      },
      foundation_top = { red = 1, blue = 1, green = 1 },
      states = { WIN = "win" }, currentState = "playing",
   }
   -- форма ровно та, что шлёт cursor: МАССИВ записей {slot_id, dragon, is_blocked}
   local blocked_cells = { { slot_id = "free_slot1", dragon = "red", is_blocked = true } }
   if not can_auto_finish(self, { free_cells = blocked_cells }) then
      return false, "a board whose cells hold only COLLECTED piles must still auto-finish"
   end
   local stale_cells = { { slot_id = "free_slot1", dragon = "red", is_blocked = false } }
   if can_auto_finish(self, { free_cells = stale_cells }) then
      return false, "premise changed: an unblocked dragon in a cell no longer blocks auto-finish — re-check what C11 was protecting"
   end
   return true
end)

-- C6. Реплей собирает драконов сам, прямыми drop_success. Кнопка масти об этом
-- узнаёт только через `collect_done`; без него она остаётся боевой с counter==4.
H.test("C6 collect_done puts the button in the same state a real click leaves", function()
   load_script("main/Scripts/dragon_button.script")
   local self = {
      sprite = "red", default_sprite = "red_grey", cursor = "cursor",
      slot_id = "dragon_button1", counter = 4, cards = {},
      free_slots_counter = 3, is_enable = true,
   }
   msg.clear()
   on_message(self, hash("collect_done"), {}, "main")
   if self.is_enable then
      return false, "the button stayed armed — a click would re-fly four collected dragons into the blocked cell"
   end
   local st = last_msg("set_button_state")
   if not st or st.data.is_active ~= false then
      return false, "cursor's mirror still says the button is active, so the click is not even filtered by the hit test"
   end
   -- и повторный get_dragon_cards после этого — no-op (F9)
   msg.clear()
   on_message(self, hash("get_dragon_cards"), {}, "cursor")
   if stub.msg_count("get_dragon_cards") > 0 then
      return false, "a disabled button still answered get_dragon_cards"
   end
   return true
end)

-- Адресация «масть → кнопка» держится на поле `sprite` из `get_dragon_buttons` и
-- легко разъезжается при переименовании. Зовём настоящую функцию main.script:
-- копия логики в тесте ничего не доказывает (замерено — мутация в dispatch
-- такой тест не роняла).
H.test("C6 replay's dragon_collect tells the matching button", function()
   load_script("main/Scripts/main.script")
   local self = {
      dragon_buttons = {
         dragon_button1 = { sprite = "red" },
         dragon_button2 = { sprite = "blue" },
         dragon_button3 = { sprite = "green" },
      },
   }
   msg.clear()
   notify_dragon_button_collected(self, "green")
   if stub.msg_count("collect_done") ~= 1 then
      return false, "exactly one button must be told, got " .. stub.msg_count("collect_done")
   end
   local m = last_msg("collect_done")
   if m.to ~= "dragon_button3" then
      return false, "the green collect must reach the green button, went to " .. tostring(m.to)
   end
   return true
end)

H.test("C5 flower_slot tells main the flower landed", function()
   load_script("main/Scripts/flower_slot.script")
   local self = { empty = true }
   msg.clear()
   on_message(self, hash("occupy_slot"), {
      animation = false,
      card = { id = "flower", data = { value = "f", suit = "flower" } },
      position = { x = 0, y = 0, z = 0 },
   }, "card")
   if stub.msg_count("flower_collected") ~= 1 then
      return false, "flower_slot must mirror the landing to main exactly once"
   end
   for _, e in ipairs(msg.log) do
      if e.id == "flower_collected" and e.to ~= "/card_table#main" then
         return false, "flower_collected went to " .. tostring(e.to) .. ", main would never see it"
      end
   end
   return true
end)

-- ─── Ложная победа: стол пуст, но карта осталась в free cell ────────────────
-- Находка независимого ревью (grok-4.6, 2026-08-21), проверена здесь на самом
-- коде игры. auto_finish_step объявляет победу по «все tableau пусты», а карты
-- в свободных ячейках не считает вообще: find_next_auto_card смотрит только
-- верхушки колонок, а can_auto_finish проверяет ячейки лишь на живого дракона.
-- Парковка десятки в ячейку — обычный ход, так что это достижимо в живой партии.

H.test("BUG auto-finish объявляет победу, пока числовая карта лежит в free cell", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = {
      tableau_stacks = { { cards = {} }, { cards = {} }, { cards = {} }, { cards = {} },
                         { cards = {} }, { cards = {} }, { cards = {} }, { cards = {} } },
      -- 26 из 27 номиналов уже в foundation: не хватает ровно 10_red,
      -- которая припаркована игроком в свободной ячейке.
      foundation_top = { red = 9, blue = 10, green = 10 },
      base_cards_count = 26,
      free_cell_state = { { card = { value = 10, suit = "red" } }, {}, {} },
      states = { WIN = "win", PLAYING = "playing" },
      currentState = "playing",
      cursor = "cursor_go",
      auto_finishing = true,
      suit_to_base = {},
      base_slots = {},
   }
   auto_finish_step(self)
   if self.currentState ~= "win" then
      return true -- поведение исправлено: победы нет, пока карта в ячейке
   end
   return false, "победа объявлена при 26 картах в foundation и живой 10_red в свободной ячейке"
end)

-- ─── Победа = пустой стол, а не «27 номиналов» ──────────────────────────────
-- Замер (reviews/probe_win27.lua, 60 раздач): в 15 из 57 решаемых партий 27-я
-- числовая карта садится, когда на столе ещё лежат 4 дракона. Раньше Victory
-- всплывал прямо поверх них. Теперь игра сама дожимает кнопки сбора.

local function win27_self(dragons_on_table)
   local stacks = {}
   -- slot_id обязателен: dragon_relocation (G7) ищет пустую колонку и называет
   -- её курсору именно этим полем. Без него зеркало отличалось бы от боевого,
   -- и тест проверял бы не тот код.
   for i = 1, 8 do stacks[i] = { slot_id = "tableau_slot" .. i, cards = {} } end
   for i = 1, (dragons_on_table or 0) do
      table.insert(stacks[1].cards, { id = "go" .. i, data = { value = "d", suit = "red", is_dragon = true } })
   end
   return {
      tableau_stacks = stacks,
      foundation_top = { red = 10, blue = 10, green = 10 },
      base_cards_count = 27,
      free_cell_state = { {}, {}, {} },
      states = { WIN = "win", PLAYING = "playing" },
      currentState = "playing",
      cursor = "cursor_go",
      suit_to_base = {},
      base_slots = {},
      tutorial_mode = false,
      auto_finishing = false,
      -- Цветок УЖЕ в своём слоте. Это не украшение фикстуры: на foundation=27
      -- цветок либо улетел, либо ещё лежит на столе — и во втором случае
      -- сдаваться рано, потому что он улетит сам через кадр (ревью блока I).
      -- Доска, где уступка вообще имеет право сработать, — та, где цветка нет.
      flower_collected = true,
   }
end

-- G7: доска, где сдвигать НЕКУДА — все восемь колонок заняты. Двенадцать
-- драконов по колонкам: 1..4 по два, 5..8 по одному. Только на такой доске
-- уступка «победа поверх драконов» вообще имеет право сработать.
local function win27_no_move_self()
   local self = win27_self(0)
   local n = 0
   for i = 1, 8 do
      local how_many = (i <= 4) and 2 or 1
      for _ = 1, how_many do
         n = n + 1
         self.tableau_stacks[i].cards[#self.tableau_stacks[i].cards + 1] =
            { id = "d" .. n, data = { value = "d", suit = "red", is_dragon = true } }
      end
   end
   return self
end

H.test("WIN27 драконы на столе: победы нет, уходит команда авто-сбора", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)
   self.base_cards_count = 26 -- 27-я придёт сообщением
   on_message(self, hash("card_to_base"), { suit = "red", value = 10, slot_id = "base_slot1" }, "card")
   if self.currentState == "win" then
      return false, "победа объявлена, пока на столе 4 несобранных дракона"
   end
   if stub.msg_count("auto_collect_dragons") ~= 1 then
      return false, "main обязан попросить курсор дожать кнопки сбора ровно один раз"
   end
   return true
end)

H.test("WIN27 во время реплея солвера авто-сбор не влезает", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)
   self.base_cards_count = 26
   self.debug_replaying = true -- доской распоряжается директор реплея
   on_message(self, hash("card_to_base"), { suit = "red", value = 10, slot_id = "base_slot1" }, "card")
   if stub.msg_count("auto_collect_dragons") ~= 0 then
      return false, "авто-сбор перебил директиву реплея — план солвера рассинхронится"
   end
   return true
end)

H.test("WIN27 курсор жмёт горящую кнопку и молчит про пустой доклад", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   local self = { dragon_buttons = {
      dragon_button1 = { is_active = true,  sprite = "red" },
      dragon_button2 = { is_active = false, sprite = "blue" },
      dragon_button3 = { is_active = false, sprite = "green" },
   }, free_slots = { free_slot1 = { is_empty = true } } }
   on_message(self, hash("auto_collect_dragons"), {}, "main")
   if stub.msg_count("auto_collect_none") ~= 0 then
      return false, "кнопка горит и ячейка есть — докладывать «собирать нечем» нельзя"
   end
   if stub.msg_count("get_dragon_cards") ~= 1 then
      return false, "должна быть нажата ровно одна горящая кнопка"
   end
   if not self.input_disabled then
      return false, "на время сбора ввод обязан быть заглушен: pending_drop общий с пальцем"
   end
   return true
end)

-- G4 (grok-4.6 #1, блокер). Кнопки драконов горят по ОБЩЕМУ счётчику свободных
-- ячеек (dragon_button.free_slot_any → free_slots_counter > 0), а садится масть
-- в КОНКРЕТНУЮ ячейку. Значит две кнопки могут гореть при одной пустой ячейке.
-- Старый код снимал снимок всех горящих и планировал нажатия через
-- timer.delay(0 / 1.7): первая масть занимала единственную ячейку, вторая
-- гасла, а таймер всё равно стрелял — и падал уже внутри get_dragon_cards.
H.test("G4 две горящие кнопки при одной ячейке: нажата ровно одна", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   local self = { dragon_buttons = {
      dragon_button1 = { is_active = true, sprite = "red" },
      dragon_button2 = { is_active = true, sprite = "blue" },
      dragon_button3 = { is_active = false, sprite = "green" },
   }, free_slots = { free_slot1 = { is_empty = true } } }
   on_message(self, hash("auto_collect_dragons"), {}, "main")
   timer.flush() -- если код всё ещё планирует нажатия таймерами — они стрельнут тут
   if stub.msg_count("get_dragon_cards") ~= 1 then
      return false, "нажатий должно быть ровно 1, а не " .. stub.msg_count("get_dragon_cards")
         .. ": вторая масть садиться уже некуда"
   end
   return true
end)

H.test("G4 кнопка горит, но ячейки нет: не жмём и докладываем main", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   local self = { dragon_buttons = {
      dragon_button1 = { is_active = true, sprite = "red" },
   }, free_slots = { free_slot1 = { is_empty = false, dragon = "blue" } } }
   on_message(self, hash("auto_collect_dragons"), {}, "main")
   if stub.msg_count("get_dragon_cards") ~= 0 then
      return false, "жать кнопку без свободной ячейки нельзя — драконам некуда лететь"
   end
   if stub.msg_count("auto_collect_none") ~= 1 then
      return false, "нажать нечего — main обязан узнать"
   end
   return true
end)

H.test("G4 ячейка с драконом СВОЕЙ масти считается пригодной", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   local self = { dragon_buttons = {
      dragon_button1 = { is_active = true, sprite = "red" },
   }, free_slots = { free_slot1 = { is_empty = false, dragon = "red" } } }
   on_message(self, hash("auto_collect_dragons"), {}, "main")
   if stub.msg_count("get_dragon_cards") ~= 1 then
      return false, "припаркованный красный дракон — законная цель для сбора красных"
   end
   return true
end)

-- G4 (grok-4.6 #1, вторая половина): защита в самом обработчике. Человек тоже
-- может успеть кликнуть по кнопке, которая ещё горит, пока дуга предыдущей
-- масти в полёте. Раньше fly_card_arc получал target_pos = nil и падал на
-- target_pos.x, УЖЕ увеличив flying_count — ввод умирал до рестарта.
H.test("G4 get_dragon_cards без свободной ячейки не летит в nil", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   local self = {
      free_slots = { free_slot1 = { is_empty = false, dragon = "blue" } },
      pending_drop = { slot_id = "dragon_button1", color = "red" },
      flying_count = 0,
   }
   local cards = { { id = "go_d1" }, { id = "go_d2" }, { id = "go_d3" }, { id = "go_d4" } }
   local ok, err = pcall(on_message, self, hash("get_dragon_cards"), cards, "dragon_button1")
   if not ok then
      return false, "обработчик упал вместо аккуратного отказа: " .. tostring(err)
   end
   if self.flying_count ~= 0 then
      return false, "flying_count увеличен без полёта — ввод останется заглушенным навсегда"
   end
   if stub.msg_count("collect_failed") ~= 1 then
      return false, "кнопка уже потушила себя — без collect_failed она останется мёртвой"
   end
   return true
end)

H.test("G4 dragons_left видит дракона в ячейке в БОЕВОЙ форме зеркала", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(0)
   -- Ровно то, что шлёт free_cell.mirror_to_main: карта целиком, значение в .data
   self.free_cell_state = { { card = { id = "go_dr1", data = { value = "d", suit = "red" } },
                              is_blocked = false }, {}, {} }
   if dragons_left(self) ~= 1 then
      return false, "припаркованный дракон не посчитан: dragons_left = " .. dragons_left(self)
   end
   self.free_cell_state[1].is_blocked = true -- масть собрана и запечатана
   if dragons_left(self) ~= 0 then
      return false, "запечатанная ячейка — это уже собранная масть, считать её нельзя"
   end
   return true
end)

H.test("G4 отказ авто-сбора возвращает игроку ввод", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_no_move_self()
   self.base_cards_count = 20 -- победы не будет, но управление вернуть обязаны
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if stub.msg_count("enable_input") ~= 1 then
      return false, "ввод заглушен на время сбора и не возвращён — стол останется глухим"
   end
   return true
end)

H.test("WIN27 курсор докладывает main, когда ни одна кнопка не горит", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   local self = { dragon_buttons = {
      dragon_button1 = { is_active = false, sprite = "red" },
      dragon_button2 = { is_active = false, sprite = "blue" },
      dragon_button3 = { is_active = false, sprite = "green" },
   } }
   on_message(self, hash("auto_collect_dragons"), {}, "main")
   if stub.msg_count("auto_collect_none") ~= 1 then
      return false, "без горящих кнопок курсор обязан доложить main ровно один раз"
   end
   for _, e in ipairs(msg.log) do
      if e.id == "auto_collect_none" and e.to ~= "/card_table#main" then
         return false, "доклад ушёл в " .. tostring(e.to) .. ", main его не увидит"
      end
   end
   return true
end)

H.test("WIN27 ни собрать, ни сдвинуть — победа всё равно объявляется", function()
   -- G7 оставил уступку хвостом: она срабатывает, только когда пустой колонки
   -- нет вообще. Без этого выхода игрок остался бы без победы — регрессия
   -- хуже исходного бага «Victory поверх драконов».
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_no_move_self()
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if self.currentState ~= "win" then
      return false, "курсор доложил, что собрать нечем — партия обязана засчитаться"
   end
   return true
end)

H.test("WIN27 доклад «собирать нечем» до раскладки номиналов победы не даёт", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_no_move_self()
   self.base_cards_count = 20 -- партия ещё идёт
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if self.currentState == "win" then
      return false, "победа при 20 картах в foundation — запасной выход открыт слишком широко"
   end
   return true
end)

H.test("WIN27 стол реально пуст: победа объявляется сразу", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(0)
   self.base_cards_count = 26
   on_message(self, hash("card_to_base"), { suit = "red", value = 10, slot_id = "base_slot1" }, "card")
   if self.currentState ~= "win" then
      return false, "стол пуст и все номиналы разложены — это победа"
   end
   if stub.msg_count("auto_collect_dragons") ~= 0 then
      return false, "собирать нечего, команда авто-сбора лишняя"
   end
   return true
end)

H.test("WIN27 победа приходит после того, как авто-сбор доиграл драконов", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(0)
   -- сбор состоялся: ячейки запечатаны собранными драконами
   self.free_cell_state = { { card = { id = "go_dr1", data = { value = "d", suit = "red" } }, is_blocked = true }, {}, {} }
   on_message(self, hash("dragons_collected"), {}, "dragon_button")
   if self.currentState ~= "win" then
      return false, "после сбора последней масти стол пуст — победа обязана быть объявлена"
   end
   return true
end)

H.test("WIN27 дракон в ячейке НЕ запечатан — это не победа", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(0)
   -- дракон просто припаркован игроком, масть не собрана
   self.free_cell_state = { { card = { id = "go_dr1", data = { value = "d", suit = "red" } }, is_blocked = false }, {}, {} }
   on_message(self, hash("dragons_collected"), {}, "dragon_button")
   if self.currentState == "win" then
      return false, "припаркованный дракон — не собранный; стол не пуст"
   end
   return true
end)

-- Парный тест к предыдущему: гард обязан пропускать ЧЕСТНУЮ победу. Без него
-- «починка» вида «никогда не побеждать» тоже красила бы тест выше в зелёный.
H.test("BUG честная победа проходит: в ячейках только собранные драконы", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = {
      tableau_stacks = { { cards = {} }, { cards = {} }, { cards = {} }, { cards = {} },
                         { cards = {} }, { cards = {} }, { cards = {} }, { cards = {} } },
      foundation_top = { red = 10, blue = 10, green = 10 },
      base_cards_count = 27,
      -- blocked = ячейка запечатана собранными драконами, победе не мешает
      free_cell_state = { { card = { id = "go_dr1", data = { value = "d", suit = "red" } }, is_blocked = true },
                          { card = { id = "go_db1", data = { value = "d", suit = "blue" } }, is_blocked = true },
                          {} },
      states = { WIN = "win", PLAYING = "playing" },
      currentState = "playing",
      cursor = "cursor_go",
      auto_finishing = true,
      suit_to_base = {},
      base_slots = {},
   }
   auto_finish_step(self)
   if self.currentState ~= "win" then
      return false, "победа не объявлена, хотя стол пуст и в ячейках только собранные драконы"
   end
   return true
end)

-- ─── FX: математика «болтания» карты при драге ───────────────────────────────
-- Прежний наклон считался от `dx` между двумя СОБЫТИЯМИ ВВОДА, то есть зависел
-- от частоты кадров устройства. Эти тесты и запинывают нормировку по времени:
-- «на глаз» такое не проверяется вообще никак.

H.test("FX drag_speed нормирует сдвиг по времени кадра", function()
   local fx = require("main.Scripts.ui_fx")
   -- один и тот же жест, снятый на 60 и на 144 Гц, даёт ОДНУ скорость
   local slow = fx.drag_speed(10, 1 / 60)
   local fast = fx.drag_speed(10 * (60 / 144), 1 / 144)
   if math.abs(slow - fast) > 1.0 then
      return false, ("частота кадров меняет скорость: %.1f vs %.1f"):format(slow, fast)
   end
   if math.abs(slow - 600) > 1.0 then
      return false, ("10px за 1/60с это 600 px/сек, получено %.1f"):format(slow)
   end
   return true
end)

H.test("FX drag_speed не делит на ноль на первом кадре", function()
   local fx = require("main.Scripts.ui_fx")
   if fx.drag_speed(37, 0) ~= 0 then return false, "dt=0 должен давать 0" end
   if fx.drag_speed(37, nil) ~= 0 then return false, "dt=nil должен давать 0" end
   if fx.drag_speed(37, -0.1) ~= 0 then return false, "отрицательный dt должен давать 0" end
   return true
end)

H.test("FX drag_tilt_deg: знак противоположен движению и упёрт в предел", function()
   local fx = require("main.Scripts.ui_fx")
   if fx.drag_tilt_deg(0) ~= 0 then return false, "покой = нулевой наклон" end
   local right = fx.drag_tilt_deg(300)
   if not (right < 0) then
      return false, "движение вправо должно давать отрицательный угол (карта отстаёт)"
   end
   if fx.drag_tilt_deg(-300) ~= -right then
      return false, "наклон должен быть симметричен по направлению"
   end
   -- вдесятеро быстрее референса не даёт вдесятеро больший угол
   local capped = fx.drag_tilt_deg(fx.DRAG_REF_SPEED * 10)
   if math.abs(capped) > fx.DRAG_MAX_TILT_DEG + 0.001 then
      return false, ("наклон пробил предел: %.2f > %d"):format(math.abs(capped), fx.DRAG_MAX_TILT_DEG)
   end
   if math.abs(capped) < fx.DRAG_MAX_TILT_DEG - 0.001 then
      return false, "на скорости выше референса наклон обязан быть предельным"
   end
   return true
end)

H.test("FX drag_squash остаётся в читаемых пределах", function()
   local fx = require("main.Scripts.ui_fx")
   if fx.drag_squash(0) ~= 1.0 then return false, "покой = полная ширина" end
   local fastest = fx.drag_squash(fx.DRAG_REF_SPEED * 5)
   if fastest < 1.0 - fx.DRAG_MAX_SQUASH - 0.001 then
      return false, ("сжатие пробило предел: %.3f"):format(fastest)
   end
   -- страховка от возврата к старому 0.45: карта не должна становиться уже 85%
   if fastest < 0.85 then
      return false, ("карта сжимается до %.2f ширины — это лапша, а не наклон"):format(fastest)
   end
   if fx.drag_squash(-fx.DRAG_REF_SPEED) ~= fx.drag_squash(fx.DRAG_REF_SPEED) then
      return false, "сжатие не должно зависеть от направления"
   end
   return true
end)

H.test("FX smooth_speed держит наклон в кадре без события мыши", function()
   local fx = require("main.Scripts.ui_fx")
   -- первый кадр драга: сглаживать нечего, берём сырое значение как есть
   if fx.smooth_speed(nil, 800, 1 / 60) ~= 800 then
      return false, "на старте драга сглаживание должно вернуть сырую скорость"
   end
   -- курсор стоял (raw=0), но рука только что двигалась: наклон обязан
   -- уцелеть, а не схлопнуться в ноль за один кадр
   local kept = fx.smooth_speed(800, 0, 1 / 60)
   if kept <= 0 then return false, "скорость схлопнулась в ноль за один кадр" end
   if kept >= 800 then return false, "скорость обязана убывать, если движения нет" end
   -- и всё-таки затухает: десяток кадров покоя выпрямляет карту
   local v = 800
   for _ = 1, 20 do v = fx.smooth_speed(v, 0, 1 / 60) end
   if math.abs(v) > 40 then
      return false, ("после 20 кадров покоя скорость должна быть ~0, получено %.1f"):format(v)
   end
   if fx.smooth_speed(500, 900, 0) ~= 500 then
      return false, "dt=0 не должен менять сглаженное значение"
   end
   return true
end)

H.test("FX drag_lag растёт вглубь стопки и упирается в потолок", function()
   local fx = require("main.Scripts.ui_fx")
   local top = fx.drag_lag(1)
   local second = fx.drag_lag(2)
   if not (second > top) then
      return false, "вторая карта обязана отставать сильнее первой, иначе стопка — жёсткое тело"
   end
   if math.abs(top - fx.DRAG_LAG_BASE) > 1e-9 then
      return false, "верхняя карта должна ехать за базовую длительность"
   end
   local deep = fx.drag_lag(50)
   if deep > fx.DRAG_LAG_MAX + 1e-9 then
      return false, ("отставание пробило потолок: %.3f"):format(deep)
   end
   if fx.drag_lag(0) ~= top or fx.drag_lag(nil) ~= top then
      return false, "индекс 0/nil не должен уезжать в отрицательное отставание"
   end
   return true
end)


-- ============================================================
-- G5. Длинная колонка не влезала в экран
-- ============================================================
-- Замер (reviews/probe_stack_len.lua): слот tableau на y=299, карта 150 px,
-- экран 0..540. При постоянном шаге 35 px целиком видны 7 карт, восьмая уже
-- обрезана, а с двенадцатой ВЕРХНЯЯ карта колонки — единственная, которую можно
-- взять, — целиком уходит под нижнюю кромку: партия становится недоигрываемой.
-- Потолок длины колонки 12 (5 раздатых + 9..3 сверху; двойка сверху не лежит,
-- она сама улетает в foundation), плюс 13-я на время полёта этой двойки.

-- config.lua требует Defold-овский vmath — стабы уже установлены выше.
local config = require("main.Scripts.config")

local SLOT_Y, CARD_H, SCREEN_H = 299, 150, 540

local function column_bottom(n)
   -- нижняя кромка ПОСЛЕДНЕЙ карты колонки из n карт
   local pitch = config.stack_offset_y(n, SLOT_Y)
   return SLOT_Y + (n - 1) * pitch - CARD_H / 2
end

H.test("G5 короткая колонка сохраняет привычный шаг 35 px", function()
   for n = 1, 7 do
      local pitch = -config.stack_offset_y(n, SLOT_Y)
      if math.abs(pitch - 35) > 0.001 then
         return false, "колонка из " .. n .. " карт влезает и сжиматься не должна, шаг = " .. pitch
      end
   end
   return true
end)

H.test("G5 колонка любой достижимой длины помещается в экран", function()
   for n = 1, 13 do
      local bottom = column_bottom(n)
      if bottom < 0 then
         return false, "колонка из " .. n .. " карт вылезает за низ экрана на "
            .. string.format("%.1f", -bottom) .. " px — верхнюю карту не взять"
      end
      local top = SLOT_Y + CARD_H / 2
      if top > SCREEN_H then
         return false, "колонка из " .. n .. " карт вылезает за верх экрана"
      end
   end
   return true
end)

H.test("G5 сжатый корешок всё ещё показывает ранг карты", function()
   -- Ранг занимает верхние 16 px спрайта 90x150 (замер по всем 27 номиналам:
   -- цветные строки 2..15, дальше разрыв и начало арта).
   local RANK_STRIP = 16
   for n = 1, 13 do
      local pitch = -config.stack_offset_y(n, SLOT_Y)
      if pitch < RANK_STRIP then
         return false, "при " .. n .. " картах видно " .. string.format("%.1f", pitch)
            .. " px — ранг (" .. RANK_STRIP .. " px) обрезан"
      end
   end
   return true
end)

-- Главный тест: гоняем НАСТОЯЩИЙ tableau_script и смотрим координаты, которые
-- он выставил картам, а не факт вызова.
H.test("G5 tableau_script реально раскладывает 12 карт в пределах экрана", function()
   load_script("main/Scripts/tableau_script.script")
   msg.clear()
   stub.go_self_pos = { x = 77, y = SLOT_Y, z = 0 }
   stub.go_positions = {}

   -- Худший достижимый случай: 5 раздатых + достройка 9..3 на раздатую 10.
   local stack = {}
   local dealt = { { value = 4, suit = "red" }, { value = 7, suit = "blue" },
                   { value = "d", suit = "green" }, { value = 6, suit = "red" },
                   { value = 10, suit = "blue" } }
   for i, d in ipairs(dealt) do
      stack[#stack + 1] = { id = "deal" .. i, data = d }
   end
   local suits = { "red", "green", "red", "green", "red", "green", "red" }
   for k, v in ipairs({ 9, 8, 7, 6, 5, 4, 3 }) do
      stack[#stack + 1] = { id = "run" .. v, data = { value = v, suit = suits[k] } }
   end
   if #stack ~= 12 then return false, "фикстура собрана неверно: " .. #stack .. " карт" end

   local self = { is_empty = false, pending_top_check = false, stack = {}, index = 1 }
   on_message(self, hash("update_stack"),
              { stack = stack, index = 1, cursor = "cursor" }, "main")

   local placed = 0
   for _, card in ipairs(stack) do
      local pos = stub.go_positions[card.id]
      if not pos then
         return false, "карте " .. card.id .. " не выставлена позиция"
      end
      placed = placed + 1
      if pos.y - CARD_H / 2 < 0 then
         return false, "карта " .. card.id .. " ушла за низ экрана: низ = "
            .. string.format("%.1f", pos.y - CARD_H / 2)
      end
      if pos.y + CARD_H / 2 > SCREEN_H then
         return false, "карта " .. card.id .. " ушла за верх экрана"
      end
   end
   if placed ~= 12 then return false, "разложено " .. placed .. " карт из 12" end

   -- И верхняя карта колонки — та, которую игрок хватает, — должна остаться
   -- целиком видимой, иначе колонку не разобрать.
   local last = stub.go_positions["run3"]
   if last.y - CARD_H / 2 < 0 then
      return false, "верхняя карта колонки обрезана снизу — её нельзя взять"
   end
   return true
end)

H.test("G5 порядок карт в колонке сверху вниз сохранён", function()
   load_script("main/Scripts/tableau_script.script")
   msg.clear()
   stub.go_self_pos = { x = 77, y = SLOT_Y, z = 0 }
   stub.go_positions = {}
   local stack = {}
   for i = 1, 12 do stack[i] = { id = "c" .. i, data = { value = i, suit = "red" } } end
   local self = { is_empty = false, pending_top_check = false, stack = {}, index = 1 }
   on_message(self, hash("update_stack"),
              { stack = stack, index = 1, cursor = "cursor" }, "main")
   for i = 2, 12 do
      local prev = stub.go_positions["c" .. (i - 1)]
      local cur  = stub.go_positions["c" .. i]
      if not (cur.y < prev.y) then
         return false, "карта " .. i .. " не ниже предыдущей — стопка перепутана"
      end
   end
   return true
end)

-- ============================================================
-- G7 — авто-сбор двигает дракона, чтобы открыть закопанного
-- ============================================================
-- Замер reviews/probe_dragon_unblock.lua (60 раздач): из 15 партий, доходящих
-- до foundation=27 при живых драконах, одним сбором доигрываются 10, со
-- сдвигом на пустую колонку — 15 из 15, столько же, сколько даёт полный
-- перебор. То есть сдвиг закрывает разрыв целиком, а не частично.

H.test("G7 есть пустая колонка — вместо победы уходит команда сдвинуть дракона", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)   -- 4 дракона в колонке 1, колонки 2..8 пусты
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if self.currentState == "win" then
      return false, "победа поверх живых драконов, хотя дракона было куда сдвинуть"
   end
   if stub.msg_count("auto_move_dragon") ~= 1 then
      return false, "команда сдвига не ушла ровно один раз"
   end
   if stub.msg_count("enable_input") ~= 0 then
      return false, "ввод вернули посреди цепочки — палец подерётся с авто-сбором"
   end
   for _, e in ipairs(msg.log) do
      if e.id == "auto_move_dragon" then
         if e.to ~= "cursor_go" then return false, "команда ушла не курсору: " .. tostring(e.to) end
         if e.data.card.id ~= "go4" then
            return false, "двигать надо ВЕРХНЮЮ карту колонки, а выбрана " .. tostring(e.data.card.id)
         end
         if e.data.slot_id ~= "tableau_slot2" then
            return false, "целью должна быть пустая колонка, а не " .. tostring(e.data.slot_id)
         end
      end
   end
   return true
end)

H.test("G7 одинокого дракона не двигают — иначе цепочка зациклится", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(0)
   -- по одному дракону в колонках 1 и 2, остальные пусты: сдвиг ничего не
   -- откроет, а гонять карту между пустыми колонками можно вечно
   self.tableau_stacks[1].cards = { { id = "a", data = { value = "d", suit = "red", is_dragon = true } } }
   self.tableau_stacks[2].cards = { { id = "b", data = { value = "d", suit = "blue", is_dragon = true } } }
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if stub.msg_count("auto_move_dragon") ~= 0 then
      return false, "двигаем карту, под которой ничего нет — это и есть петля"
   end
   if self.currentState ~= "win" then
      return false, "сдвигать нечего и собирать нечем — партия обязана засчитаться"
   end
   return true
end)

H.test("G7 двигают верхушку САМОЙ высокой колонки", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(0)
   local function dragon(id) return { id = id, data = { value = "d", suit = "red", is_dragon = true } } end
   self.tableau_stacks[1].cards = { dragon("x1"), dragon("x2") }
   self.tableau_stacks[3].cards = { dragon("y1"), dragon("y2"), dragon("y3") }
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   for _, e in ipairs(msg.log) do
      if e.id == "auto_move_dragon" and e.data.card.id ~= "y3" then
         return false, "выбрана " .. tostring(e.data.card.id) .. ", а глубже закопано в колонке 3"
      end
   end
   return true
end)

H.test("G7 бюджет сдвигов не даёт цепочке крутиться вечно", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)
   self.auto_collect_moves = 24   -- потолок выбран
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if stub.msg_count("auto_move_dragon") ~= 0 then
      return false, "бюджет исчерпан, а сдвиг всё равно заказан"
   end
   if stub.msg_count("enable_input") ~= 1 then
      return false, "сдались — обязаны вернуть ввод игроку"
   end
   return true
end)

H.test("G7 в туториале дракона не двигают", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)
   self.tutorial_mode = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if stub.msg_count("auto_move_dragon") ~= 0 then
      return false, "туториальной доской распоряжается сценарий, а не авто-сбор"
   end
   return true
end)

H.test("G7 после сдвига цепочка возобновляется, но не в тот же кадр", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)
   self.auto_collecting = true
   on_message(self, hash("auto_collect_moved"), {}, "cursor")
   if stub.msg_count("auto_collect_dragons") ~= 0 then
      return false, "заказ ушёл немедленно: occupy_slot и счётчик кнопки ещё в очереди"
   end
   for _ = 1, 4 do update(self, 0.016) end
   if stub.msg_count("auto_collect_dragons") ~= 1 then
      return false, "цепочка не возобновилась — стол замрёт с заглушённым вводом"
   end
   for _ = 1, 4 do update(self, 0.016) end
   if stub.msg_count("auto_collect_dragons") ~= 1 then
      return false, "заказ повторился — сдвиг пойдёт по кругу"
   end
   return true
end)

H.test("G7 сдвиг после отмены авто-сбора не возобновляет цепочку", function()
   load_script("main/Scripts/main.script")
   msg.clear()
   local self = win27_self(4)
   self.auto_collecting = false   -- игрок уже получил управление
   on_message(self, hash("auto_collect_moved"), {}, "cursor")
   for _ = 1, 6 do update(self, 0.016) end
   if stub.msg_count("auto_collect_dragons") ~= 0 then
      return false, "цепочка ожила сама по себе и отберёт у игрока ввод"
   end
   return true
end)

H.test("G7 курсор действительно двигает карту: полёт → drop_success → доклад", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   stub.anims = {}
   local self = {
      flying_count = 0,
      tableau_slots = { tableau_slot5 = { is_empty = true, pos = vmath.vector3(481, 299, 0) } },
   }
   local card = { id = "d_red_go", data = { value = "d", suit = "red", is_dragon = true } }
   on_message(self, hash("auto_move_dragon"), { card = card, slot_id = "tableau_slot5" }, "main")
   if not self.input_disabled then
      return false, "ввод не заглушён: палец успеет схватить летящего дракона"
   end
   if self.flying_count ~= 1 then
      return false, "полёт не учтён в flying_count — auto-finish решит, что стол в покое"
   end
   if stub.msg_count("drop_success") ~= 0 then
      return false, "карта села, не долетев"
   end
   stub.flush_anims(2)   -- дуга это две вложенные анимации
   if self.flying_count ~= 0 then
      return false, "flying_count не вернулся к нулю — стол останется «в полёте» навсегда"
   end
   local drop, moved = nil, 0
   for _, e in ipairs(msg.log) do
      if e.id == "drop_success" then drop = e end
      if e.id == "auto_collect_moved" then moved = moved + 1 end
   end
   if not drop then return false, "после полёта не отправлен drop_success" end
   if drop.to ~= "d_red_go" then return false, "drop_success ушёл не карте: " .. tostring(drop.to) end
   if drop.data.slot_id ~= "tableau_slot5" then
      return false, "карта садится не в ту колонку: " .. tostring(drop.data.slot_id)
   end
   if drop.data.card ~= card then
      return false, "в occupy_slot уедет не та запись карты — зеркало разъедется"
   end
   if moved ~= 1 then return false, "main не узнал о сдвиге, цепочка встанет" end
   return true
end)

H.test("G7 курсор не летит в исчезнувший слот", function()
   load_script("main/Scripts/cursor.script")
   msg.clear()
   stub.anims = {}
   local self = { flying_count = 0, tableau_slots = {} }
   on_message(self, hash("auto_move_dragon"),
              { card = { id = "d_go" }, slot_id = "tableau_slot5" }, "main")
   if self.flying_count ~= 0 then
      return false, "flying_count увеличен без полёта — ровно так падал G4"
   end
   if stub.msg_count("auto_collect_none_final") ~= 1 then
      return false, "курсор промолчал: main будет ждать доклада вечно"
   end
   return true
end)


H.test("G7 победа снимает замок авто-сбора на любом пути", function()
   -- Сегодня карты после победы мертвы липким block_play_input, а обратно в
   -- партию можно попасть только через перезагрузку коллекции. Тест держит
   -- инвариант на будущее: победа не оставляет за собой auto_collecting=true.
   load_script("main/Scripts/main.script")
   for _, case in ipairs({ "board_cleared", "give_up" }) do
      msg.clear()
      local self = (case == "board_cleared") and win27_self(0) or win27_no_move_self()
      self.auto_collecting = true
      if case == "board_cleared" then
         on_message(self, hash("dragons_collected"), {}, "dragon_button")
      else
         on_message(self, hash("auto_collect_none"), {}, "cursor")
      end
      if self.currentState ~= "win" then
         return false, case .. ": победы не случилось, тест проверяет не то"
      end
      if self.auto_collecting then
         return false, case .. ": замок авто-сбора остался взведён"
      end
      if stub.msg_count("enable_input") ~= 1 then
         return false, case .. ": курсору не вернули ввод"
      end
   end
   return true
end)


-- Ревью блока I (grok-4.6): уступка срабатывала на кадр раньше, чем нужно.
-- Замер зонда, который это подтвердил: сиды 150 и 261 казались безнадёжными
-- ровно потому, что в наборе ходов не было автоулёта цветка. Стоило добавить
-- его — обе доски доигрываются до нуля драконов.
--
-- Пара тестов, а не один: «не сдаваться, пока цветок на столе» в одиночку
-- зеленело бы и от «не сдаваться никогда», то есть от партии, которая после
-- отказа авто-сбора зависает без победы навсегда.
-- Кадры крутим ТАК ЖЕ, как их крутит игра: update, а на каждый новый запрос
-- к курсору отвечаем auto_collect_none — курсор в изоляции не отвечает сам.
-- Возвращает, сколько раз main переспросил курсор.
local function run_collect_frames(self, seconds, dt)
   dt = dt or 0.016
   local asked = stub.msg_count("auto_collect_dragons")
   local frames = math.floor(seconds / dt)
   for _ = 1, frames do
      update(self, dt)
      local now = stub.msg_count("auto_collect_dragons")
      if now > asked then
         asked = now
         on_message(self, hash("auto_collect_none"), {}, "cursor")
      end
      if self.currentState == "win" then break end
   end
   return asked
end

H.test("уступка ждёт дольше, чем длится полёт цветка", function()
   msg.clear()
   load_script("main/Scripts/main.script")
   local self = win27_no_move_self()
   self.flower_collected = false   -- цветок в дуге: сядет через 0.7 с (fly_card_arc)
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if self.currentState == "win" then
      return false, "победа объявлена сразу — цветок ещё даже не тронулся"
   end
   -- 0.7 с — ровно длительность дуги (0.35 + 0.35). Пока она идёт, сдаваться
   -- нельзя: flower_collected приходит только из occupy_slot, то есть ПОСЛЕ
   -- посадки. Тест кадровый бюджет ловит: 32 кадра = 0.53 с < 0.7 с.
   local asked = run_collect_frames(self, 0.7)
   if self.currentState == "win" then
      return false, "победа объявлена посреди полёта цветка — драконы ещё на столе"
   end
   if asked < 1 then
      return false, "за всё ожидание курсора ни разу не переспросили — ввод останется глухим"
   end
   return true
end)

H.test("ожидание цветка не зависит от частоты кадров", function()
   -- Тот же полёт на 120 Гц. Бюджет, отмеренный в КАДРАХ, здесь съедается вдвое
   -- быстрее и победа приезжает посреди дуги — ровно та поломка, которую нашло
   -- ревью блока J. Бюджет в секундах эту разницу не замечает.
   msg.clear()
   load_script("main/Scripts/main.script")
   local self = win27_no_move_self()
   self.flower_collected = false
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   run_collect_frames(self, 0.7, 0.008)
   if self.currentState == "win" then
      return false, "на 120 Гц сдались посреди полёта — бюджет считается в кадрах, а не во времени"
   end
   return true
end)

H.test("уступка не ждёт вечно: закопанный цветок не держит партию", function()
   msg.clear()
   load_script("main/Scripts/main.script")
   local self = win27_no_move_self()
   self.flower_collected = false   -- закопан намертво, сигнала не будет никогда
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   run_collect_frames(self, 5.0)
   if self.currentState ~= "win" then
      return false, "ждём бесконечно — игрок остался без победы на доске, где ходов нет"
   end
   if self.auto_collecting then
      return false, "победа объявлена, а замок авто-сбора остался взведён"
   end
   return true
end)

H.test("цветок сел — уступка больше не тянет время", function()
   msg.clear()
   load_script("main/Scripts/main.script")
   local self = win27_no_move_self()
   self.flower_collected = true    -- цветок уже в своём слоте
   self.auto_collecting = true
   on_message(self, hash("auto_collect_none"), {}, "cursor")
   if self.currentState ~= "win" then
      return false, "цветка на столе нет, ходов нет — уступка обязана сработать сразу"
   end
   return true
end)

-- G3: авто-финиш не должен стартовать, когда взять нечего.
--
-- Пара тестов, а не один: проверка «не стартует» в одиночку зеленела бы и от
-- «не стартует никогда», то есть от полностью выключённого авто-финиша.
local function g3_board(cards, foundation)
   return {
      tutorial_mode = false, auto_finishing = false, debug_replaying = false,
      states = { PLAYING = "playing", WIN = "win" }, currentState = "playing",
      foundation_top = foundation,
      tableau_stacks = { { cards = cards } },
      free_cell_state = {},
   }
end

H.test("G3 закопанная под своей же старшей картой девятка не запускает авто-финиш", function()
   load_script("main/Scripts/main.script")
   -- Снизу вверх: 9_red, сверху 10_red. Обе «безопасны» (чужие фундаменты на 9),
   -- но фундамент красной ждёт 9, а сверху лежит 10.
   local cards = {
      { id = "c9r",  data = { value = 9,  suit = "red" } },
      { id = "c10r", data = { value = 10, suit = "red" } },
   }
   local self = g3_board(cards, { red = 8, blue = 9, green = 9 })
   if can_auto_finish(self, { free_cells = {} }) then
      return false, "авто-финиш стартовал на колонке, где верхушка не та: 0.5 с глухого ввода впустую"
   end
   return true
end)

H.test("G3 та же колонка в правильном порядке авто-финиш запускает", function()
   load_script("main/Scripts/main.script")
   -- Те же две карты, но 9 сверху — жадному съёму есть с чего начать.
   local cards = {
      { id = "c10r", data = { value = 10, suit = "red" } },
      { id = "c9r",  data = { value = 9,  suit = "red" } },
   }
   local self = g3_board(cards, { red = 8, blue = 9, green = 9 })
   if not can_auto_finish(self, { free_cells = {} }) then
      return false, "авто-финиш не стартовал там, где верхушка ровно следующая — проверка убила саму функцию"
   end
   return true
end)


return H
