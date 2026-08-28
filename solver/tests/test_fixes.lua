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
-- FIX #1: M.deal reproduces the GAME'S deal ALGORITHM bit-for-bit. The oracle
-- below independently reimplements the game in pure Lua:
--   create_deck   (main.script:62-76)  — PER-SUIT: each suit's 2..10 then its 4
--                                          dragons, then next suit, flower last.
--   shuffle_deck  (main.script) — 3 Fisher-Yates passes. Сидирование и прогрев
--                                 с 2026-08-23 живут в game_manager.init (D4:
--                                 os.time() на каждую раздачу давал двум
--                                 рестартам в секунду одну колоду). Тест
--                                 сидирует локально, поэтому переезд его не
--                                 касается — но сравнивать с игрой надо ровно
--                                 три прохода тасовки, без seed внутри них.
--   deal_cards    (main.script:105-148) — COLUMN-MAJOR, 8 cols × 5, removed from end.
-- This is a Lua-vs-Lua check (both use math.random) so it CAN match exactly,
-- validating the algorithm. It does NOT claim per-seed parity with the LIVE game
-- (Defold's PRNG ≠ Lua 5.4's) — that is unfixable in pure Lua and irrelevant to
-- the aggregate solvable-rate (uniform shuffle ⇒ same board distribution).
-- ============================================================
H.test("fix#1 deal matches game algorithm bit-for-bit (oracle, seeds 1/42/12345)", function(rules)
   -- Independent oracle reimplementation of the game's deal.
   local function game_deal(seed)
      local deck = {}
      for _, suit in ipairs({ "red", "blue", "green" }) do
         for v = 2, 10 do deck[#deck+1] = { value=v,   suit=suit } end
         for _ = 1, 4   do deck[#deck+1] = { value="d", suit=suit, is_dragon=true } end
      end
      deck[#deck+1] = { value="f", suit="flower", is_flower=true }
      math.randomseed(seed)
      for _ = 1, 20 do math.random() end
      for _ = 1, 3 do
         for i = #deck, 2, -1 do
            local j = math.random(1, i)
            deck[i], deck[j] = deck[j], deck[i]
         end
      end
      local tableau = {}
      for c = 1, 8 do
         tableau[c] = {}
         for _ = 1, 5 do table.insert(tableau[c], table.remove(deck)) end
      end
      return tableau
   end

   for _, seed in ipairs({ 1, 42, 12345 }) do
      local got = rules.deal(seed).tableau
      local want = game_deal(seed)
      for c = 1, 8 do
         for r = 1, 5 do
            local g, w = got[c][r], want[c][r]
            if g.value ~= w.value or g.suit ~= w.suit then
               return false, string.format(
                  "seed %d col%d row%d: got %s:%s, game algorithm gives %s:%s — deck build / deal order diverges",
                  seed, c, r, tostring(g.suit), tostring(g.value), tostring(w.suit), tostring(w.value))
            end
         end
      end
   end
   return true
end)

-- ============================================================
-- C1 (was FIX #2, INVERTED 2026-08-16): the dragon counter is EXPOSED dragons —
-- tableau tops AND unblocked free cells.
-- fix#2 claimed tops-only and this test asserted it, which pinned the bug in
-- place. The button counter is incremented once per dragon that surfaces as a
-- top and is NEVER decremented, so parking that dragon does not take it back —
-- and a dragon can only reach a cell from a top, and can never be buried again
-- (can_stack_cards rejects dragons). In the live game 3 tops + 1 parked lights
-- the button; the solver used to refuse the move.
-- ============================================================
H.test("C1 dragon counter: 3 tops + 1 in free cell => dragon_collect IS legal", function(rules)
   local state = empty_state()
   -- 3 red dragons exposed on tableau tops
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   -- 4th red dragon parked in an unblocked free cell — it still counts
   state.free_cells[1] = { card=drag("red"), is_blocked=false }

   local moves = rules.legal_moves(state)
   if not has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "dragon_collect for red MUST appear: 3 dragons on tops + 1 parked in a free cell = 4 exposed, exactly what lights the button in game"
   end
   return true
end)

H.test("C1 dragon counter: 3 tops + 1 buried => still NO dragon_collect", function(rules)
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   -- 4th red dragon buried under a numeric: never surfaced, never counted
   state.tableau[4] = { drag("red"), num("blue", 5) }

   local moves = rules.legal_moves(state)
   if has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "a buried dragon has never been a tableau top — the button counter never saw it, so collect must stay illegal"
   end
   return true
end)

-- The parked dragon's own cell is the host, so the collect needs no OTHER free
-- cell — parity with compute_free_slots_counter and with the live button, whose
-- free_slots_counter was never charged twice for that cell.
H.test("C1 collect is legal with 2 parked reds and the last cell taken by a stranger", function(rules)
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.free_cells[1] = { card=drag("red"),      is_blocked=false }
   state.free_cells[2] = { card=drag("red"),      is_blocked=false }
   state.free_cells[3] = { card=num("blue", 7),   is_blocked=false }

   local moves = rules.legal_moves(state)
   if not has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "2 tops + 2 parked = 4 exposed; a parked cell hosts the pile, so no spare cell is required"
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
