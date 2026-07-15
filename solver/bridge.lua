-- solver/bridge.lua — convert the live Defold board into a solver state.
--
-- The terminal watcher (solver/watch.lua) replays the solver's OWN deal. To watch
-- the solver play the PLAYER'S actual board we cannot share a seed (the game's
-- shuffle PRNG differs from the solver's). Instead main.script snapshots its board
-- and this module turns that snapshot into the exact state shape solver/rules.lua
-- expects, so rules.solve() runs on the real position.
--
-- SNAPSHOT CONTRACT (see test_bridge.lua for the canonical spec):
--   snap.tableau[c]    = array (c=1..8) of cards, bottom->top order, each
--                        { value=<2..10|"d"|"f">, suit=<"red"|"blue"|"green"|"flower"> }
--   snap.foundation    = { red=N, blue=N, green=N }   -- top value; 1 or nil = empty
--   snap.free_cells[i] = (i=1..3) nil/{} (empty) | {card={value,suit}} (parked) |
--                        {card={value="d",suit=S}, blocked=true} (collected dragon pile)
--   snap.flower        = <bool>                        -- flower collected
--
-- Only game->solver is implemented (pure, unit-tested). The reverse direction
-- (solver move -> Defold messages) lives in the game, not here.

local M = {}

-- One game card -> one solver card. Flags are DERIVED from value so the snapshot
-- need not carry is_dragon/is_flower (more robust than trusting the game's flags).
function M.card(gc)
   local v = gc.value
   if v == "f" or gc.is_flower then
      return { value = "f", suit = "flower", is_flower = true }
   end
   if v == "d" or gc.is_dragon then
      return { value = "d", suit = gc.suit, is_dragon = true }
   end
   return { value = v, suit = gc.suit }
end

-- Snapshot of the live board -> solver state (rules.lua shape).
function M.from_game(snap)
   -- Tableau: 8 columns, bottom->top (same order rules.deal produces).
   local tableau = {}
   for c = 1, 8 do
      tableau[c] = {}
      local col = (snap.tableau and snap.tableau[c]) or {}
      for _, gc in ipairs(col) do
         tableau[c][#tableau[c] + 1] = M.card(gc)
      end
   end

   -- Foundations: missing suit defaults to 1 (empty baseline, matching rules.deal).
   local f = snap.foundation or {}
   local foundation_top = { red = f.red or 1, blue = f.blue or 1, green = f.green or 1 }

   -- Free cells + the dual dragons_collected mapping:
   -- a blocked slot is a collected dragon pile -> it stays a card-bearing blocked
   -- slot AND sets dragons_collected[suit] (both, or the solver's gating breaks).
   local free_cells = {}
   local dragons_collected = { red = false, blue = false, green = false }
   for i = 1, 3 do
      local fc = snap.free_cells and snap.free_cells[i]
      if fc and fc.blocked then
         local suit = (fc.card and fc.card.suit) or fc.suit
         free_cells[i] = { card = { value = "d", suit = suit, is_dragon = true }, is_blocked = true }
         if suit then dragons_collected[suit] = true end
      elseif fc and fc.card then
         free_cells[i] = { card = M.card(fc.card), is_blocked = false }
      else
         free_cells[i] = { card = nil, is_blocked = false }
      end
   end

   return {
      tableau = tableau,
      foundation_top = foundation_top,
      free_cells = free_cells,
      flower_slot = { occupied = snap.flower and true or false },
      dragons_collected = dragons_collected,
      -- These two are recomputed from the board at every decision point in
      -- rules.legal_moves (compute_dragon_counter / compute_free_slots_counter) and
      -- are NOT part of state_hash, so deal-defaults are correct here; they exist
      -- only so rules.copy_state never nil-indexes.
      dragon_counter = { red = 0, blue = 0, green = 0 },
      free_slots_counter = { red = 3, blue = 3, green = 3 },
   }
end

return M
