-- test_watch.lua — tests for the ASCII solver replay viewer (solver/watch.lua).
-- Only the PURE rendering functions are tested here; the animation/IO loop
-- (screen clear + sleep) is not unit-tested. Replay correctness itself is
-- already covered by run.lua's replay_and_verify.

local new_harness = require("solver.tests.harness")
local W = require("solver.watch")
local H = new_harness()

-- ============================================================
-- card_str: one card -> short plain token (no padding, no color)
-- ============================================================
H.test("watch.card_str: numeric / dragon / flower / empty", function(rules)
   local cases = {
      { card = { value = 5,   suit = "red"   },                 want = "R5"  },
      { card = { value = 10,  suit = "green" },                 want = "G10" },
      { card = { value = "d", suit = "blue", is_dragon = true}, want = "BD"  },
      { card = { value = "f", suit = "flower", is_flower=true}, want = "FL"  },
      { card = nil,                                             want = "."   },
   }
   for _, c in ipairs(cases) do
      local got = W.card_str(c.card)
      if got ~= c.want then
         return false, string.format("card_str mismatch: got %q want %q", tostring(got), c.want)
      end
   end
   return true
end)

-- ============================================================
-- render: full board -> multi-line string with the key regions present
-- ============================================================
H.test("watch.render: shows foundations, free cells, and 8 columns", function(rules)
   local state = rules.deal(1)
   local s = W.render(state, { move_no = 0, total = 0, desc = "deal" })
   for _, token in ipairs({ "R:", "B:", "G:", "FREE", "FLOWER", "c1", "c8" }) do
      if not s:find(token, 1, true) then
         return false, "render output missing region marker: " .. token
      end
   end
   -- A real dealt card token (suit letter + value) must appear somewhere.
   if not s:find("%u%d") then
      return false, "render output shows no card tokens"
   end
   return true
end)

-- ============================================================
-- render: a collected-dragon (blocked) free cell is shown distinctly
-- ============================================================
H.test("watch.render: blocked free cell renders as collected, not as a card", function(rules)
   -- Controlled state (empty tableau) so the only possible "RD" would come from
   -- the free-cell region under test.
   local state = {
      tableau = { {},{},{},{},{},{},{},{} },
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cells = {
         { card = { value="d", suit="red", is_dragon=true }, is_blocked = true },
         { card = nil, is_blocked = false },
         { card = nil, is_blocked = false },
      },
      flower_slot = { occupied = false },
      dragons_collected = { red = false, blue = false, green = false },
   }
   local s = W.render(state, { move_no = 1, total = 1, desc = "x" })
   if s:find("RD", 1, true) then
      return false, "blocked (collected) free cell should render as a pile (e.g. [##]), not the raw token RD"
   end
   if not s:find("[##]", 1, true) then
      return false, "blocked free cell should render as a collected pile marker [##]"
   end
   return true
end)

return H
