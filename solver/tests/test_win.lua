-- test_win.lua
-- Tests for rules.is_win(state) — win condition (SPEC §4).
--
-- GROUNDING:
--   The game is won when ALL of:
--     foundation_top.red == 10, foundation_top.blue == 10, foundation_top.green == 10
--     flower_slot.occupied == true
--   Dragons in blocked free cells is implied and NOT separately checked by
--   the win predicate (SPEC §4 explicit note).
--
--   The live-game bug (base_cards_count >= 27) is NOT reproduced in the solver.
--   The solver MUST use the explicit 3-foundation + flower condition.
--
--   CRITICAL test (c): a state with 27 numeric cards on foundation but
--   dragons/flower still out must NOT be considered a win.
--
-- Anti-weakening checkpoints:
--   (w1) all-foundation + flower = WIN
--   (w2) 27 numeric on foundation BUT dragons still on tableau = NOT WIN
--   (w3) 27 numeric on foundation BUT flower not collected = NOT WIN
--   (w4) only partial foundation (e.g., red=10,blue=10,green=8) = NOT WIN
--   (w5) empty starting state = NOT WIN

local new_harness = require("solver.tests.harness")
local H = new_harness()

-- Helpers to build states
local function empty_state()
   return {
      tableau = { {},{},{},{},{},{},{},{} },
      foundation_top = { red=1, blue=1, green=1 },
      free_cells = {
         { card=nil, is_blocked=false },
         { card=nil, is_blocked=false },
         { card=nil, is_blocked=false },
      },
      flower_slot = { occupied=false },
      dragons_collected = { red=false, blue=false, green=false },
      dragon_counter    = { red=0, blue=0, green=0 },
      free_slots_counter = { red=3, blue=3, green=3 },
   }
end

local function make_dragon(suit)
   return { value="d", suit=suit, is_dragon=true }
end

local function make_flower()
   return { value="f", suit="flower", is_flower=true }
end

local function make_num(suit, val)
   return { value=val, suit=suit }
end

-- (w1) All foundations at 10 + flower occupied = WIN
H.test("is_win: all-foundation (3×10) + flower occupied = WIN", function(rules)
   local state = empty_state()
   state.foundation_top = { red=10, blue=10, green=10 }
   state.flower_slot.occupied = true
   state.dragons_collected = { red=true, blue=true, green=true }
   -- tableau and free_cells are empty (everything is placed)
   local result = rules.is_win(state)
   if result ~= true then
      return false, "expected is_win=true when foundation_top all 10 and flower collected"
   end
   return true
end)

-- (w2) 27 numeric on foundation but dragons still on tableau = NOT WIN
-- This is test (c) from the task: the solver must NOT trigger victory early.
-- Grounded against SPEC §4: "The live game can trigger victory while dragons are
-- still on the tableau... For a correct solver, use the explicit condition."
-- And main.script:605: live bug uses base_cards_count >= 27.
H.test("is_win: 27 numeric on foundation but dragons on tableau = NOT WIN [test-c]", function(rules)
   local state = empty_state()
   -- All numeric cards are in the foundation
   state.foundation_top = { red=10, blue=10, green=10 }
   -- Flower has NOT been collected
   state.flower_slot.occupied = false
   -- Dragons are still sitting on the tableau (uncollected)
   state.tableau[1] = {
      make_dragon("red"), make_dragon("red"), make_dragon("red"), make_dragon("red"),
   }
   state.tableau[2] = {
      make_dragon("blue"), make_dragon("blue"), make_dragon("blue"), make_dragon("blue"),
   }
   state.tableau[3] = {
      make_dragon("green"), make_dragon("green"), make_dragon("green"), make_dragon("green"),
   }
   state.tableau[4] = { make_flower() }

   local result = rules.is_win(state)
   if result ~= false then
      return false, "NOT WIN expected when flower and dragons are still uncollected, even if numeric foundation is full"
   end
   return true
end)

-- (w3) All numeric on foundation + dragons collected, but flower NOT collected = NOT WIN
H.test("is_win: all numeric + dragons collected but flower slot empty = NOT WIN [test-c]", function(rules)
   local state = empty_state()
   state.foundation_top = { red=10, blue=10, green=10 }
   state.flower_slot.occupied = false  -- flower NOT collected
   -- Dragons are in blocked free cells (collected)
   state.free_cells = {
      { card=make_dragon("red"),   is_blocked=true },
      { card=make_dragon("blue"),  is_blocked=true },
      { card=make_dragon("green"), is_blocked=true },
   }
   state.dragons_collected = { red=true, blue=true, green=true }

   local result = rules.is_win(state)
   if result ~= false then
      return false, "NOT WIN expected when flower slot is still empty"
   end
   return true
end)

-- (w4) Partial foundation only = NOT WIN
H.test("is_win: partial foundation (red=10,blue=10,green=8) = NOT WIN", function(rules)
   local state = empty_state()
   state.foundation_top = { red=10, blue=10, green=8 }
   state.flower_slot.occupied = true
   state.dragons_collected = { red=true, blue=true, green=true }

   local result = rules.is_win(state)
   if result ~= false then
      return false, "NOT WIN expected when one foundation suit is not complete (green=8)"
   end
   return true
end)

-- (w5) Empty starting state = NOT WIN
H.test("is_win: empty starting state = NOT WIN", function(rules)
   local state = empty_state()
   local result = rules.is_win(state)
   if result ~= false then
      return false, "NOT WIN expected for an empty/starting state"
   end
   return true
end)

-- (w6) Foundation all 10 + flower but one suit actually at 9 = NOT WIN
H.test("is_win: foundation nearly complete (one suit at 9) = NOT WIN", function(rules)
   local state = empty_state()
   state.foundation_top = { red=9, blue=10, green=10 }
   state.flower_slot.occupied = true
   state.dragons_collected = { red=true, blue=true, green=true }

   local result = rules.is_win(state)
   if result ~= false then
      return false, "NOT WIN expected when red foundation is at 9 (needs 10)"
   end
   return true
end)

return H
