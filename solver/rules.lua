-- solver/rules.lua
-- Pure Lua 5.4 — zero Defold deps.
-- Public API: deal, legal_moves, apply_move, is_win, can_auto_finish, can_move_to_foundation_safe
-- See SPEC.md for canonical rules.

local M = {}

-- ============================================================
-- 1. Card helpers
-- ============================================================

local function make_num(suit, val)
   return { value=val, suit=suit }
end

local function make_dragon(suit)
   return { value="d", suit=suit, is_dragon=true }
end

local function make_flower()
   return { value="f", suit="flower", is_flower=true }
end

-- can_stack(bottom, top):
--   bottom = the card already on the column (destination, HIGHER value)
--   top    = the incoming card being placed (LOWER value)
-- Returns true if top can be placed on bottom.
-- Rule: different suits, bottom.value == top.value + 1 (bottom is exactly one MORE)
-- Source: test_moves B1 comment "can_stack(bottom=5_blue, top=4_red) => 5==4+1 YES"
-- SPEC §3.1 formula "bottom.value == top.value - 1 (bottom is lower)" has inverted naming.
local function can_stack(bottom, top)
   if not bottom or not top then return false end
   if bottom.is_flower or bottom.is_dragon then return false end
   if top.is_flower or top.is_dragon then return false end
   if bottom.suit == top.suit then return false end
   if type(bottom.value) ~= "number" or type(top.value) ~= "number" then return false end
   return bottom.value == top.value + 1
end

-- ============================================================
-- 2. Deal
-- ============================================================

-- Build the 40-card deck
local function build_deck()
   local deck = {}
   local suits = { "red", "blue", "green" }

   -- Per-suit order, EXACTLY matching create_deck (main.script:62-76): for each
   -- suit emit its 9 numerics (2..10) then its 4 dragons, then the next suit.
   -- (The previous all-numerics-then-all-dragons order gave a different shuffled
   --  deck for the same seed — review composer-v2 P0.)
   for _, suit in ipairs(suits) do
      for v = 2, 10 do
         deck[#deck + 1] = make_num(suit, v)
      end
      for _ = 1, 4 do
         deck[#deck + 1] = make_dragon(suit)
      end
   end

   -- 1 flower card (last)
   deck[#deck + 1] = make_flower()

   return deck
end

-- Shuffle per SPEC §2.1: seed, 20 warmup, 3 descending Fisher-Yates passes
local function shuffle_deck(deck, seed)
   math.randomseed(seed)
   -- 20 warmup calls
   for _ = 1, 20 do math.random() end
   -- 3 Fisher-Yates passes
   for _ = 1, 3 do
      for i = #deck, 2, -1 do
         local j = math.random(1, i)
         deck[i], deck[j] = deck[j], deck[i]
      end
   end
end

-- Deal: 8 columns, each 5 cards.
-- Cards removed from END of shuffled deck (table.remove with no index).
-- COLUMN-MAJOR order matching the game source (main.script deal_cards):
--   outer loop: stack_index = 1..8 (column)
--   inner loop: card_index  = 1..5  (position within column)
-- Column 1 gets deck[40..36], column 2 gets deck[35..31], etc.
-- Position 1 in column = bottom card (first received).
function M.deal(seed)
   local deck = build_deck()
   shuffle_deck(deck, seed)

   local tableau = {}
   for i = 1, 8 do tableau[i] = {} end

   -- Column-major: fill each column fully before moving to the next.
   for col = 1, 8 do
      for _ = 1, 5 do
         local card = table.remove(deck) -- removes from end
         table.insert(tableau[col], card)
      end
   end

   return {
      tableau = tableau,
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

-- ============================================================
-- 3. Legal moves
-- ============================================================

-- Compute the start index of the maximal valid run at the top of a column.
-- col: array of cards (index 1 = bottom, index n = top)
-- Returns s such that col[s..n] is the maximal valid run from top.
local function maximal_run_start(col)
   local n = #col
   if n == 0 then return nil end
   local s = n
   while s > 1 and can_stack(col[s-1], col[s]) do
      s = s - 1
   end
   return s
end

-- Deep-copy a card (shallow, cards are flat tables)
local function copy_card(c)
   if c == nil then return nil end
   return {
      value     = c.value,
      suit      = c.suit,
      is_dragon = c.is_dragon,
      is_flower = c.is_flower,
   }
end

-- Deep-copy state (used by apply_move)
local function copy_state(state)
   -- tableau
   local new_tableau = {}
   for i = 1, 8 do
      new_tableau[i] = {}
      for j, card in ipairs(state.tableau[i]) do
         new_tableau[i][j] = copy_card(card)
      end
   end

   -- free_cells
   local new_fc = {}
   for i, fc in ipairs(state.free_cells) do
      new_fc[i] = { card=copy_card(fc.card), is_blocked=fc.is_blocked }
   end

   -- foundation_top, flower_slot, dragons_collected
   local new_ft = { red=state.foundation_top.red, blue=state.foundation_top.blue, green=state.foundation_top.green }
   local new_flower = { occupied=state.flower_slot.occupied }
   local new_dc = { red=state.dragons_collected.red, blue=state.dragons_collected.blue, green=state.dragons_collected.green }
   local new_dragon_counter = { red=state.dragon_counter.red, blue=state.dragon_counter.blue, green=state.dragon_counter.green }
   local new_fsc = { red=state.free_slots_counter.red, blue=state.free_slots_counter.blue, green=state.free_slots_counter.green }

   return {
      tableau          = new_tableau,
      foundation_top   = new_ft,
      free_cells       = new_fc,
      flower_slot      = new_flower,
      dragons_collected = new_dc,
      dragon_counter   = new_dragon_counter,
      free_slots_counter = new_fsc,
   }
end

-- Compute derived dragon_counter from current state:
-- counts dragons of each suit that are EXPOSED — tableau tops plus unblocked
-- free cells.
--
-- C1: an earlier comment here claimed TABLEAU-TOPS ONLY. That was wrong, and it
-- made the solver reject a collect the live game offers. The button counter is
-- incremented once per dragon that surfaces as a tableau top
-- (tableau_script -> dragon_button.script "send_counter_to_button", deduped by
-- card id) and is NEVER decremented — parking that dragon in a free cell does
-- not take it back. And a dragon can only reach a free cell FROM a tableau top
-- (cells start empty), while nothing can be stacked onto a dragon
-- (tableau_script.can_stack_cards rejects is_dragon on both sides), so it can
-- never be buried again. Therefore "counted by the game" == "on a tableau top
-- OR parked in a free cell".
-- A BLOCKED cell holds an already-collected pile: dragons_collected[suit] gates
-- that case, and the pile is not a loose dragon — do not count it.
local function compute_dragon_counter(state)
   local dc = { red=0, blue=0, green=0 }
   for i = 1, 8 do
      local col = state.tableau[i]
      if #col > 0 then
         local top = col[#col]
         if top.is_dragon then
            dc[top.suit] = dc[top.suit] + 1
         end
      end
   end
   for _, fc in ipairs(state.free_cells) do
      if fc.card and fc.card.is_dragon and not fc.is_blocked then
         dc[fc.card.suit] = dc[fc.card.suit] + 1
      end
   end
   return dc
end

-- Compute derived free_slots_counter from current state per SPEC §3.4:
-- Starts at 3; each free cell slot that is occupied (by any card) OR blocked
-- costs 1 from every suit's counter EXCEPT:
--   a blocked slot hosting a dragon of suit S does NOT cost suit S (it will host
--   the collected pile) — but since dragons_collected[S] will be true in that case
--   the dragon_collect move is already gated by dragons_collected check.
-- Simpler: free_slots_counter[S] = number of free cell slots that are available
-- for a dragon-collect of suit S.  A slot is available if:
--   - it is not blocked AND card == nil  (empty), OR
--   - it holds a dragon of suit S and is not blocked (will be the host slot)
local function compute_free_slots_counter(state)
   local fsc = { red=0, blue=0, green=0 }
   local suits = { "red", "blue", "green" }
   for _, suit in ipairs(suits) do
      for _, fc in ipairs(state.free_cells) do
         if not fc.is_blocked then
            if fc.card == nil then
               -- empty unblocked slot: available for any suit
               fsc[suit] = fsc[suit] + 1
            elseif fc.card.is_dragon and fc.card.suit == suit then
               -- slot already holds a same-suit dragon: can host the collect
               fsc[suit] = fsc[suit] + 1
            end
         end
      end
   end
   return fsc
end

function M.legal_moves(state)
   local moves = {}
   local tableau = state.tableau

   -- Helper: find first unoccupied, unblocked free cell index
   local function first_free_cell()
      for i, fc in ipairs(state.free_cells) do
         if not fc.is_blocked and fc.card == nil then return i end
      end
      return nil
   end

   -- Helper: check if column c (index) is empty
   local function col_empty(c)
      return #tableau[c] == 0
   end

   -- Helper: top card of column c, or nil
   local function col_top(c)
      local col = tableau[c]
      if #col == 0 then return nil end
      return col[#col]
   end

   -- ---- Foundation moves from tableau tops ----
   for from_col = 1, 8 do
      local card = col_top(from_col)
      if card and not card.is_dragon and not card.is_flower then
         if type(card.value) == "number" then
            if card.value == state.foundation_top[card.suit] + 1 then
               moves[#moves + 1] = { type="to_foundation", from_col=from_col }
            end
         end
      end
   end

   -- ---- Foundation moves from free cells ----
   for slot_i, fc in ipairs(state.free_cells) do
      if fc.card and not fc.is_blocked then
         local card = fc.card
         if not card.is_dragon and not card.is_flower then
            if type(card.value) == "number" then
               if card.value == state.foundation_top[card.suit] + 1 then
                  moves[#moves + 1] = { type="to_foundation", from_free_cell=slot_i }
               end
            end
         end
      end
   end

   -- ---- Dragon collect (use derived counters, not stale stored state) ----
   local suits = { "red", "blue", "green" }
   local dragon_counter = compute_dragon_counter(state)
   local free_slots_counter = compute_free_slots_counter(state)
   for _, suit in ipairs(suits) do
      if not state.dragons_collected[suit]
         and dragon_counter[suit] == 4
         and free_slots_counter[suit] > 0 then
         moves[#moves + 1] = { type="dragon_collect", suit=suit }
      end
   end

   -- ---- To free cell (any top tableau card) ----
   local fc_slot = first_free_cell()
   if fc_slot then
      for from_col = 1, 8 do
         local card = col_top(from_col)
         -- free_cell.script:46-49 accepts ANY card type (B5). The flower is handled
         -- by the mandatory auto-fly (apply_mandatory_tracked) before branching, so it is
         -- never a tableau top at a search node — no guard needed here.
         if card then
            moves[#moves + 1] = { type="to_free_cell", from_col=from_col, to_slot=fc_slot }
         end
      end
   end

   -- ---- From free cell → tableau ----
   for slot_i, fc in ipairs(state.free_cells) do
      if fc.card and not fc.is_blocked then
         local fcard = fc.card
         -- Try to stack onto each tableau column
         for to_col = 1, 8 do
            if col_empty(to_col) then
               moves[#moves + 1] = { type="from_free_cell", from_slot=slot_i, to_col=to_col }
            else
               local target = col_top(to_col)
               if can_stack(target, fcard) then
                  moves[#moves + 1] = { type="from_free_cell", from_slot=slot_i, to_col=to_col }
               end
            end
         end
      end
   end

   -- ---- Tableau single-card moves ----
   for from_col = 1, 8 do
      local col = tableau[from_col]
      if #col > 0 then
         local top = col[#col]
         for to_col = 1, 8 do
            if from_col ~= to_col then
               if col_empty(to_col) then
                  -- Any single card can go to an empty column
                  -- We only generate single-card move here if the run length is exactly 1
                  -- (multi-card runs to empty columns are handled as multi_to_tableau below)
                  -- Actually per test B3: single-card top to empty is "to_empty_tableau" type
                  -- But multi-card run to empty is "multi_to_tableau".
                  -- We need to emit single-card move as "tableau_to_tableau" or "to_empty_tableau"
                  -- Check B1: col1..col4 all go to empty cols 5-8 via to_free_cell
                  -- B5 checks to_free_cell with from_col field only.
                  -- For clarity, emit tableau_to_tableau for single card to any target (empty or not).
                  -- The tests use has_move checking specific fields; let's see what's needed:
                  -- B1 checks { type="tableau_to_tableau", from_col=2, to_col=1 }
                  -- B3 checks { type="multi_to_tableau", from_col=1, to_col=4 } for empty col
                  -- So single card to empty col must also be emitted somehow.
                  -- Let's emit "tableau_to_tableau" for single-card to occupied, and
                  -- "to_empty_tableau" for single-card to empty (only if run size == 1).
                  -- But B3 asserts multi_to_tableau to empty. Let's be safe and emit both types
                  -- when applicable. Actually re-reading: B3 only tests multi_to_tableau for run.
                  -- Single top card to empty: emit tableau_to_tableau (the tests only check
                  -- specific from/to combos). Let's just emit "tableau_to_tableau" for all single moves.
                  moves[#moves + 1] = { type="tableau_to_tableau", from_col=from_col, to_col=to_col }
               else
                  local target = col_top(to_col)
                  if can_stack(target, top) then
                     moves[#moves + 1] = { type="tableau_to_tableau", from_col=from_col, to_col=to_col }
                  end
               end
            end
         end
      end
   end

   -- ---- Multi-card run moves ----
   for from_col = 1, 8 do
      local col = tableau[from_col]
      local n = #col
      if n >= 2 then
         local s = maximal_run_start(col)
         -- s is the start of the maximal valid run
         -- Only enumerate runs starting at s <= p <= n-1 (at least 2 cards in run)
         for p = s, n - 1 do
            -- Run is col[p..n], run bottom is col[p]
            local run_bottom = col[p]
            for to_col = 1, 8 do
               if to_col ~= from_col then
                  if col_empty(to_col) then
                     -- Run can go to any empty column
                     moves[#moves + 1] = { type="multi_to_tableau", from_col=from_col, to_col=to_col, run_start=p, run_size=n-p+1 }
                  else
                     local target = col_top(to_col)
                     if can_stack(target, run_bottom) then
                        moves[#moves + 1] = { type="multi_to_tableau", from_col=from_col, to_col=to_col, run_start=p, run_size=n-p+1 }
                     end
                  end
               end
            end
         end
      end
   end

   return moves
end

-- ============================================================
-- 4. Win condition
-- ============================================================

function M.is_win(state)
   return state.foundation_top.red   == 10
      and state.foundation_top.blue  == 10
      and state.foundation_top.green == 10
      and state.flower_slot.occupied == true
end

-- ============================================================
-- 5. Apply move
-- ============================================================

function M.apply_move(state, move)
   local s = copy_state(state)

   if move.type == "to_foundation" then
      if move.from_col then
         local col = s.tableau[move.from_col]
         local card = table.remove(col)
         s.foundation_top[card.suit] = card.value
      elseif move.from_free_cell then
         local fc = s.free_cells[move.from_free_cell]
         local card = fc.card
         s.foundation_top[card.suit] = card.value
         fc.card = nil
      end

   elseif move.type == "to_free_cell" then
      local col = s.tableau[move.from_col]
      local card = table.remove(col)
      -- Find first available free cell
      for i, fc in ipairs(s.free_cells) do
         if not fc.is_blocked and fc.card == nil then
            fc.card = card
            break
         end
      end

   elseif move.type == "from_free_cell" then
      local fc = s.free_cells[move.from_slot]
      local card = fc.card
      fc.card = nil
      table.insert(s.tableau[move.to_col], card)

   elseif move.type == "tableau_to_tableau" then
      local from_col = s.tableau[move.from_col]
      local card = table.remove(from_col)
      table.insert(s.tableau[move.to_col], card)

   elseif move.type == "multi_to_tableau" then
      local from_col = s.tableau[move.from_col]
      local p = move.run_start
      local n = #from_col
      -- Extract cards from p to n
      local run = {}
      for i = p, n do
         run[#run + 1] = from_col[i]
      end
      -- Remove from source column
      for i = n, p, -1 do
         table.remove(from_col, i)
      end
      -- Add to target column
      for _, card in ipairs(run) do
         table.insert(s.tableau[move.to_col], card)
      end

   elseif move.type == "dragon_collect" then
      local suit = move.suit
      -- Find target free cell: prefer one holding a dragon of this suit,
      -- otherwise take first empty unblocked slot
      local target_slot = nil
      for i, fc in ipairs(s.free_cells) do
         if fc.card and fc.card.is_dragon and fc.card.suit == suit and not fc.is_blocked then
            target_slot = i
            break
         end
      end
      if not target_slot then
         for i, fc in ipairs(s.free_cells) do
            if not fc.is_blocked and fc.card == nil then
               target_slot = i
               break
            end
         end
      end

      -- Remove this suit's dragons from tableau tops...
      for col_i = 1, 8 do
         local col = s.tableau[col_i]
         if #col > 0 then
            local top = col[#col]
            if top.is_dragon and top.suit == suit then
               table.remove(col)
            end
         end
      end
      -- ...and from free cells (C2). compute_dragon_counter counts parked
      -- dragons, so the gate can fire with 1-3 of them in cells; every one of
      -- them joins the pile. Clearing only the target slot would strand the
      -- others as phantom occupied cells.
      local parked = 0
      for _, fc in ipairs(s.free_cells) do
         if fc.card and fc.card.is_dragon and fc.card.suit == suit and not fc.is_blocked then
            fc.card = nil
            parked = parked + 1
         end
      end

      -- Place and block the target free cell
      if target_slot then
         s.free_cells[target_slot].card = make_dragon(suit)
         s.free_cells[target_slot].is_blocked = true
      end

      s.dragons_collected[suit] = true
      -- Mirror the game's per-suit slot accounting (free_cell.script
      -- send_to_dragon_buttons): a cell occupied by ANY card already costs the
      -- other suits 1. Cells we touched go from `parked` occupied to exactly 1
      -- (the blocked pile), so the other suits get back parked-1 — which is the
      -- familiar -1 when nothing was parked, and 0 for the common single-parked
      -- collect (that cell was already paid for).
      -- (Derived compute_free_slots_counter is what legal_moves actually reads;
      -- this stored field is kept in sync for snapshot/parity consumers.)
      local delta = parked - 1
      for _, s_name in ipairs({"red","blue","green"}) do
         if s_name ~= suit then
            s.free_slots_counter[s_name] = s.free_slots_counter[s_name] + delta
         end
      end

   elseif move.type == "flower_auto" then
      -- Find flower on top of any tableau column and move to flower slot
      for col_i = 1, 8 do
         local col = s.tableau[col_i]
         if #col > 0 and col[#col].is_flower then
            table.remove(col)
            s.flower_slot.occupied = true
            break
         end
      end

   elseif move.type == "to_empty_tableau" then
      -- Single card to empty tableau (from free cell or tableau)
      if move.from_col then
         local card = table.remove(s.tableau[move.from_col])
         table.insert(s.tableau[move.to_col], card)
      elseif move.from_free_cell then
         local fc = s.free_cells[move.from_free_cell]
         local card = fc.card
         fc.card = nil
         table.insert(s.tableau[move.to_col], card)
      end
   end

   return s
end

-- ============================================================
-- 6. can_auto_finish (as implemented in main.script §5.1)
-- ============================================================

function M.can_auto_finish(state)
   -- Check no live (non-blocked) dragon in any free cell
   for _, fc in ipairs(state.free_cells) do
      if fc.card and fc.card.is_dragon and not fc.is_blocked then
         return false
      end
   end

   -- Remaining tableau cards: no dragons/flower, and each value is safe
   -- (same predicate as main.script can_auto_finish: v <= min_other+1).
   local remaining = 0
   for i = 1, 8 do
      local col = state.tableau[i]
      for _, card in ipairs(col) do
         remaining = remaining + 1
         if card.is_dragon or card.is_flower then
            return false
         end
         local v = card.value
         if type(v) == "number" then
            local min_other = 10
            for suit, val in pairs(state.foundation_top) do
               if suit ~= card.suit then
                  min_other = math.min(min_other, val)
               end
            end
            if v > min_other + 1 then
               return false
            end
         end
      end
   end
   if remaining == 0 then return false end

   return true
end

-- ============================================================
-- 7. Safe foundation move predicate (SPEC §5.2)
-- ============================================================

-- Returns true if card can safely be moved to foundation
-- (i.e. no other suit still needs this card's value - 1 for stacking)
function M.can_move_to_foundation_safe(card, foundation_top)
   if card.is_dragon or card.is_flower then return false end
   if type(card.value) ~= "number" then return false end
   if card.value ~= foundation_top[card.suit] + 1 then return false end

   -- Safe check: no other suit is more than 1 behind this card's value
   local min_other = 10
   local suits = { "red", "blue", "green" }
   for _, suit in ipairs(suits) do
      if suit ~= card.suit then
         if foundation_top[suit] < min_other then
            min_other = foundation_top[suit]
         end
      end
   end
   return card.value <= min_other + 1
end

-- ============================================================
-- 8. Solver: DFS/IDDFS with transposition table and budget
-- ============================================================

-- Goal: all 8 tableau columns empty AND all free cells empty-or-blocked.
-- This works for mini-deals (no flower/dragons) AND full deals (after flower/dragon cleanup).
-- NOTE: does NOT require is_win (flower_slot check) — the goal is exhausting all tableau cards.
local function is_goal(state)
   -- All tableau columns must be empty
   for i = 1, 8 do
      if #state.tableau[i] > 0 then return false end
   end
   -- All free cells must be empty or blocked (no live card parked)
   for _, fc in ipairs(state.free_cells) do
      if fc.card ~= nil and not fc.is_blocked then return false end
   end
   return true
end

-- Canonical state hash for transposition table.
-- Serializes the mutable parts of state that affect reachability.
local function state_hash(state)
   local parts = {}

   -- Tableau columns. Columns are INTERCHANGEABLE (no per-column property), so
   -- two states that differ only by which column holds which pile are equivalent
   -- for solvability. Sort the column strings to canonicalize that permutation
   -- symmetry (review #4) — collapses duplicate search states, cutting timeouts.
   -- Safe because the hash is used only for the visited/transposition set.
   local col_strs = {}
   for i = 1, 8 do
      local col_parts = {}
      for _, card in ipairs(state.tableau[i]) do
         col_parts[#col_parts + 1] = card.suit .. ":" .. tostring(card.value)
      end
      col_strs[i] = table.concat(col_parts, ",")
   end
   table.sort(col_strs)
   for _, cs in ipairs(col_strs) do
      parts[#parts + 1] = cs
      parts[#parts + 1] = ";"
   end
   parts[#parts + 1] = "|"

   -- Foundation tops
   parts[#parts + 1] = "F" .. state.foundation_top.red .. "," .. state.foundation_top.blue .. "," .. state.foundation_top.green
   parts[#parts + 1] = "|"

   -- Free cells (card or empty or blocked). Slots are INTERCHANGEABLE too — sort
   -- to canonicalize (review #4). Blocked-slot identity doesn't matter; which
   -- colours are collected is tracked separately in dragons_collected below.
   local fc_strs = {}
   for _, fc in ipairs(state.free_cells) do
      if fc.is_blocked then
         fc_strs[#fc_strs + 1] = "B"
      elseif fc.card then
         fc_strs[#fc_strs + 1] = "C:" .. fc.card.suit .. ":" .. tostring(fc.card.value)
      else
         fc_strs[#fc_strs + 1] = "_"
      end
   end
   table.sort(fc_strs)
   for _, s in ipairs(fc_strs) do
      parts[#parts + 1] = s
      parts[#parts + 1] = ","
   end
   parts[#parts + 1] = "|"

   -- Flower slot
   parts[#parts + 1] = state.flower_slot.occupied and "FL1" or "FL0"
   parts[#parts + 1] = "|"

   -- Dragons collected
   parts[#parts + 1] = (state.dragons_collected.red and "1" or "0")
                     .. (state.dragons_collected.blue and "1" or "0")
                     .. (state.dragons_collected.green and "1" or "0")

   return table.concat(parts, "")
end

-- Version that tracks moves applied (returns new state + move list)
local function apply_mandatory_tracked(state)
   local moves_applied = {}
   local changed = true
   local s = state

   while changed do
      changed = false
      repeat -- Lua 5.1 has no `continue`/`goto`; `break` here = "restart while loop"

      -- 1. Flower auto-fly
      for col_i = 1, 8 do
         local col = s.tableau[col_i]
         if #col > 0 and col[#col].is_flower then
            local move = { type="flower_auto" }
            s = M.apply_move(s, move)
            moves_applied[#moves_applied + 1] = move
            changed = true
            break
         end
      end
      if changed then break end

      -- 2. Value-2 auto-move to foundation
      for col_i = 1, 8 do
         local col = s.tableau[col_i]
         if #col > 0 then
            local top = col[#col]
            if type(top.value) == "number" and top.value == 2 then
               local move = { type="to_foundation", from_col=col_i }
               s = M.apply_move(s, move)
               moves_applied[#moves_applied + 1] = move
               changed = true
               break
            end
         end
      end
      if changed then break end

      -- 3. Safe foundation moves from tableau tops
      for col_i = 1, 8 do
         local col = s.tableau[col_i]
         if #col > 0 then
            local top = col[#col]
            if not top.is_dragon and not top.is_flower then
               if M.can_move_to_foundation_safe(top, s.foundation_top) then
                  local move = { type="to_foundation", from_col=col_i }
                  s = M.apply_move(s, move)
                  moves_applied[#moves_applied + 1] = move
                  changed = true
                  break
               end
            end
         end
      end
      if changed then break end

      -- 4b. Safe foundation moves from free cells
      for slot_i, fc in ipairs(s.free_cells) do
         if fc.card and not fc.is_blocked then
            if M.can_move_to_foundation_safe(fc.card, s.foundation_top) then
               local move = { type="to_foundation", from_free_cell=slot_i }
               s = M.apply_move(s, move)
               moves_applied[#moves_applied + 1] = move
               changed = true
               break
            end
         end
      end

      until true
   end

   return s, moves_applied
end

function M.forced_moves(state)
   local _, moves = apply_mandatory_tracked(state)
   return moves
end

-- Flatten a nested path into a flat list of moves
local function flatten_path(path_node)
   local result = {}
   local node = path_node
   -- path_node is a linked list: { move=..., prev=... }
   -- We need to collect in forward order, so traverse to a stack then reverse
   local stack = {}
   while node do
      if node.move then
         stack[#stack + 1] = node.move
      end
      node = node.prev
   end
   -- Reverse to get forward order
   for i = #stack, 1, -1 do
      result[#result + 1] = stack[i]
   end
   return result
end

-- DFS with transposition table and node budget.
-- Returns (path_table, status_string) where:
--   path_table = list of moves (truthy) on success
--   false, "unsolvable" if search exhausted
--   false, "timeout" if budget exceeded
function M.solve(initial_state, opts)
   opts = opts or {}
   local node_budget = opts.node_budget or 50000
   local nodes_visited = 0

   -- Apply mandatory moves to initial state first
   local start_state, start_moves = apply_mandatory_tracked(initial_state)

   -- Check if already solved after mandatory moves
   if is_goal(start_state) then
      return start_moves, "solved"
   end

   -- Transposition table (closed set of visited state hashes)
   local visited = {}
   visited[state_hash(start_state)] = true

   -- DFS stack: each entry = { state=..., path=linked_list_node, branching_moves=..., idx=1 }
   -- linked_list_node = { move=move_obj, prev=parent_node }
   -- We use an explicit stack to avoid Lua stack overflow on deep recursion.

   -- Build initial branching moves
   local initial_branch_moves = M.legal_moves(start_state)

   local dfs_stack = {
      {
         state  = start_state,
         path_node = nil, -- root has no move
         branch_moves = initial_branch_moves,
         idx    = 1,
      }
   }

   -- Pre-compute start_moves as a path prefix (linked list)
   -- For simplicity, we flatten at the end. Store start_moves as prefix.
   local prefix_moves = start_moves

   while #dfs_stack > 0 do
      local frame = dfs_stack[#dfs_stack]

      if frame.idx > #frame.branch_moves then
         -- Exhausted all moves at this level; backtrack
         dfs_stack[#dfs_stack] = nil
      else
         local move = frame.branch_moves[frame.idx]
         frame.idx = frame.idx + 1

         nodes_visited = nodes_visited + 1
         if nodes_visited > node_budget then
            return false, "timeout"
         end

         -- Apply the branch move
         local next_state = M.apply_move(frame.state, move)

         -- Apply mandatory moves on top
         local next_s, mand_moves = apply_mandatory_tracked(next_state)

         -- Build path node for this branch move
         local new_path_node = { move=move, prev=frame.path_node }
         -- Attach mandatory moves as additional path nodes
         local cur_node = new_path_node
         for _, mm in ipairs(mand_moves) do
            cur_node = { move=mm, prev=cur_node }
         end

         -- Check transposition
         local h = state_hash(next_s)
         if not visited[h] then
            visited[h] = true

            -- Check goal
            if is_goal(next_s) then
               -- Reconstruct full path
               local branch_path = flatten_path(cur_node)
               local full_path = {}
               for _, m in ipairs(prefix_moves) do
                  full_path[#full_path + 1] = m
               end
               for _, m in ipairs(branch_path) do
                  full_path[#full_path + 1] = m
               end
               return full_path, "solved"
            end

            -- Push new DFS frame
            local next_branch_moves = M.legal_moves(next_s)
            dfs_stack[#dfs_stack + 1] = {
               state        = next_s,
               path_node    = cur_node,
               branch_moves = next_branch_moves,
               idx          = 1,
            }
         end
      end
   end

   return false, "unsolvable"
end

return M
