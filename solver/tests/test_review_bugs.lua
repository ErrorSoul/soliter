-- Regression tests for review-fixes leftovers (F3–F7, F10, C3).
-- Pure Lua — no Defold. Game-script bugs live in test_game_scripts.lua.

local new_harness = require("solver.tests.harness")
local H = new_harness()

local function num(suit, val) return { value = val, suit = suit } end
local function drag(suit) return { value = "d", suit = suit, is_dragon = true } end

local function empty_state()
   return {
      tableau = { {}, {}, {}, {}, {}, {}, {}, {} },
      foundation_top = { red = 1, blue = 1, green = 1 },
      free_cells = {
         { card = nil, is_blocked = false },
         { card = nil, is_blocked = false },
         { card = nil, is_blocked = false },
      },
      flower_slot = { occupied = false },
      dragons_collected = { red = false, blue = false, green = false },
      dragon_counter = { red = 0, blue = 0, green = 0 },
      free_slots_counter = { red = 3, blue = 3, green = 3 },
   }
end

-- F5: reset must clear highlight_dirty (otherwise a leftover pulse survives restart)
H.test("F5 tutorial_state.reset clears highlight_dirty", function()
   local T = require("main.Scripts.tutorial_state")
   T.highlight_dirty = true
   T.step = 3
   T.reset()
   if T.highlight_dirty then
      return false, "reset() left highlight_dirty=true"
   end
   if T.step ~= 0 then
      return false, "reset() should still zero step"
   end
   return true
end)

-- F10: victory pulse is consumed by UI; play input must stay blocked until reset
H.test("F10 victory blocks play input after show_victory is consumed", function()
   local T = require("main.Scripts.tutorial_state")
   T.reset()
   if not T.request_victory or not T.is_play_input_blocked then
      return false, "tutorial_state.request_victory / is_play_input_blocked missing"
   end
   T.request_victory()
   if not T.show_victory then
      return false, "request_victory should set show_victory pulse"
   end
   if not T.is_play_input_blocked() then
      return false, "play input should be blocked when victory is requested"
   end
   T.show_victory = false -- UI poll consumes the pulse (ui.gui_script)
   if not T.is_play_input_blocked() then
      return false, "block dropped when show_victory was consumed — cards stay clickable under overlay"
   end
   T.reset()
   if T.is_play_input_blocked() then
      return false, "reset() must unblock play input"
   end
   return true
end)

-- F6: solver can_auto_finish must use the same safe-foundation predicate as the game
H.test("F6 can_auto_finish false when a remaining card is unsafe (v > min_other+1)", function(rules)
   local s = empty_state()
   s.tableau[1] = { num("red", 5) }
   s.foundation_top = { red = 4, blue = 1, green = 1 }
   if rules.can_auto_finish(s) then
      return false, "5_red with others at 1 is unsafe; can_auto_finish must be false"
   end
   return true
end)

H.test("F6 can_auto_finish true when every remaining card is safe", function(rules)
   local s = empty_state()
   s.tableau[1] = { num("red", 3) }
   s.foundation_top = { red = 2, blue = 2, green = 2 }
   if not rules.can_auto_finish(s) then
      return false, "3_red with others at 2 is safe; can_auto_finish must be true"
   end
   return true
end)

-- C3: dragon_collect is a branch, not a forced mandatory move
H.test("C3 forced_moves does not collect dragons (legal_moves still does)", function(rules)
   if not rules.forced_moves then
      return false, "rules.forced_moves missing — need to inspect mandatory pass"
   end
   local s = empty_state()
   s.tableau[1] = { drag("red") }
   s.tableau[2] = { drag("red") }
   s.tableau[3] = { drag("red") }
   s.tableau[4] = { drag("red") }
   local forced = rules.forced_moves(s)
   for _, m in ipairs(forced) do
      if m.type == "dragon_collect" then
         return false, "mandatory pass forced dragon_collect — consumes a free cell, not always safe"
      end
   end
   local moves = rules.legal_moves(s)
   local has_collect = false
   for _, m in ipairs(moves) do
      if m.type == "dragon_collect" and m.suit == "red" then
         has_collect = true
      end
   end
   if not has_collect then
      return false, "legal_moves lost dragon_collect — it must stay a branching move"
   end
   return true
end)

H.test("C3 forced_moves still auto-flies a tableau-top 2", function(rules)
   local s = empty_state()
   s.tableau[1] = { num("red", 2) }
   local forced = rules.forced_moves(s)
   for _, m in ipairs(forced) do
      if m.type == "to_foundation" and m.from_col == 1 then
         return true
      end
   end
   return false, "mandatory pass must still auto-foundation a top 2"
end)

-- F3: identity contract — Defold fixed_fit already gives virtual 960x540 coords.
-- A real unproject of 800x800 window would map (166.6, 424.9) → (200, 300) and
-- DOUBLE-apply letterbox, breaking hit-tests. See docs/responsive-explained.md §2.
H.test("F3 screen_to_world is identity even on a non-16:9 window", function()
   _G.vmath = _G.vmath or {
      vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
   }
   _G.window = { get_size = function() return 800, 800 end }
   package.loaded["main.Scripts.coords"] = nil
   package.loaded["main.Scripts.config"] = nil
   local coords = require("main.Scripts.coords")
   local x, y = coords.screen_to_world(166.6, 424.9)
   if math.abs(x - 166.6) > 0.01 or math.abs(y - 424.9) > 0.01 then
      return false, string.format(
         "screen_to_world must pass through (got %.2f,%.2f) — Defold already virtualizes action.x/y",
         x, y)
   end
   return true
end)

-- F4: one-slot queue must be clearable so MENU click does not leak into next deal
H.test("F4 sfx.clear drops a queued pending sound", function()
   local sfx = require("main.Scripts.sfx")
   sfx.queue("button_click")
   if sfx.pending ~= "button_click" then
      return false, "queue did not set pending"
   end
   if not sfx.clear then
      return false, "sfx.clear missing"
   end
   sfx.clear()
   if sfx.pending ~= nil then
      return false, "clear() left pending set — MENU click will play on next deal"
   end
   return true
end)

-- F7: WIN banner must reset ANSI, not leave the terminal green
H.test("F7 watch.RESET is a real ANSI reset", function()
   local W = require("solver.watch")
   if W.RESET ~= "\27[0m" then
      return false, string.format("watch.RESET want \\27[0m, got %q", tostring(W.RESET))
   end
   return true
end)

return H
