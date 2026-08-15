-- solver/watch.lua — animated ASCII replay of the solver playing a deal.
--
-- Watch the solver solve a board, move by move, in your terminal:
--   lua solver/watch.lua                 -- a new random solvable game each run
--   lua solver/watch.lua --seed 42       -- a specific seed
--   lua solver/watch.lua --seed 42 --delay 0.6 --budget 400000 --no-color
--
-- Purpose: eyeball that the solver only ever makes LEGAL moves and reaches a
-- real win — a visual cross-check of the rules engine against how the game plays.
-- The board model and move semantics come straight from solver/rules.lua, so what
-- you watch is exactly what the solver's solvability numbers are based on.

-- Pure rendering lives in board_view (no require/io/os, Defold-safe). Re-export
-- so the terminal CLI below and the existing tests keep using M.card_str/render/
-- describe unchanged.
local view = require("solver.board_view")
local M = {
   card_str = view.card_str,
   render   = view.render,
   describe = view.describe,
   RESET    = "\27[0m",
}

-- ============================================================
-- CLI (only when run directly, not when required by the test runner)
-- ============================================================

local function main()
   -- Resolve solver/rules.lua relative to this script.
   local script_path = debug.getinfo(1, "S").source:sub(2)
   local script_dir  = script_path:match("^(.*)/[^/]+$") or "."
   package.path = script_dir .. "/?.lua;" .. package.path
   local R = require("rules")

   -- Parse args
   local seed, delay, budget, color = nil, 0.35, nil, true
   local i = 1
   while arg and i <= #arg do
      local a = arg[i]
      if a == "--seed" then i = i + 1; seed = tonumber(arg[i])
      elseif a == "--delay" then i = i + 1; delay = tonumber(arg[i]) or delay
      elseif a == "--budget" then i = i + 1; budget = tonumber(arg[i])
      elseif a == "--no-color" then color = false end
      i = i + 1
   end

   local moves, used_seed
   if seed then
      budget = budget or 300000
      local st = R.deal(seed)
      local mv, status = R.solve(st, { node_budget = budget })
      if status ~= "solved" then
         io.write(string.format("seed %d: %s within budget %d — try another --seed or a higher --budget.\n",
            seed, status, budget))
         os.exit(1)
      end
      moves, used_seed = mv, seed
   else
      -- "New game": search random seeds until one solves within a quick budget.
      budget = budget or 150000
      local base = os.time and os.time() or 1
      for attempt = 0, 30 do
         local cand = (base + attempt * 7919) % 1000000 + 1
         local mv, status = R.solve(R.deal(cand), { node_budget = budget })
         if status == "solved" then moves, used_seed = mv, cand; break end
      end
      if not moves then
         io.write("could not find a solvable seed quickly — rerun, or pass --seed N --budget 400000.\n")
         os.exit(1)
      end
   end

   -- Animate the replay from a fresh deal.
   local state = R.deal(used_seed)
   local total = #moves
   local function frame(move_no, desc)
      io.write("\27[2J\27[H")  -- clear screen + home
      io.write(M.render(state, { seed = used_seed, move_no = move_no, total = total, desc = desc, color = color }))
      io.write("\n")
      io.flush()
      if delay > 0 then os.execute("sleep " .. tostring(delay)) end
   end

   frame(0, "deal")
   for n, mv in ipairs(moves) do
      state = R.apply_move(state, mv)
      frame(n, M.describe(mv))
   end

   if R.is_win(state) then
      io.write("\n" .. (color and "\27[92m" or "") .. "WIN ✓  (" .. total .. " moves, seed " .. used_seed .. ")" .. (color and M.RESET or "") .. "\n")
   else
      io.write("\nNOT a win after replay (seed " .. used_seed .. ") — this should not happen; please report.\n")
      os.exit(1)
   end
end

if arg and arg[0] and arg[0]:match("watch%.lua$") then
   main()
end

return M
