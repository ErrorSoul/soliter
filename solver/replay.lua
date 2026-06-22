-- solver/replay.lua — PURE director planner for the in-game auto-replay (stage 2b).
--
-- Walks a solved line of play together with a parallel "go_map" (the real card
-- GO ids) in lock-step with rules.apply_move, and emits a flat list of abstract
-- "directives". The game-side glue (main.script) turns each directive into a
-- drop_success / move_stack_cards message — this module never touches Defold
-- (no msg/timer/go), so it is fully unit-testable and is the ONLY automated
-- check of director logic (the engine can't run headless).
--
-- Why a parallel go_map instead of reading the live game back: the solver's
-- solution was computed from build_solver_snapshot, whose tableau walk this map
-- mirrors 1:1. Keeping our own bookkeeping means the director is authoritative —
-- e.g. it names the free-cell slot for a park/dragon-collect rather than letting
-- the game's nondeterministic pairs() pick it (cursor.script:643-659).
--
-- go_map mirrors only the MOVABLE regions of the solver state:
--   go_map.tableau[col] = { go, go, ... }      -- parallel to state.tableau[col]
--   go_map.free_cells[i] = go | BLOCKED | nil  -- parallel to state.free_cells[i]
-- Foundations and the flower slot are NOT tracked: cards there leave play.

local rules = require("solver.rules")

local M = {}

-- Marker for a free cell that holds a collected (blocked) dragon pile.
local BLOCKED = "__blocked__"
M.BLOCKED = BLOCKED

local function top(col) return col[#col] end

-- Free-cell ordinal that went empty -> holding a parked card (to_free_cell).
local function find_filled_cell(pre, post)
   for i = 1, #post.free_cells do
      local a, b = pre.free_cells[i], post.free_cells[i]
      if a.card == nil and not a.is_blocked and b.card ~= nil and not b.is_blocked then
         return i
      end
   end
end

-- Free-cell ordinal that became blocked (dragon_collect).
local function find_blocked_cell(pre, post)
   for i = 1, #post.free_cells do
      if not pre.free_cells[i].is_blocked and post.free_cells[i].is_blocked then
         return i
      end
   end
end

-- Pop the top GO of a go_map column, asserting it exists (a nil here means the
-- go_map desynced from the solver state — fail loud rather than emit a nil slot).
local function pop_top(gm, col)
   local go = table.remove(gm.tableau[col])
   assert(go ~= nil, "replay: go_map underflow popping tableau col " .. tostring(col))
   return go
end

-- Emit the directive for one move and mutate go_map to match the post-state.
local function step(pre, post, move, gm)
   local t = move.type

   if t == "to_foundation" then
      if move.from_col then
         local go = pop_top(gm, move.from_col)
         return { kind = "to_foundation", card_go = go, suit = top(pre.tableau[move.from_col]).suit }
      else
         local i = move.from_free_cell
         local go = gm.free_cells[i]
         assert(go and go ~= BLOCKED, "replay: no parked GO in free cell " .. tostring(i))
         gm.free_cells[i] = nil
         return { kind = "to_foundation", card_go = go, suit = pre.free_cells[i].card.suit }
      end

   elseif t == "to_free_cell" then
      local go = pop_top(gm, move.from_col)
      local ord = find_filled_cell(pre, post)
      assert(ord, "replay: to_free_cell found no newly-filled cell")
      gm.free_cells[ord] = go
      return { kind = "to_free_cell", card_go = go, cell_ord = ord }

   elseif t == "from_free_cell" then
      local i = move.from_slot
      local go = gm.free_cells[i]
      assert(go and go ~= BLOCKED, "replay: no parked GO in free cell " .. tostring(i))
      gm.free_cells[i] = nil
      local depth = #gm.tableau[move.to_col]
      table.insert(gm.tableau[move.to_col], go)
      return { kind = "from_free_cell", card_go = go, to_col = move.to_col, to_depth = depth }

   elseif t == "tableau_to_tableau" then
      local go = pop_top(gm, move.from_col)
      local depth = #gm.tableau[move.to_col]
      table.insert(gm.tableau[move.to_col], go)
      return { kind = "tableau_to_tableau", card_go = go, to_col = move.to_col, to_depth = depth }

   elseif t == "to_empty_tableau" then
      local go
      if move.from_col then
         go = pop_top(gm, move.from_col)
      else
         local i = move.from_free_cell
         go = gm.free_cells[i]
         assert(go and go ~= BLOCKED, "replay: no parked GO in free cell " .. tostring(i))
         gm.free_cells[i] = nil
      end
      -- target column is empty -> depth 0
      table.insert(gm.tableau[move.to_col], go)
      return { kind = "to_empty_tableau", card_go = go, to_col = move.to_col, to_depth = 0 }

   elseif t == "multi_to_tableau" then
      local src = gm.tableau[move.from_col]
      local p = move.run_start
      local run = {}
      for i = p, #src do run[#run + 1] = src[i] end
      for i = #src, p, -1 do table.remove(src, i) end
      assert(#run == move.run_size, "replay: multi run size mismatch (go_map desync)")
      local depth = #gm.tableau[move.to_col]
      for _, go in ipairs(run) do table.insert(gm.tableau[move.to_col], go) end
      return { kind = "multi_to_tableau", card_gos = run, to_col = move.to_col, to_depth = depth }

   elseif t == "dragon_collect" then
      local ord = find_blocked_cell(pre, post)
      assert(ord, "replay: dragon_collect found no newly-blocked cell")
      -- Mirror apply_move: scan cols 1..8, take the top GO of every column whose
      -- pre-state top is a dragon of this suit (the gate guarantees exactly 4).
      local gos = {}
      for col_i = 1, 8 do
         local col = pre.tableau[col_i]
         local c = col[#col]
         if c and c.is_dragon and c.suit == move.suit then
            gos[#gos + 1] = pop_top(gm, col_i)
         end
      end
      gm.free_cells[ord] = BLOCKED
      return { kind = "dragon_collect", card_gos = gos, cell_ord = ord }

   elseif t == "flower_auto" then
      -- apply_move takes the first column (1..8) whose top is the flower.
      for col_i = 1, 8 do
         local col = pre.tableau[col_i]
         local c = col[#col]
         if c and c.is_flower then
            local go = pop_top(gm, col_i)
            return { kind = "flower_auto", card_go = go }
         end
      end
      error("replay: flower_auto but no flower on any tableau top")
   end

   error("replay: unknown move type " .. tostring(t))
end

-- plan(state, moves, go_map) -> directives (array)
--   state   : initial solver state (from bridge.from_game). Not mutated
--             (apply_move returns copies; we only read `state`).
--   moves   : solved line of play (from rules.solve).
--   go_map  : initial { tableau = {8 arrays of GOs}, free_cells = {} }. MUTATED
--             in place to the terminal map (callers may inspect it after).
-- Raises on any go_map/solver desync (nil GO, run-size mismatch, missing cell).
function M.plan(state, moves, go_map)
   go_map.free_cells = go_map.free_cells or {}
   local directives = {}
   for _, move in ipairs(moves) do
      local post = rules.apply_move(state, move)
      directives[#directives + 1] = step(state, post, move, go_map)
      state = post
   end
   return directives
end

return M
