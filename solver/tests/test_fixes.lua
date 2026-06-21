-- test_fixes.lua — regression tests for the Stage-1b consensus review fixes.
-- See reviews/solver-SYNTHESIS.md findings #1 (deal), #2 (dragon counter), #3 (flower).

local new_harness = require("solver.tests.harness")
local R = require("solver.rules")
local H = new_harness()

local function num(suit, val)   return { value=val,  suit=suit } end
local function drag(suit)       return { value="d",  suit=suit, is_dragon=true } end
local function flower()         return { value="f",  suit="flower", is_flower=true } end

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
   }
end

local function has_move(moves, fields)
   for _, m in ipairs(moves) do
      local match = true
      for k, v in pairs(fields) do
         if m[k] ~= v then match = false; break end
      end
      if match then return true end
   end
   return false
end

-- ============================================================
-- FIX #1: deal layout is COLUMN-MAJOR (regression snapshot, seed 42).
-- Round-robin (the old bug) produces a different layout. These exact values
-- were captured from the corrected column-major M.deal(42). Source of truth:
-- main.script:105-148 (deal_cards) — outer col 1..8, inner 5 cards per column.
-- ============================================================
H.test("fix#1 deal column-major: seed 42 layout matches game (regression)", function(rules)
   local function code(card) return card.suit:sub(1,1) .. tostring(card.value) end
   local function col_str(st, i)
      local t = {}
      for _, c in ipairs(st.tableau[i]) do t[#t+1] = code(c) end
      return table.concat(t, ",")
   end
   local st = rules.deal(42)
   local c1 = col_str(st, 1)
   local c2 = col_str(st, 2)
   if c1 ~= "g6,b4,g5,b2,g3" then
      return false, "col1 expected 'g6,b4,g5,b2,g3' (column-major) got '" .. c1 .. "' — deal may have reverted to round-robin"
   end
   if c2 ~= "rd,b5,r8,rd,rd" then
      return false, "col2 expected 'rd,b5,r8,rd,rd' got '" .. c2 .. "'"
   end
   -- determinism
   if col_str(rules.deal(42), 1) ~= c1 then return false, "deal not deterministic for same seed" end
   return true
end)

-- ============================================================
-- FIX #2: dragon counter is TABLEAU-TOPS ONLY.
-- Game increments the button counter only when a dragon surfaces as a tableau
-- top (dragon_button.script:25 via tableau_script.script:44); a dragon parked in
-- a free cell does NOT count. So 3 tops + 1 in a free cell => NO collect.
-- ============================================================
H.test("fix#2 dragon counter: 3 tops + 1 in free cell => NO dragon_collect", function(rules)
   local state = empty_state()
   -- 3 red dragons exposed on tableau tops
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   -- 4th red dragon parked in an unblocked free cell (must NOT count)
   state.free_cells[1] = { card=drag("red"), is_blocked=false }

   local moves = rules.legal_moves(state)
   if has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "dragon_collect for red must NOT appear: only 3 dragons are tableau tops; the 4th is parked in a free cell (game counts tops only)"
   end
   return true
end)

H.test("fix#2 dragon counter: 4 tops + free slot => dragon_collect present", function(rules)
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   state.tableau[4] = { drag("red") }
   -- a free slot is available (all cells empty)
   local moves = rules.legal_moves(state)
   if not has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "dragon_collect for red MUST appear: all 4 red dragons are tableau tops and a free cell is available"
   end
   return true
end)

-- NOTE on the flower: review #3 (grok-build) suggested guarding the flower out of
-- manual moves. We deliberately did NOT: free_cell.script:46-49 accepts any card
-- (parity test B5), and the flower is auto-flown by apply_mandatory before any
-- branch, so it is never a tableau top inside the search. Guarding would contradict
-- B5 for zero change in solver behaviour. Decision recorded in reviews/solver-SYNTHESIS.md.

return H
