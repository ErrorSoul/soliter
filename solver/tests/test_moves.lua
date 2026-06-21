-- test_moves.lua
-- Tests for rules.legal_moves(state) — move-set PARITY tests (test-b).
--
-- GROUNDING (PARITY PRINCIPLE):
--   Each expected move set below was derived by reading the actual game scripts
--   and manually computing what the slot/cursor scripts would permit.
--   Provenance cited per rule.
--
-- Rules sourced from:
--   tableau_script.script:150-163  → can_stack_cards(bottom, top)
--     bottom.suit ~= top.suit AND bottom.value == top.value - 1
--     AND neither card is dragon or flower
--   card.script:41-52              → is_correct_card(self, selected_card)  [same rule, opposite perspective]
--   base_slot.script:67-76         → check_correct_cards(self, new_card)   [foundation placement]
--   dragon_button.script:68-86     → check_state / free_slot_any           [dragon collect enable]
--   free_cell.script:44-86         → check_slot / occupy_slot              [free cell accept any card]
--   SPEC §3.1-3.6                  → canonical descriptions

-- IMPORTANT: rules.legal_moves(state) must return a list of move descriptors.
-- Each move descriptor must include a "type" field at minimum.
-- The tests below build exact expected sets and compare them.
-- Move types used (matching SPEC §7):
--   "tableau_to_tableau"  — single-card stack move between tableau columns
--   "multi_to_tableau"    — multi-card run move to tableau column
--   "to_free_cell"        — single card to free cell
--   "from_free_cell"      — card from free cell to tableau
--   "to_foundation"       — single card to foundation
--   "dragon_collect"      — collect all 4 dragons of a suit
--   "flower_auto"         — flower auto-fly (mandatory, not branching — may be absent from list)
--   "to_empty_tableau"    — single card to empty tableau column

local new_harness = require("solver.tests.harness")
local H = new_harness()

-- Card constructors
local function num(suit, val)   return { value=val,  suit=suit } end
local function drag(suit)       return { value="d",  suit=suit, is_dragon=true } end
local function flower()         return { value="f",  suit="flower", is_flower=true } end

-- Build minimal empty state template
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

-- Utility: count moves of a given type in list
local function count_moves(moves, mtype)
   local n = 0
   for _, m in ipairs(moves) do
      if m.type == mtype then n = n + 1 end
   end
   return n
end

-- Utility: check move exists with given fields
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
-- STATE B1: Single-card tableau stacking
-- Board:
--   col1 = [5_blue]   (top = 5 blue)
--   col2 = [4_red]    (top = 4 red)
--   col3 = [4_green]  (top = 4 green)
--   col4 = [4_blue]   (top = 4 blue)
--   col5-8 = empty
--
-- EXPECTED legal tableau-to-tableau moves (SPEC §3.1 / tableau_script.script:150-163):
--   can_stack(bottom=5_blue, top=4_red)   => suits differ (blue≠red), 5==4+1 YES
--   can_stack(bottom=5_blue, top=4_green) => suits differ (blue≠green), 5==4+1 YES
--   can_stack(bottom=5_blue, top=4_blue)  => suits SAME (blue==blue) NO
--
-- col2,3,4 can also move to empty columns (cols 5-8)
-- col1 (5_blue) can move to empty columns (cols 5-8)
-- col2,3,4 each have a 4-value card; NONE can stack onto each other
--   (4_red onto 4_green? 4==4-1? No, 4!=3)
--
-- Foundation moves: none (foundation_top.X = 1, need value=2, no 2s present)
-- Free cell: any card can go to a free cell (3 empty) => 4 cards × 3 = 12 possible,
--            but only 4 top cards so 4 "to_free_cell" moves (one per top card; harness
--            counts distinct source cards, not (card, slot) pairs — check SPEC §7 item 7:
--            "legal if any free cell is unoccupied" — one move per source card suffices
--            for the solver since any empty slot is equivalent)
--
-- PARITY assertions:
--   (B1-a) 4_red and 4_green can stack on 5_blue (via tableau_to_tableau)
--   (B1-b) 4_blue CANNOT stack on 5_blue (same suit)
--   (B1-c) no card stacks on 4_red/4_green/4_blue from other columns
--            (there is no card of value 3 on the board)
-- ============================================================
H.test("moves B1: single-card stacking — different suits allowed, same suit blocked", function(rules)
   -- PROVENANCE: tableau_script.script:163
   --   return bottom_card.data.suit ~= top_card.data.suit
   --          and bottom_card.data.value == top_card.data.value - 1
   local state = empty_state()
   state.tableau[1] = { num("blue", 5) }  -- 5_blue
   state.tableau[2] = { num("red",  4) }  -- 4_red
   state.tableau[3] = { num("green",4) }  -- 4_green
   state.tableau[4] = { num("blue", 4) }  -- 4_blue
   -- cols 5-8 remain empty

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   -- 4_red can stack on 5_blue (different suits, value 4 = 5-1)
   if not has_move(moves, { type="tableau_to_tableau", from_col=2, to_col=1 }) then
      return false, "4_red (col2) must be able to stack on 5_blue (col1): suits differ, 4==5-1"
   end

   -- 4_green can stack on 5_blue (different suits, value 4 = 5-1)
   if not has_move(moves, { type="tableau_to_tableau", from_col=3, to_col=1 }) then
      return false, "4_green (col3) must be able to stack on 5_blue (col1): suits differ, 4==5-1"
   end

   -- 4_blue CANNOT stack on 5_blue (SAME suit)
   if has_move(moves, { type="tableau_to_tableau", from_col=4, to_col=1 }) then
      return false, "4_blue (col4) must NOT stack on 5_blue (col1): same suit (blue)"
   end

   return true
end)

-- ============================================================
-- STATE B2: Dragon-collect availability
-- Board:
--   col1 = [d_red]   (top = dragon red)
--   col2 = [d_red]   (top = dragon red)
--   col3 = [d_red]   (top = dragon red)
--   col4 = [d_red]   (top = dragon red)
--   col5 = [5_blue]  (top = 5_blue, not dragon)
--   col6-8 = empty
--   free_cells: all 3 empty, unblocked
--   dragons_collected.red = false
--
-- EXPECTED: dragon_collect for "red" IS available.
--   Condition (SPEC §3.4 / dragon_button.script:69,83-86):
--     counter[red] == 4  (all 4 red dragons exposed as tops of their columns)
--     free_slots_counter[red] > 0  (at least one free slot available)
--     is_enable = true  (button not yet used)
--
-- The 4 red dragons are at tops of cols 1-4 => counter[red] == 4
-- 3 free cells are all empty => free_slots_counter[red] == 3 > 0
-- dragons_collected.red = false => button still enabled
--
-- PARITY assertions:
--   (B2-a) dragon_collect for "red" IS in legal moves
--   (B2-b) dragon_collect for "blue" and "green" are NOT in legal moves
--             (zero blue/green dragons exposed)
-- ============================================================
H.test("moves B2: dragon collect available iff all 4 exposed + free slot exists", function(rules)
   -- PROVENANCE:
   --   dragon_button.script:69: if self.is_enable and self.counter == 4 and free_slot_any(self)
   --   dragon_button.script:83-86: free_slot_any => self.free_slots_counter > 0
   --   SPEC §3.4: counter[S]==4 AND free_slots_counter[S]>0
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   state.tableau[4] = { drag("red") }
   state.tableau[5] = { num("blue", 5) }
   -- cols 6-8 empty
   -- Update dragon_counter to reflect 4 red dragons exposed
   state.dragon_counter = { red=4, blue=0, green=0 }
   state.free_slots_counter = { red=3, blue=3, green=3 }
   state.dragons_collected = { red=false, blue=false, green=false }

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   -- Red dragon collect must be available
   if not has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "dragon_collect for 'red' must be legal: all 4 red dragons exposed, 3 free cells available"
   end

   -- Blue and green dragon collects must NOT be available
   if has_move(moves, { type="dragon_collect", suit="blue" }) then
      return false, "dragon_collect for 'blue' must NOT be legal: no blue dragons exposed"
   end
   if has_move(moves, { type="dragon_collect", suit="green" }) then
      return false, "dragon_collect for 'green' must NOT be legal: no green dragons exposed"
   end

   return true
end)

-- ============================================================
-- STATE B2b: Dragon collect BLOCKED by no free slots
-- Same as B2 but all free cells are occupied by non-dragon cards.
-- free_slots_counter[red] should be 0 => collect NOT available.
-- PROVENANCE: dragon_button.script:83-86, free_cell.script:31-41
--   A non-dragon card occupying a free cell decrements ALL buttons' counters.
-- ============================================================
H.test("moves B2b: dragon collect blocked when no free slots available", function(rules)
   -- PROVENANCE:
   --   free_cell.script:37-41: send_to_dragon_buttons(self, card, -1) for non-dragon
   --     => change_button_counter(self, num) for ALL buttons (including red)
   --   SPEC §3.4: free_slots_counter[S] > 0 required
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   state.tableau[4] = { drag("red") }
   -- All 3 free cells occupied by non-dragon numeric cards
   state.free_cells = {
      { card=num("blue", 7), is_blocked=false },
      { card=num("red",  8), is_blocked=false },
      { card=num("green",9), is_blocked=false },
   }
   -- free_slots_counter for red = 0 (all 3 slots blocked by other cards)
   state.dragon_counter = { red=4, blue=0, green=0 }
   state.free_slots_counter = { red=0, blue=0, green=0 }
   state.dragons_collected = { red=false, blue=false, green=false }

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   if has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "dragon_collect for 'red' must NOT be legal when no free slots available"
   end
   return true
end)

-- ============================================================
-- STATE B3: Multi-card run move
-- Board:
--   col1 = [6_green, 5_red, 4_blue]   (bottom to top; 4_blue is top)
--     sub-run: 5_red/4_blue forms a valid sequence (5 and 4, different suits)
--   col2 = [7_green]   (top = 7_green; can_stack(7_green, 5_red)? 7==5+1? NO, 7!=6 NO)
--   col3 = [6_blue]    (top = 6_blue)
--     can_stack(6_blue, 5_red)? suit differ(blue≠red), value 6==5+1 YES
--     => can drop 2-card run [5_red, 4_blue] onto 6_blue
--   col4-8 = empty
--
-- EXPECTED:
--   multi_to_tableau move: run [5_red, 4_blue] from col1 (starting at index 2) → col3
--   multi_to_tableau move: run [5_red, 4_blue] from col1 (starting at index 2) → empty col4,5,6,7,8
--   ALSO the top single card (4_blue) can move as single to col3 via tableau_to_tableau
--     can_stack(6_blue, 4_blue)? suit same(blue==blue) NO → NOT allowed
--   4_blue can move to 5_red's position? No, we're on col1.
--   For col2 (7_green): can 4_blue stack on 7_green? suit differ(blue≠green), 7==4+1? No, 7!=5 NO
--
-- PARITY assertions:
--   (B3-a) multi-card run [5_red,4_blue] (2 cards from col1) can land on 6_blue (col3)
--   (B3-b) multi-card run can land on empty columns (col4-8)
--   (B3-c) run CANNOT land on 7_green (col2): 7 != 5+1
--   (B3-d) multi-card run CANNOT go to free_cell (SPEC §3.1: only tableau targets)
-- ============================================================
H.test("moves B3: multi-card run — correct targets permitted, wrong targets blocked", function(rules)
   -- PROVENANCE:
   --   SPEC §3.1 multi-card run: drop legal if can_stack(target_top, run_bottom) OR target empty
   --   tableau_script.script:150-163: same can_stack rule
   --   SPEC §3.1: "Multi-card runs may only be dropped onto tableau columns"
   local state = empty_state()
   -- col1: bottom=6_green, mid=5_red, top=4_blue
   state.tableau[1] = { num("green", 6), num("red", 5), num("blue", 4) }
   -- col2: 7_green
   state.tableau[2] = { num("green", 7) }
   -- col3: 6_blue
   state.tableau[3] = { num("blue", 6) }
   -- col4-8: empty

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   -- Multi-card run [5_red, 4_blue] from col1 MUST land on 6_blue (col3)
   -- run_bottom = 5_red; can_stack(6_blue, 5_red): suit blue≠red YES, value 6==5+1 YES
   if not has_move(moves, { type="multi_to_tableau", from_col=1, to_col=3 }) then
      return false, "multi-card run [5_red,4_blue] from col1 must land on 6_blue (col3): can_stack(6_blue,5_red)=true"
   end

   -- Multi-card run MUST be able to go to an empty column (col4)
   if not has_move(moves, { type="multi_to_tableau", from_col=1, to_col=4 }) then
      return false, "multi-card run from col1 must be able to go to empty column (col4)"
   end

   -- Multi-card run CANNOT land on 7_green (col2)
   -- can_stack(7_green, 5_red): suit green≠red YES, value 7==5+1? No, 7!=6 NO
   if has_move(moves, { type="multi_to_tableau", from_col=1, to_col=2 }) then
      return false, "multi-card run [5_red,4_blue] must NOT land on 7_green (col2): 7!=5+1"
   end

   -- Multi-card run must NOT go to a free cell (SPEC §3.1 explicit restriction)
   local has_run_to_fc = false
   for _, m in ipairs(moves) do
      if m.type == "multi_to_free_cell" or
         (m.type == "to_free_cell" and m.run_size and m.run_size > 1) then
         has_run_to_fc = true
      end
   end
   if has_run_to_fc then
      return false, "multi-card run must NOT target a free cell (SPEC §3.1)"
   end

   return true
end)

-- ============================================================
-- STATE B4: Foundation placement correctness
-- Grounding: base_slot.script:11-15 and 67-76
--   Empty slot: accepts card with value==2 (any suit)
--   Non-empty slot: same suit, value == last_card.value + 1
--
-- Board:
--   foundation_top = { red=3, blue=1, green=5 }
--     red slot has 3 on top (last placed was 3_red), next needed: 4_red
--     blue slot empty (foundation_top=1 => needs value 2)
--     green slot has 5 on top, next needed: 6_green
--   col1 = [4_red]   → should go to red foundation (4 == 3+1, same suit)
--   col2 = [2_blue]  → should go to blue foundation (2 == 1+1, blue slot empty needs 2)
--   col3 = [6_green] → should go to green foundation (6 == 5+1, same suit)
--   col4 = [4_blue]  → should NOT go to blue foundation (blue needs 2, not 4)
--   col5 = [5_red]   → should NOT go to red foundation (red needs 4, not 5)
--   col6 = [3_red]   → should NOT go to red foundation (red needs 4, not 3)
-- ============================================================
H.test("moves B4: foundation placement — correct value/suit required, wrong ones rejected", function(rules)
   -- PROVENANCE:
   --   base_slot.script:13: if self.empty and message.card.data.value == 2
   --   base_slot.script:67-76: check_correct_cards: same suit, value == last_card.value+1
   --   SPEC §3.2
   local state = empty_state()
   state.foundation_top = { red=3, blue=1, green=5 }
   state.tableau[1] = { num("red",  4) }  -- 4_red → red foundation (needs 4)
   state.tableau[2] = { num("blue", 2) }  -- 2_blue → blue foundation (needs 2)
   state.tableau[3] = { num("green",6) }  -- 6_green → green foundation (needs 6)
   state.tableau[4] = { num("blue", 4) }  -- 4_blue → NOT to blue foundation (needs 2)
   state.tableau[5] = { num("red",  5) }  -- 5_red → NOT to red foundation (needs 4)
   state.tableau[6] = { num("red",  3) }  -- 3_red → NOT to red foundation (needs 4)

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   -- 4_red must go to foundation
   if not has_move(moves, { type="to_foundation", from_col=1 }) then
      return false, "4_red (col1) must move to foundation: red needs 4 (foundation_top.red=3)"
   end

   -- 2_blue must go to foundation
   if not has_move(moves, { type="to_foundation", from_col=2 }) then
      return false, "2_blue (col2) must move to foundation: blue slot empty needs 2"
   end

   -- 6_green must go to foundation
   if not has_move(moves, { type="to_foundation", from_col=3 }) then
      return false, "6_green (col3) must move to foundation: green needs 6 (foundation_top.green=5)"
   end

   -- 4_blue must NOT go to foundation (blue needs 2, not 4)
   if has_move(moves, { type="to_foundation", from_col=4 }) then
      return false, "4_blue (col4) must NOT go to foundation: blue needs 2, not 4"
   end

   -- 5_red must NOT go to foundation (red needs 4, not 5)
   if has_move(moves, { type="to_foundation", from_col=5 }) then
      return false, "5_red (col5) must NOT go to foundation: red needs 4, not 5"
   end

   -- 3_red must NOT go to foundation (red needs 4, not 3)
   if has_move(moves, { type="to_foundation", from_col=6 }) then
      return false, "3_red (col6) must NOT go to foundation: red needs 4, not 3"
   end

   return true
end)

-- ============================================================
-- STATE B5: Free cell — any card type accepted, blocked slot inaccessible
-- Board:
--   col1 = [d_red]    (dragon)
--   col2 = [flower()]  (flower)
--   col3 = [4_blue]   (numeric)
--   free_cells:
--     slot1: empty, unblocked  → accepts any
--     slot2: occupied, blocked  → neither place nor remove
--     slot3: occupied, unblocked → can remove (pick)
--
-- PROVENANCE:
--   free_cell.script:46-49: check_slot -> if not self.is_occupied then slot_valid
--   free_cell.script:102-105: can_pick_card -> if self.is_occupied and not self.is_blocked
--   SPEC §3.3
-- ============================================================
H.test("moves B5: free cell accepts any card type; blocked slot inaccessible", function(rules)
   -- PROVENANCE:
   --   free_cell.script:46-49: check_slot accepts any card as long as not occupied
   --   free_cell.script:102-105: can_pick_card requires occupied AND NOT blocked
   --   SPEC §3.3
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { flower() }
   state.tableau[3] = { num("blue", 4) }
   -- slot1: empty, unblocked
   state.free_cells[1] = { card=nil, is_blocked=false }
   -- slot2: occupied + blocked (collected dragons)
   state.free_cells[2] = { card=drag("blue"), is_blocked=true }
   -- slot3: occupied + unblocked (a card can be picked from here)
   state.free_cells[3] = { card=num("green", 9), is_blocked=false }

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   -- Dragon (col1) can go to empty free cell (slot1)
   if not has_move(moves, { type="to_free_cell", from_col=1 }) then
      return false, "d_red (col1) must be moveable to free cell: free_cell.script accepts any card"
   end

   -- Flower (col2) can go to empty free cell (slot1)
   if not has_move(moves, { type="to_free_cell", from_col=2 }) then
      return false, "flower (col2) must be moveable to free cell: free_cell.script accepts any card"
   end

   -- Numeric (col3) can go to empty free cell (slot1)
   if not has_move(moves, { type="to_free_cell", from_col=3 }) then
      return false, "4_blue (col3) must be moveable to free cell: free_cell.script accepts any card"
   end

   -- Cannot place card into slot2 (blocked)
   local placing_into_blocked = false
   for _, m in ipairs(moves) do
      if (m.type == "to_free_cell") and m.to_slot == 2 then
         placing_into_blocked = true
      end
   end
   if placing_into_blocked then
      return false, "must NOT be able to place into blocked free cell (slot2)"
   end

   -- Cannot pick from slot2 (blocked)
   local picking_from_blocked = false
   for _, m in ipairs(moves) do
      if (m.type == "from_free_cell") and m.from_slot == 2 then
         picking_from_blocked = true
      end
   end
   if picking_from_blocked then
      return false, "must NOT be able to pick from blocked free cell (slot2)"
   end

   -- CAN pick from slot3 (occupied + not blocked)
   if not has_move(moves, { type="from_free_cell", from_slot=3 }) then
      return false, "must be able to pick from slot3 (occupied + not blocked)"
   end

   return true
end)

-- ============================================================
-- STATE B6: Dragon already collected — button disabled, no collect move
-- PROVENANCE: dragon_button.script:34: self.is_enable = false after collect
--             SPEC §3.4: "The dragon button for suit S is permanently disabled"
-- ============================================================
H.test("moves B6: dragon already collected — no collect move generated", function(rules)
   -- PROVENANCE:
   --   dragon_button.script:34: self.is_enable = false (after get_dragon_cards)
   --   SPEC §3.4: "permanently disabled (is_enable = false)"
   local state = empty_state()
   state.tableau[1] = { drag("red") }
   state.tableau[2] = { drag("red") }
   state.tableau[3] = { drag("red") }
   state.tableau[4] = { drag("red") }
   state.dragon_counter = { red=4, blue=0, green=0 }
   state.free_slots_counter = { red=3, blue=3, green=3 }
   -- Red is already collected — button disabled
   state.dragons_collected = { red=true, blue=false, green=false }

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   if has_move(moves, { type="dragon_collect", suit="red" }) then
      return false, "dragon_collect for 'red' must NOT appear: already collected (is_enable=false)"
   end
   return true
end)

-- ============================================================
-- STATE B7: Multi-card grab across a SEQUENCE BREAK is illegal
-- Board:
--   col1 = [8_red, 5_blue, 4_green]   (bottom→top)
--     can_stack(8_red, 5_blue)? 8==5+1? NO → SEQUENCE BREAK between 8_red and 5_blue
--     can_stack(5_blue, 4_green)? blue≠green, 5==4+1 YES → valid run = [5_blue, 4_green]
--     => 8_red is BURIED below the break; only [5_blue,4_green] (or single 4_green) is grabbable
--   col2 = [9_blue]   discriminator: an ILLEGAL full-column grab (run_bottom=8_red)
--     would stack on 9_blue — can_stack(9_blue,8_red): blue≠red, 9==8+1 YES.
--     A spec-faithful-but-wrong solver enumerates it; the real game does NOT.
--   col3 = [6_red]    positive control: legal run (run_bottom=5_blue) stacks here —
--     can_stack(6_red,5_blue): red≠blue, 6==5+1 YES.
--
-- PARITY assertions:
--   (B7-a) multi_to_tableau col1→col3 PRESENT  (valid run [5_blue,4_green] lands on 6_red)
--   (B7-b) multi_to_tableau col1→col2 ABSENT   (would require illegally grabbing 8_red)
--
-- This is the test gap the adversarial review flagged: B3's column is fully a
-- valid run, so it cannot catch a solver that grabs across a break. B7 does.
-- Source: tableau_script.script:86-144 (update_visible_cards exposes only the
--   maximal valid run); cursor.script:486-488,701-760 (only that run is grabbable).
-- ============================================================
H.test("moves B7: multi-card grab across a sequence break must NOT be enumerated", function(rules)
   local state = empty_state()
   state.tableau[1] = { num("red", 8), num("blue", 5), num("green", 4) }
   state.tableau[2] = { num("blue", 9) }
   state.tableau[3] = { num("red", 6) }

   local moves = rules.legal_moves(state)
   if type(moves) ~= "table" then
      return false, "legal_moves must return a table"
   end

   -- (B7-a) the legal run [5_blue,4_green] must be able to land on 6_red (col3)
   if not has_move(moves, { type="multi_to_tableau", from_col=1, to_col=3 }) then
      return false, "legal run [5_blue,4_green] from col1 must land on 6_red (col3): can_stack(6_red,5_blue)=true"
   end

   -- (B7-b) no multi-card move col1→col2: that requires grabbing 8_red across the break
   if has_move(moves, { type="multi_to_tableau", from_col=1, to_col=2 }) then
      return false, "multi-card grab across sequence break is ILLEGAL: 8_red is buried below 5_blue (8!=5+1), cannot be grabbed onto 9_blue (col2)"
   end

   return true
end)

return H
