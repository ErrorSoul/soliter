-- test_solvable.lua
-- Test (a): the known-solvable deal from deal_auto_finish_test in main.script.
--
-- GROUNDING:
--   The board is lifted VERBATIM from main.script:225-282 (deal_auto_finish_test).
--   That function creates an explicit layout with these 3 populated columns:
--     col1: bottom=3_blue, top=2_red
--     col2: bottom=3_red,  top=2_blue
--     col3: bottom=3_green, top=2_green
--     col4-8: empty
--   The solver MUST return "solved" (a solution path exists) for this state.
--
--   Solution exists because:
--     1. 2_red auto-moves to foundation (foundation_top.red becomes 2)
--     2. 2_blue auto-moves to foundation (foundation_top.blue becomes 2)
--     3. 2_green auto-moves to foundation (foundation_top.green becomes 2)
--     4. Then 3_blue → 3_red → 3_green complete foundations → WIN
--   (No dragons, no flower in this test deal.)
--
-- IMPORTANT: This board has NO dragons and NO flower.
--   is_win requires foundation_top all==10 AND flower_slot.occupied==true.
--   However, since there is NO flower card in this deal, a correct solver
--   must recognize that all cards are numeric and the win state is achievable
--   with flower_slot untouched (since the flower was never in this test deal).
--   The SPEC §4 win condition requires flower_slot.occupied == true.
--   The solver must recognize this deal reaches a state where:
--     foundation_top = {red=3, blue=3, green=3}
--     all tableau empty
--     no dragons, no flower card
--   Since this mini-deal only has 6 cards (no flower, no dragons), the solver
--   must understand this is a sub-game that IS solvable given the cards provided.
--   We test rules.solve(state) returns a non-nil/non-false result.
--
-- NOTE ON FLOWER HANDLING:
--   The test deal has no flower and no dragons. The win condition checks
--   foundation_top.X == 10, but this 6-card mini-board can only reach max
--   foundation_top = 3. A true "solve" for this mini-board means finding
--   a move sequence that places all present cards in foundation. The test
--   therefore checks that rules.solve(state) succeeds (returns a solution)
--   rather than that the returned win state passes is_win(). See notes below.

local new_harness = require("solver.tests.harness")
local H = new_harness()

local function num(suit, val) return { value=val, suit=suit } end

local function make_auto_finish_state()
   -- Verbatim from main.script:229-242 (deal_auto_finish_test layout)
   -- Only the state data matters; no Defold game objects.
   local state = {
      tableau = {
         -- col1: bottom=3_blue, top=2_red  (index 1=bottom, index 2=top)
         { num("blue", 3), num("red", 2) },
         -- col2: bottom=3_red, top=2_blue
         { num("red", 3), num("blue", 2) },
         -- col3: bottom=3_green, top=2_green
         { num("green", 3), num("green", 2) },
         -- col4-8: empty
         {}, {}, {}, {}, {},
      },
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
   return state
end

-- Test (a): solver returns a solution (non-nil/non-false) for the known solvable deal.
-- rules.solve(state) must return a solution (truthy) for this board.
-- This test will FAIL if rules.lua is absent (expected during TDD step 1).
H.test("solvable A: known solvable deal (deal_auto_finish_test) returns a solution", function(rules)
   -- PROVENANCE: main.script:225-282 deal_auto_finish_test
   -- The 6-card layout with 3 numeric 2s and 3 numeric 3s (no dragons, no flower)
   -- is always solvable: auto-move all 2s first, then 3s.

   if type(rules.solve) ~= "function" then
      return false, "rules.solve must be a function (see SPEC §7)"
   end

   local state = make_auto_finish_state()
   local solution = rules.solve(state)

   if solution == nil or solution == false then
      return false, "rules.solve must return a solution for the known solvable deal (deal_auto_finish_test from main.script:225)"
   end

   -- solution must be a table (list of moves) or at least truthy
   if type(solution) ~= "table" and solution ~= true then
      return false, string.format("rules.solve must return a table (move list) or true, got %s", type(solution))
   end

   return true
end)

-- Additional check: verify the starting state of the test deal is correctly structured
H.test("solvable A: deal_auto_finish_test starting state has correct card layout", function(rules)
   -- PROVENANCE: main.script:229-242
   -- Sanity check the state we're passing to the solver is correct.
   local state = make_auto_finish_state()

   -- col1 top must be 2_red (index 2 in our bottom-to-top array)
   local col1_top = state.tableau[1][2]
   if col1_top.value ~= 2 or col1_top.suit ~= "red" then
      return false, string.format("col1 top must be 2_red, got %s_%s",
         tostring(col1_top.value), tostring(col1_top.suit))
   end

   -- col3 bottom must be 3_green (index 1)
   local col3_bot = state.tableau[3][1]
   if col3_bot.value ~= 3 or col3_bot.suit ~= "green" then
      return false, string.format("col3 bottom must be 3_green, got %s_%s",
         tostring(col3_bot.value), tostring(col3_bot.suit))
   end

   -- Cols 4-8 must be empty
   for i = 4, 8 do
      if #state.tableau[i] ~= 0 then
         return false, string.format("col%d must be empty in deal_auto_finish_test, has %d cards",
            i, #state.tableau[i])
      end
   end

   -- Total cards: 6 (no dragons, no flower)
   local total = 0
   for _, col in ipairs(state.tableau) do total = total + #col end
   if total ~= 6 then
      return false, string.format("deal_auto_finish_test must have 6 total cards, got %d", total)
   end

   return true
end)

-- Verify that after solving, all 6 cards land in foundation
-- (This tests the solver's output validity, not just truthiness)
H.test("solvable A: solution moves all 6 cards to foundation (3 suits × 2 values)", function(rules)
   -- PROVENANCE: main.script:225-282 + SPEC §3.2 (foundation placement)
   if type(rules.solve) ~= "function" then
      return false, "rules.solve must be a function"
   end
   if type(rules.apply_move) ~= "function" then
      -- apply_move may not exist; skip deep validation if so
      return false, "rules.apply_move must be a function for solution validation"
   end

   local state = make_auto_finish_state()
   local solution = rules.solve(state)
   if not solution or type(solution) ~= "table" then
      return false, "solve must return a move-list table for this deal"
   end

   -- Apply all moves from the solution
   local s = state
   for i, move in ipairs(solution) do
      local next_s, err = rules.apply_move(s, move)
      if not next_s then
         return false, string.format("apply_move failed at step %d: %s", i, tostring(err))
      end
      s = next_s
   end

   -- After all moves, all tableau columns must be empty
   for i = 1, 8 do
      if #s.tableau[i] ~= 0 then
         return false, string.format("col%d not empty after solution; %d cards remain",
            i, #s.tableau[i])
      end
   end

   -- Foundation must have placed all 3 suits with at least value 3 (max for this mini-board)
   -- (This board only has values 2 and 3, so foundation_top.X must reach 3)
   for _, suit in ipairs({"red", "blue", "green"}) do
      if s.foundation_top[suit] < 3 then
         return false, string.format("foundation.%s must reach 3 after solution, got %d",
            suit, s.foundation_top[suit])
      end
   end

   return true
end)

return H
