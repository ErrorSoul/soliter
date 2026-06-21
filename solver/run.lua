-- solver/run.lua
-- CLI: /opt/homebrew/bin/lua solver/run.lua --seeds A..B
--
-- For each seed in [A, B]:
--   1. Deal the board using rules.M.deal(seed) (replicates SPEC §2 shuffle, column-major)
--   2. Solve it with a per-board node budget
--   3. Print summary with honest labels:
--        "solved within budget" / "timeout — NOT proven unsolvable" / "proven unsolvable"
--   4. For each solved board, write solver/golden/<seed>.txt (move sequence)
--   5. Replay the golden path through rules to self-verify it reaches a win state
--   6. Report auto-finish: condition (SPEC §5) + count of solved boards reaching can_auto_finish
--
-- Usage: lua solver/run.lua --seeds 1..30

-- ============================================================
-- 1. Determine script's own directory for relative requires
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)  -- remove "@"
local script_dir  = script_path:match("^(.*)/[^/]+$") or "."

-- Allow require("rules") to find solver/rules.lua
package.path = script_dir .. "/?.lua;" .. package.path

local R = require("rules")

-- ============================================================
-- 2. Configuration
-- ============================================================

local NODE_BUDGET = 15000  -- per-board DFS node budget

-- ============================================================
-- 3. Parse CLI args
-- ============================================================

local function parse_args(args)
   local seed_a, seed_b = nil, nil
   local budget = NODE_BUDGET
   local i = 1
   while i <= #args do
      if args[i] == "--seeds" then
         i = i + 1
         local range = args[i]
         if not range then
            io.stderr:write("Error: --seeds requires a value like A..B\n")
            os.exit(1)
         end
         seed_a, seed_b = range:match("^(%d+)%.%.(%d+)$")
         if not seed_a then
            io.stderr:write("Error: --seeds format must be A..B (integers), got: " .. tostring(range) .. "\n")
            os.exit(1)
         end
         seed_a = tonumber(seed_a)
         seed_b = tonumber(seed_b)
      elseif args[i] == "--budget" then
         i = i + 1
         budget = tonumber(args[i])
         if not budget then
            io.stderr:write("Error: --budget requires an integer node count\n")
            os.exit(1)
         end
      end
      i = i + 1
   end
   if not seed_a or not seed_b then
      io.stderr:write("Usage: lua solver/run.lua --seeds A..B [--budget N]\n")
      os.exit(1)
   end
   return seed_a, seed_b, budget
end

-- ============================================================
-- 4. Move serialization (for golden files)
-- ============================================================

local function move_to_str(m)
   if m.type == "to_foundation" then
      if m.from_col then
         return string.format("to_foundation from_col=%d", m.from_col)
      else
         return string.format("to_foundation from_free_cell=%d", m.from_free_cell)
      end
   elseif m.type == "to_free_cell" then
      return string.format("to_free_cell from_col=%d", m.from_col)
   elseif m.type == "from_free_cell" then
      return string.format("from_free_cell from_slot=%d to_col=%d", m.from_slot, m.to_col)
   elseif m.type == "tableau_to_tableau" then
      return string.format("tableau_to_tableau from_col=%d to_col=%d", m.from_col, m.to_col)
   elseif m.type == "multi_to_tableau" then
      return string.format("multi_to_tableau from_col=%d to_col=%d run_start=%d run_size=%d",
         m.from_col, m.to_col, m.run_start, m.run_size)
   elseif m.type == "dragon_collect" then
      return string.format("dragon_collect suit=%s", m.suit)
   elseif m.type == "flower_auto" then
      return "flower_auto"
   elseif m.type == "to_empty_tableau" then
      if m.from_col then
         return string.format("to_empty_tableau from_col=%d to_col=%d", m.from_col, m.to_col)
      else
         return string.format("to_empty_tableau from_free_cell=%d to_col=%d", m.from_free_cell, m.to_col)
      end
   else
      -- Fallback: serialize all fields
      local parts = { m.type }
      for k, v in pairs(m) do
         if k ~= "type" then
            parts[#parts + 1] = k .. "=" .. tostring(v)
         end
      end
      return table.concat(parts, " ")
   end
end

local function str_to_move(line)
   local parts = {}
   for word in line:gmatch("%S+") do
      parts[#parts + 1] = word
   end
   if #parts == 0 then return nil end

   local move = { type = parts[1] }
   for i = 2, #parts do
      local k, v = parts[i]:match("^([^=]+)=(.+)$")
      if k then
         local n = tonumber(v)
         move[k] = n ~= nil and n or v
      end
   end
   return move
end

-- ============================================================
-- 5. Golden file helpers
-- ============================================================

local function golden_dir(base_dir)
   return base_dir .. "/golden"
end

local function ensure_dir(path)
   -- Use mkdir -p; ignore errors (dir may already exist)
   os.execute("mkdir -p " .. path)
end

local function write_golden(base_dir, seed, moves)
   local dir = golden_dir(base_dir)
   ensure_dir(dir)
   local path = dir .. "/" .. tostring(seed) .. ".txt"
   local f = io.open(path, "w")
   if not f then
      return nil, "Cannot open " .. path .. " for writing"
   end
   f:write("# seed=" .. tostring(seed) .. " moves=" .. tostring(#moves) .. "\n")
   for _, m in ipairs(moves) do
      f:write(move_to_str(m) .. "\n")
   end
   f:close()
   return path
end

local function read_golden(path)
   local f = io.open(path, "r")
   if not f then return nil, "Cannot open " .. path end
   local moves = {}
   for line in f:lines() do
      if not line:match("^#") and line:match("%S") then
         local m = str_to_move(line)
         if m then moves[#moves + 1] = m end
      end
   end
   f:close()
   return moves
end

-- ============================================================
-- 6. Replay and self-verify
-- ============================================================

-- Replay moves from a fresh deal and assert is_win at the end.
-- Returns (true, move_count) on PASS, or (false, reason) on FAIL.
local function replay_and_verify(seed, moves)
   local state = R.deal(seed)
   for i, move in ipairs(moves) do
      local next_state = R.apply_move(state, move)
      if next_state == nil then
         return false, string.format("apply_move returned nil at step %d (move: %s)", i, move_to_str(move))
      end
      state = next_state
   end
   if R.is_win(state) then
      return true, #moves
   else
      -- Diagnose what's missing
      local missing = {}
      if state.foundation_top.red   ~= 10 then missing[#missing+1] = "red="..state.foundation_top.red end
      if state.foundation_top.blue  ~= 10 then missing[#missing+1] = "blue="..state.foundation_top.blue end
      if state.foundation_top.green ~= 10 then missing[#missing+1] = "green="..state.foundation_top.green end
      if not state.flower_slot.occupied then missing[#missing+1] = "flower=missing" end
      return false, "not a win state after replay: " .. table.concat(missing, ", ")
   end
end

-- ============================================================
-- 7. Auto-finish reachability check
-- ============================================================

-- Replay moves step-by-step; return true if can_auto_finish ever becomes true.
-- The move-index when it triggers is NOT reported: DFS paths are long and
-- non-optimal, so that index is an artifact of the search, not real-play timing.
local function reaches_auto_finish(seed, moves)
   local state = R.deal(seed)
   for _, move in ipairs(moves) do
      state = R.apply_move(state, move)
      if state and R.can_auto_finish(state) then
         return true
      end
   end
   return false
end

-- ============================================================
-- 8. Main
-- ============================================================

local function main()
   local args = arg or {}
   local seed_a, seed_b, node_budget = parse_args(args)

   -- Determine base directory (script's dir = solver/)
   local base_dir = script_dir

   local n_solved     = 0
   local n_unsolvable = 0
   local n_timeout    = 0
   local total_seeds  = seed_b - seed_a + 1

   local replay_results = {}   -- { seed, pass, detail }
   local af_count = 0          -- count of solved boards that reach can_auto_finish

   for seed = seed_a, seed_b do
      local state = R.deal(seed)
      local moves, status = R.solve(state, { node_budget = node_budget })

      if status == "solved" then
         n_solved = n_solved + 1

         -- Write golden file
         local golden_path, err = write_golden(base_dir, seed, moves)
         if not golden_path then
            io.stderr:write("Warning: could not write golden for seed " .. seed .. ": " .. tostring(err) .. "\n")
         end

         -- Self-verify by replaying from fresh deal
         local pass, detail = replay_and_verify(seed, moves)
         replay_results[#replay_results + 1] = {
            seed   = seed,
            pass   = pass,
            detail = detail,
            moves  = #moves,
         }

         -- Auto-finish reachability
         if reaches_auto_finish(seed, moves) then
            af_count = af_count + 1
         end

      elseif status == "unsolvable" then
         n_unsolvable = n_unsolvable + 1
      else
         n_timeout = n_timeout + 1
      end
   end

   -- ---- Print summary ----
   io.write(string.format("Seeds %d..%d  budget=%d nodes/board\n", seed_a, seed_b, node_budget))
   io.write(string.format("solved within budget:      %d / %d (%.0f%%)\n",
      n_solved, total_seeds, 100 * n_solved / total_seeds))
   io.write(string.format("timeout (NOT proven unsolvable): %d / %d (%.0f%%)\n",
      n_timeout, total_seeds, 100 * n_timeout / total_seeds))
   io.write(string.format("proven unsolvable:         %d / %d (%.0f%%)\n",
      n_unsolvable, total_seeds, 100 * n_unsolvable / total_seeds))

   -- ---- Replay results ----
   if #replay_results > 0 then
      io.write("\nReplay verification:\n")
      local all_pass = true
      for _, r in ipairs(replay_results) do
         local tag = r.pass and "PASS" or "FAIL"
         if not r.pass then all_pass = false end
         io.write(string.format("  seed=%d  %s  moves=%d  %s\n",
            r.seed, tag, r.moves, r.pass and "" or ("-- " .. tostring(r.detail))))
      end
      if all_pass then
         io.write("All replays: PASS\n")
      else
         io.write("Some replays: FAIL\n")
      end
   end

   -- ---- Auto-finish reachability ----
   io.write(string.format("\ncan_auto_finish trigger condition (SPEC §5):\n"))
   io.write("  all dragons collected + no dragon/flower anywhere in tableau + tableau non-empty\n")
   if n_solved > 0 then
      io.write(string.format("Solved boards reaching can_auto_finish: %d / %d\n",
         af_count, n_solved))
   end
end

main()
