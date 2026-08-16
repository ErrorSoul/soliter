-- test_replay.lua — tests for the PURE director planner (solver/replay.lua).
--
-- replay.plan() is the only AUTOMATED check of stage-2b director logic (the
-- Defold engine can't run headless). These tests treat a real solved deal as
-- the fixture and assert the invariants that make the auto-replay a safe smoke
-- test for the refactor that follows it:
--   * no go_map / solver desync (plan() raises on underflow),
--   * every source GO is a real card, never reused after it leaves play,
--   * free-cell ordinals are never double-booked,
--   * each directive references the card it claims to,
--   * the terminal go_map is a win (tableau empty, all 3 cells blocked).

local new_harness = require("solver.tests.harness")
local replay = require("solver.replay")
local H = new_harness()

local SEED   = 2        -- known solvable (handoff §0b: 78 moves)
local BUDGET = 200000

-- Build a solved fixture: state, solution moves, a go_map of synthetic GO ids
-- ("c<col>_<row>"), and a reverse id->card map. Returns nil if the seed did not
-- solve within budget (so the test can fail loudly with a clear reason).
local function fixture(rules)
   local state = rules.deal(SEED)
   local moves, status = rules.solve(state, { node_budget = BUDGET })
   if status ~= "solved" then return nil, "seed " .. SEED .. " did not solve: " .. tostring(status) end

   local id_card = {}
   local go_map = { tableau = {}, free_cells = {} }
   for col = 1, 8 do
      go_map.tableau[col] = {}
      for row, card in ipairs(state.tableau[col]) do
         local id = "c" .. col .. "_" .. row
         go_map.tableau[col][row] = id
         id_card[id] = card
      end
   end
   return { state = state, moves = moves, go_map = go_map, id_card = id_card }
end

-- ============================================================
-- plan() walks the whole solution without a desync, 1 directive per move.
-- (plan() asserts internally on any go_map underflow, so reaching the end is
--  itself proof the parallel bookkeeping stayed consistent.)
-- ============================================================
H.test("replay.plan: solves seed without desync, one directive per move", function(rules)
   local f, why = fixture(rules)
   if not f then return false, why end
   local directives = replay.plan(f.state, f.moves, f.go_map)
   if #directives ~= #f.moves then
      return false, string.format("directive count %d != move count %d", #directives, #f.moves)
   end
   return true
end)

-- ============================================================
-- Every source GO is a real card id, never the BLOCKED marker, and no GO is
-- referenced again after it has left play (foundation / flower / dragon pile).
-- ============================================================
H.test("replay.plan: no source GO is reused after it leaves play", function(rules)
   local f, why = fixture(rules)
   if not f then return false, why end
   local directives = replay.plan(f.state, f.moves, f.go_map)

   local gone = {}   -- GOs that have left play (foundation/flower/blocked pile)
   local function use(go, kind)
      if go == replay.BLOCKED or f.id_card[go] == nil then
         return string.format("directive %s references non-card GO %q", kind, tostring(go))
      end
      if gone[go] then
         return string.format("directive %s reuses GO %q after it left play", kind, tostring(go))
      end
   end

   for _, d in ipairs(directives) do
      if d.card_go then
         local err = use(d.card_go, d.kind); if err then return false, err end
      end
      if d.card_gos then
         for _, go in ipairs(d.card_gos) do
            local err = use(go, d.kind); if err then return false, err end
         end
      end
      -- mark consumers' GOs as gone-for-good
      if d.kind == "to_foundation" or d.kind == "flower_auto" then
         gone[d.card_go] = true
      elseif d.kind == "dragon_collect" then
         for _, go in ipairs(d.card_gos) do gone[go] = true end
      end
   end
   return true
end)

-- ============================================================
-- Free-cell ordinals are never double-booked: a park targets an empty ordinal,
-- and the parked GO is released (becomes movable again) by its later from-cell
-- directive. Tracked by GO identity since from-cell directives carry card_go.
-- ============================================================
H.test("replay.plan: free-cell ordinals never double-booked", function(rules)
   local f, why = fixture(rules)
   if not f then return false, why end
   local directives = replay.plan(f.state, f.moves, f.go_map)

   local cell = {}          -- ord -> GO currently parked
   local parked_ord = {}    -- GO -> ord while parked
   for _, d in ipairs(directives) do
      if d.kind == "to_free_cell" then
         if cell[d.cell_ord] then
            return false, string.format("park into ord %d already holding %q", d.cell_ord, tostring(cell[d.cell_ord]))
         end
         cell[d.cell_ord] = d.card_go
         parked_ord[d.card_go] = d.cell_ord
      elseif (d.kind == "from_free_cell" or d.kind == "to_empty_tableau" or d.kind == "to_foundation")
             and parked_ord[d.card_go] then
         -- a parked card moving out frees its ordinal
         cell[parked_ord[d.card_go]] = nil
         parked_ord[d.card_go] = nil
      end
   end
   return true
end)

-- ============================================================
-- Directive identities match the GO's actual card: foundation suit, dragon suit,
-- and the flower are exactly what the reverse map says.
-- ============================================================
H.test("replay.plan: directive identities match the underlying card", function(rules)
   local f, why = fixture(rules)
   if not f then return false, why end
   local directives = replay.plan(f.state, f.moves, f.go_map)

   for _, d in ipairs(directives) do
      if d.kind == "to_foundation" then
         local c = f.id_card[d.card_go]
         if c.suit ~= d.suit then
            return false, string.format("to_foundation suit %q but GO is %q", tostring(d.suit), tostring(c.suit))
         end
      elseif d.kind == "dragon_collect" then
         if #d.card_gos ~= 4 then
            return false, "dragon_collect must move exactly 4 dragons, got " .. #d.card_gos
         end
         for _, go in ipairs(d.card_gos) do
            local c = f.id_card[go]
            if not (c.is_dragon) then return false, "dragon_collect GO is not a dragon: " .. tostring(go) end
         end
      elseif d.kind == "flower_auto" then
         if not f.id_card[d.card_go].is_flower then
            return false, "flower_auto GO is not the flower: " .. tostring(d.card_go)
         end
      end
   end
   return true
end)

-- ============================================================
-- `auto` flag marks exactly the moves the game performs itself (and must NOT be
-- double-driven): flower auto-fly + a value-2 reaching a tableau top. Foundation
-- moves of 3..10, and any move out of a free cell, are director-driven (not auto).
-- ============================================================
H.test("replay.plan: auto flag == game's own auto-fly moves only", function(rules)
   local f, why = fixture(rules)
   if not f then return false, why end
   local directives = replay.plan(f.state, f.moves, f.go_map)

   for _, d in ipairs(directives) do
      if d.kind == "flower_auto" then
         if d.auto ~= true then return false, "flower_auto must be auto=true" end
      elseif d.kind == "to_foundation" then
         local want = (d.from == "tableau" and d.value == 2)
         if (d.auto == true) ~= want then
            return false, string.format("to_foundation auto=%s for %s value %s (want %s)",
               tostring(d.auto), tostring(d.from), tostring(d.value), tostring(want))
         end
      elseif d.auto == true then
         return false, "no non-foundation/non-flower directive may be auto: " .. d.kind
      end
   end
   return true
end)

-- ============================================================
-- Terminal go_map is a win: every tableau column empty, all 3 free cells hold a
-- blocked dragon pile. (plan() mutates go_map in place to this terminal state.)
-- ============================================================
H.test("replay.plan: terminal go_map is a win (tableau empty, cells blocked)", function(rules)
   local f, why = fixture(rules)
   if not f then return false, why end
   replay.plan(f.state, f.moves, f.go_map)

   for col = 1, 8 do
      if #f.go_map.tableau[col] ~= 0 then
         return false, "tableau col " .. col .. " not empty at end: " .. #f.go_map.tableau[col] .. " GOs left"
      end
   end
   for i = 1, 3 do
      if f.go_map.free_cells[i] ~= replay.BLOCKED then
         return false, "free cell " .. i .. " is not a blocked dragon pile at end"
      end
   end
   return true
end)

-- ============================================================
-- Hand-built dragon_collect (independent of any seed's solution): 4 red dragons
-- on 4 tableau tops -> one directive with all 4 GOs + a target ordinal; go_map
-- tops popped, the chosen cell marked BLOCKED, the card beneath a dragon stays.
-- ============================================================
H.test("replay.plan: dragon_collect emits 4 GOs and blocks one cell", function(rules)
   local function drag() return { value = "d", suit = "red", is_dragon = true } end
   local function num(v)  return { value = v, suit = "blue" } end

   local state = {
      tableau = {
         { num(5), drag() },   -- col1: numeric beneath, dragon on top
         { drag() },
         { drag() },
         { drag() },
         {}, {}, {}, {},
      },
      free_cells = {
         { card = nil, is_blocked = false },
         { card = nil, is_blocked = false },
         { card = nil, is_blocked = false },
      },
      foundation_top    = { red = 1, blue = 1, green = 1 },
      flower_slot       = { occupied = false },
      dragons_collected = { red = false, blue = false, green = false },
      free_slots_counter = { red = 3, blue = 3, green = 3 },
      dragon_counter     = { red = 4, blue = 0, green = 0 },
   }

   local go_map = {
      tableau = {
         { "b5", "d1" }, { "d2" }, { "d3" }, { "d4" }, {}, {}, {}, {},
      },
      free_cells = {},
   }

   local directives = replay.plan(state, { { type = "dragon_collect", suit = "red" } }, go_map)
   if #directives ~= 1 then return false, "expected 1 directive, got " .. #directives end
   local d = directives[1]
   if d.kind ~= "dragon_collect" then return false, "wrong kind: " .. tostring(d.kind) end
   if #d.card_gos ~= 4 then return false, "expected 4 dragon GOs, got " .. #d.card_gos end

   -- the 4 dragon GOs (d1..d4) were collected; the numeric b5 stays in col1
   local collected = {}
   for _, go in ipairs(d.card_gos) do collected[go] = true end
   for _, id in ipairs({ "d1", "d2", "d3", "d4" }) do
      if not collected[id] then return false, "dragon GO " .. id .. " was not collected" end
   end
   if collected["b5"] then return false, "numeric card b5 was wrongly collected" end

   if #go_map.tableau[1] ~= 1 or go_map.tableau[1][1] ~= "b5" then
      return false, "col1 should retain only b5 after collect"
   end
   for _, col in ipairs({ 2, 3, 4 }) do
      if #go_map.tableau[col] ~= 0 then return false, "col " .. col .. " should be empty after collect" end
   end
   if d.cell_ord < 1 or d.cell_ord > 3 then return false, "cell_ord out of range: " .. tostring(d.cell_ord) end
   if go_map.free_cells[d.cell_ord] ~= replay.BLOCKED then
      return false, "target free cell " .. d.cell_ord .. " not marked BLOCKED"
   end
   return true
end)

-- ============================================================
-- C2: since C1 counts parked dragons, a collect can include cards sitting in
-- free cells. Their GOs must join card_gos exactly once, their go_map slots must
-- be cleared, and every cell that is NOT the host must be named in
-- release_cells — the glue (main.script) posts remove_card there, without which
-- the cell stays occupied by a card that has flown away.
-- ============================================================
H.test("replay.plan: dragon_collect takes parked GOs and names the cells to release", function(rules)
   local function drag() return { value = "d", suit = "red", is_dragon = true } end

   local state = {
      tableau = { { drag() }, { drag() }, {}, {}, {}, {}, {}, {} },
      free_cells = {
         { card = drag(),                            is_blocked = false },
         { card = { value = 7, suit = "blue" },      is_blocked = false },
         { card = drag(),                            is_blocked = false },
      },
      foundation_top    = { red = 1, blue = 1, green = 1 },
      flower_slot       = { occupied = false },
      dragons_collected = { red = false, blue = false, green = false },
      free_slots_counter = { red = 1, blue = 0, green = 0 },
      dragon_counter     = { red = 4, blue = 0, green = 0 },
   }
   local go_map = {
      tableau = { { "d1" }, { "d2" }, {}, {}, {}, {}, {}, {} },
      free_cells = { "d3", "b7", "d4" },
   }

   local directives = replay.plan(state, { { type = "dragon_collect", suit = "red" } }, go_map)
   local d = directives[1]
   if not d or d.kind ~= "dragon_collect" then
      return false, "expected a dragon_collect directive, got " .. tostring(d and d.kind)
   end

   local seen = {}
   for _, go in ipairs(d.card_gos) do
      if seen[go] then return false, "GO " .. go .. " appears twice in the pile" end
      seen[go] = true
   end
   for _, id in ipairs({ "d1", "d2", "d3", "d4" }) do
      if not seen[id] then return false, "dragon GO " .. id .. " is missing from the pile" end
   end
   if seen["b7"] then return false, "the unrelated 7_blue was swept into the pile" end
   if #d.card_gos ~= 4 then return false, "expected exactly 4 GOs, got " .. #d.card_gos end

   -- go_map: host BLOCKED, the other dragon cell empty, the stranger untouched
   if go_map.free_cells[d.cell_ord] ~= replay.BLOCKED then
      return false, "host cell " .. tostring(d.cell_ord) .. " not marked BLOCKED"
   end
   if go_map.free_cells[2] ~= "b7" then
      return false, "the 7_blue cell must be untouched"
   end
   local other = d.cell_ord == 1 and 3 or 1
   if go_map.free_cells[other] ~= nil then
      return false, "cell " .. other .. " still holds a GO that flew into the pile — duplicate/strand"
   end

   -- release_cells: exactly the non-host dragon cell
   local rel = d.release_cells or {}
   if #rel ~= 1 or rel[1] ~= other then
      return false, "release_cells must name exactly cell " .. other ..
         ", got {" .. table.concat(rel, ",") .. "}"
   end
   return true
end)

return H
