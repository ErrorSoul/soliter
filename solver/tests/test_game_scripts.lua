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

return H
