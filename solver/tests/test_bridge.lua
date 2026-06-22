-- test_bridge.lua — tests for solver/bridge.lua (game board -> solver state).
--
-- The bridge converts a plain-Lua SNAPSHOT of the live Defold board (produced
-- inside main.script) into the exact state shape solver/rules.lua expects, so the
-- solver can solve the player's ACTUAL board (not a PRNG-matched seed).
--
-- SNAPSHOT CONTRACT (what main.script must produce):
--   snap.tableau[c]    = array (c=1..8) of cards, bottom->top order, each
--                        { value=<2..10|"d"|"f">, suit=<"red"|"blue"|"green"|"flower"> }
--   snap.foundation    = { red=N, blue=N, green=N }  -- top value; 1 or nil = empty
--   snap.free_cells[i] = (i=1..3) one of:
--                          nil / {}                      -- empty slot
--                          { card={value,suit} }         -- a parked card
--                          { card={value="d",suit=S}, blocked=true }  -- collected dragon pile
--   snap.flower        = <bool>                          -- flower collected
--
-- Only game->solver is unit-tested here (it is pure Lua). The reverse direction
-- (solver move -> Defold messages) is glue tested by running the real game.

local new_harness = require("solver.tests.harness")
local bridge = require("solver.bridge")
local H = new_harness()

-- Deep structural compare of two solver cards (ignores extra fields).
local function card_eq(a, b)
   if a == nil and b == nil then return true end
   if a == nil or b == nil then return false end
   return a.value == b.value and a.suit == b.suit
      and (a.is_dragon and true or false) == (b.is_dragon and true or false)
      and (a.is_flower and true or false) == (b.is_flower and true or false)
end

-- Convert a solver state into a game-style snapshot (oracle for round-trip).
local function state_to_snapshot(st)
   local snap = { tableau = {}, foundation = {}, free_cells = {}, flower = st.flower_slot.occupied }
   for c = 1, 8 do
      snap.tableau[c] = {}
      for _, card in ipairs(st.tableau[c]) do
         snap.tableau[c][#snap.tableau[c] + 1] = { value = card.value, suit = card.suit }
      end
   end
   snap.foundation = { red = st.foundation_top.red, blue = st.foundation_top.blue, green = st.foundation_top.green }
   for i = 1, 3 do
      local fc = st.free_cells[i]
      if fc.is_blocked then
         snap.free_cells[i] = { card = { value = fc.card.value, suit = fc.card.suit }, blocked = true }
      elseif fc.card then
         snap.free_cells[i] = { card = { value = fc.card.value, suit = fc.card.suit } }
      else
         snap.free_cells[i] = {}
      end
   end
   return snap
end

-- ============================================================
-- card mapping: numeric / dragon / flower, flags derived from value
-- ============================================================
H.test("bridge.from_game: maps numeric, dragon, flower cards (derives flags)", function(rules)
   local snap = {
      tableau = {
         { { value = 5, suit = "red" } },          -- numeric
         { { value = "d", suit = "blue" } },       -- dragon, no flag given
         { { value = "f", suit = "flower" } },     -- flower, no flag given
         {}, {}, {}, {}, {},
      },
   }
   local st = bridge.from_game(snap)
   if not card_eq(st.tableau[1][1], { value = 5, suit = "red" }) then
      return false, "numeric card mismatch"
   end
   if not card_eq(st.tableau[2][1], { value = "d", suit = "blue", is_dragon = true }) then
      return false, "dragon card not flagged is_dragon"
   end
   if not card_eq(st.tableau[3][1], { value = "f", suit = "flower", is_flower = true }) then
      return false, "flower card not flagged is_flower"
   end
   return true
end)

-- ============================================================
-- collected dragons: blocked free cell -> is_blocked + dragons_collected[suit]
-- (the dual-mapping that is easy to get wrong)
-- ============================================================
H.test("bridge.from_game: collected dragons set is_blocked AND dragons_collected[suit]", function(rules)
   local snap = {
      tableau = { {}, {}, {}, {}, {}, {}, {}, {} },
      free_cells = {
         { card = { value = "d", suit = "red" }, blocked = true },  -- collected red pile
         {},                                                        -- empty
         { card = { value = 7, suit = "green" } },                  -- a parked card
      },
   }
   local st = bridge.from_game(snap)
   if not st.free_cells[1].is_blocked then return false, "blocked slot not marked is_blocked" end
   if not (st.free_cells[1].card and st.free_cells[1].card.is_dragon) then
      return false, "blocked slot should host a dragon card"
   end
   if st.dragons_collected.red ~= true then return false, "dragons_collected.red should be true" end
   if st.dragons_collected.blue ~= false or st.dragons_collected.green ~= false then
      return false, "only red should be collected"
   end
   if st.free_cells[2].card ~= nil or st.free_cells[2].is_blocked then return false, "slot 2 should be empty" end
   if not card_eq(st.free_cells[3].card, { value = 7, suit = "green" }) then
      return false, "parked card mismatch in slot 3"
   end
   if st.free_cells[3].is_blocked then return false, "parked slot must not be blocked" end
   return true
end)

-- ============================================================
-- foundation + flower + empty defaults
-- ============================================================
H.test("bridge.from_game: foundation tops, flower occupancy, empty defaults", function(rules)
   local snap = {
      tableau = { {}, {}, {}, {}, {}, {}, {}, {} },
      foundation = { red = 5, blue = 2 },  -- green omitted -> default empty (1)
      flower = true,
   }
   local st = bridge.from_game(snap)
   if st.foundation_top.red ~= 5 or st.foundation_top.blue ~= 2 then return false, "foundation tops wrong" end
   if st.foundation_top.green ~= 1 then return false, "omitted foundation suit should default to 1" end
   if st.flower_slot.occupied ~= true then return false, "flower should be occupied" end
   -- all free cells default empty
   for i = 1, 3 do
      if st.free_cells[i].card ~= nil or st.free_cells[i].is_blocked then
         return false, "free cell " .. i .. " should default to empty"
      end
   end
   return true
end)

-- ============================================================
-- counters present (so rules.apply_move / copy_state never nil-index)
-- ============================================================
H.test("bridge.from_game: derived counters present; state usable by solver", function(rules)
   local snap = { tableau = { {}, {}, {}, {}, {}, {}, {}, {} } }
   local st = bridge.from_game(snap)
   if type(st.dragon_counter) ~= "table" then return false, "dragon_counter missing" end
   if type(st.free_slots_counter) ~= "table" then return false, "free_slots_counter missing" end
   -- legal_moves must run without error on a bridged state
   local ok, moves = pcall(rules.legal_moves, st)
   if not ok then return false, "legal_moves errored on bridged state: " .. tostring(moves) end
   if type(moves) ~= "table" then return false, "legal_moves did not return a table" end
   return true
end)

-- ============================================================
-- round-trip oracle: solver deal -> snapshot -> from_game == original deal
-- ============================================================
H.test("bridge.from_game: round-trips a full deal back to an equivalent state", function(rules)
   local orig = rules.deal(123)
   local snap = state_to_snapshot(orig)
   local st = bridge.from_game(snap)

   -- tableau columns identical
   for c = 1, 8 do
      if #st.tableau[c] ~= #orig.tableau[c] then return false, "column " .. c .. " size differs" end
      for r = 1, #orig.tableau[c] do
         if not card_eq(st.tableau[c][r], orig.tableau[c][r]) then
            return false, "card mismatch at col " .. c .. " row " .. r
         end
      end
   end
   -- foundation, flower, dragons
   for _, s in ipairs({ "red", "blue", "green" }) do
      if st.foundation_top[s] ~= orig.foundation_top[s] then return false, "foundation " .. s .. " differs" end
      if st.dragons_collected[s] ~= orig.dragons_collected[s] then return false, "dragons_collected " .. s .. " differs" end
   end
   if st.flower_slot.occupied ~= orig.flower_slot.occupied then return false, "flower differs" end
   -- free cells all empty in a fresh deal
   for i = 1, 3 do
      if st.free_cells[i].card ~= nil or st.free_cells[i].is_blocked then
         return false, "free cell " .. i .. " should be empty after deal round-trip"
      end
   end

   -- And the bridged deal must be solvable to the same verdict the solver gives
   -- on its own deal(123) — proves the bridged state is genuinely equivalent.
   local _, status_orig = rules.solve(rules.deal(123), { node_budget = 60000 })
   local _, status_bridged = rules.solve(st, { node_budget = 60000 })
   if status_orig ~= status_bridged then
      return false, "solve verdict differs: orig=" .. tostring(status_orig) .. " bridged=" .. tostring(status_bridged)
   end
   return true
end)

return H
