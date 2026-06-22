-- solver/board_view.lua — PURE rendering of a solver board state to text.
--
-- No module requires, no io/os, no Defold deps: safe to load from a Defold
-- script (the game's debug solver) AND from the terminal watcher.
-- Keeping the CLI's rules/io/os dependencies OUT of this file is deliberate:
-- Defold's build scanner reads require literals statically (it does not skip
-- comments either), so pulling the CLI watcher into the game broke the build.

local M = {}

local SUIT_LETTER = { red = "R", blue = "B", green = "G", flower = "F" }
local SUIT_COLOR  = { red = "\27[91m", blue = "\27[94m", green = "\27[92m", flower = "\27[95m" }
local RESET, DIM  = "\27[0m", "\27[90m"
local CELL_W      = 4  -- visible width of one tableau cell

-- One card -> short plain token (no padding, no color). nil -> ".".
function M.card_str(card)
   if card == nil then return "." end
   if card.is_flower then return "FL" end
   if card.is_dragon then return (SUIT_LETTER[card.suit] or "?") .. "D" end
   return (SUIT_LETTER[card.suit] or "?") .. tostring(card.value)
end

-- Pad a plain token to CELL_W, optionally wrapping the glyphs (not the padding)
-- in this suit's color. Color codes are zero-width so alignment is preserved.
local function cell(card, use_color)
   local tok = M.card_str(card)
   local pad = string.rep(" ", math.max(0, CELL_W - #tok))
   if use_color and card then
      local c = SUIT_COLOR[card.suit] or ""
      return c .. tok .. RESET .. pad
   end
   return tok .. pad
end

local function found_val(v)
   if type(v) == "number" and v >= 2 then return tostring(v) end
   return "-"
end

-- Full board -> multi-line string. info = { seed, move_no, total, desc, color }.
function M.render(state, info)
   info = info or {}
   local color = info.color
   local ft = state.foundation_top or {}
   local dc = state.dragons_collected or {}
   local out = {}

   if info.seed or info.total then
      out[#out+1] = string.format("=== seed %s — move %d/%d%s ===",
         tostring(info.seed or "?"), info.move_no or 0, info.total or 0,
         info.desc and ("  ·  " .. info.desc) or "")
   end

   -- Foundations + flower + dragon-collect status
   local function dtag(suit)
      local on = dc[suit] and true or false
      return SUIT_LETTER[suit] .. (on and "v" or "-")
   end
   out[#out+1] = string.format("FOUND  R:%s B:%s G:%s    FLOWER:%s    DRAGONS %s %s %s",
      found_val(ft.red), found_val(ft.blue), found_val(ft.green),
      (state.flower_slot and state.flower_slot.occupied) and "v" or "-",
      dtag("red"), dtag("blue"), dtag("green"))

   -- Free cells: collected pile (blocked) vs parked card vs empty
   local fcparts = {}
   for i = 1, 3 do
      local fc = state.free_cells and state.free_cells[i]
      if fc and fc.is_blocked then
         fcparts[#fcparts+1] = "[##]"          -- collected dragon pile
      elseif fc and fc.card then
         local tok = M.card_str(fc.card)
         local c = color and (SUIT_COLOR[fc.card.suit] or "") or ""
         fcparts[#fcparts+1] = "[" .. c .. tok .. (color and RESET or "") .. "]"
      else
         fcparts[#fcparts+1] = "[  ]"
      end
   end
   out[#out+1] = "FREE   " .. table.concat(fcparts, " ")

   out[#out+1] = string.rep("-", 4 * 8 + 4)

   -- Column headers
   local hdr = {}
   for c = 1, 8 do hdr[#hdr+1] = "c" .. c .. string.rep(" ", CELL_W - (#("c"..c))) end
   out[#out+1] = " " .. table.concat(hdr, "")

   -- Tableau rows: index 1 at top, accessible (last) card at the bottom.
   local maxh = 0
   for c = 1, 8 do
      local col = state.tableau and state.tableau[c] or {}
      if #col > maxh then maxh = #col end
   end
   for r = 1, maxh do
      local row = {}
      for c = 1, 8 do
         local col = state.tableau and state.tableau[c] or {}
         row[#row+1] = cell(col[r], color)
      end
      out[#out+1] = " " .. table.concat(row, "")
   end
   if maxh == 0 then
      out[#out+1] = " " .. (color and DIM or "") .. "(tableau empty)" .. (color and RESET or "")
   end

   return table.concat(out, "\n")
end

-- Human-readable one-line move description.
function M.describe(m)
   local t = m.type
   if t == "to_foundation" then
      return "→ foundation (" .. (m.from_col and ("col " .. m.from_col) or ("free cell " .. m.from_free_cell)) .. ")"
   elseif t == "to_free_cell" then
      return "col " .. m.from_col .. " → free cell"
   elseif t == "from_free_cell" then
      return "free cell " .. m.from_slot .. " → col " .. m.to_col
   elseif t == "tableau_to_tableau" then
      return "col " .. m.from_col .. " → col " .. m.to_col
   elseif t == "multi_to_tableau" then
      return "col " .. m.from_col .. " → col " .. m.to_col .. " (run of " .. m.run_size .. ")"
   elseif t == "dragon_collect" then
      return "collect " .. m.suit .. " dragons"
   elseif t == "flower_auto" then
      return "flower → flower slot"
   elseif t == "to_empty_tableau" then
      return "→ empty col " .. m.to_col
   end
   return t or "?"
end

return M
