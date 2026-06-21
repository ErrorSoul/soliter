-- test_deal.lua
-- Tests for rules.deal(seed) — deck construction and determinism.
--
-- GROUNDING:
--   rules.deal(seed) must replicate the shuffle exactly as in main.script:367–377
--   and SPEC.md §2.1–2.2:
--     math.randomseed(seed)
--     for _ = 1,20 do math.random() end   -- 20 warmup calls
--     for pass = 1,3 do                   -- 3 Fisher-Yates passes
--         for i = #deck, 2, -1 do
--             local j = math.random(1,i)
--             deck[i], deck[j] = deck[j], deck[i]
--         end
--     end
--   Cards are removed from END of shuffled deck (table.remove with no index)
--   into columns 1-8, 5 cards each (SPEC §2.2).
--   Deck size: 27 numeric + 12 dragon + 1 flower = 40 cards (SPEC §1.5).
--
-- Anti-weakening checkpoint:
--   A later agent must NOT relax these assertions:
--     (d1) deal(seed) returns a state table
--     (d2) state.tableau has exactly 8 columns
--     (d3) every column has exactly 5 cards
--     (d4) total cards across all columns = 40
--     (d5) same seed -> same deal (determinism)
--     (d6) different seeds -> different deals (with overwhelming probability)
--     (d7) deck composition: 27 numeric (2-10, 3 suits), 12 dragon, 1 flower

local new_harness = require("solver.tests.harness")
local H = new_harness()

-- (d1-d4) Basic structure after deal
H.test("deal: returns valid state table with 8 columns of 5 cards each", function(rules)
   local seed = 42
   local state = rules.deal(seed)
   if type(state) ~= "table" then
      return false, "deal() must return a table, got: " .. type(state)
   end
   if type(state.tableau) ~= "table" then
      return false, "state.tableau must be a table"
   end
   if #state.tableau ~= 8 then
      return false, string.format("expected 8 tableau columns, got %d", #state.tableau)
   end
   local total = 0
   for i = 1, 8 do
      local col = state.tableau[i]
      if type(col) ~= "table" then
         return false, string.format("tableau[%d] must be a table", i)
      end
      if #col ~= 5 then
         return false, string.format("tableau[%d] must have 5 cards, got %d", i, #col)
      end
      total = total + #col
   end
   if total ~= 40 then
      return false, string.format("total cards must be 40, got %d", total)
   end
   return true
end)

-- (d7) Deck composition: 27 numeric + 12 dragon + 1 flower = 40
H.test("deal: deck composition — 27 numeric (2-10 × 3 suits), 12 dragon, 1 flower", function(rules)
   local state = rules.deal(99)
   local numeric_count = 0
   local dragon_count  = 0
   local flower_count  = 0
   local bad_value     = nil
   local suits = { red = 0, blue = 0, green = 0, flower = 0 }

   for _, col in ipairs(state.tableau) do
      for _, card in ipairs(col) do
         if type(card) ~= "table" then
            return false, "card must be a table"
         end
         if card.is_flower then
            flower_count = flower_count + 1
            if card.value ~= "f" then
               return false, "flower card must have value='f', got: " .. tostring(card.value)
            end
            if card.suit ~= "flower" then
               return false, "flower card must have suit='flower', got: " .. tostring(card.suit)
            end
         elseif card.is_dragon then
            dragon_count = dragon_count + 1
            if card.value ~= "d" then
               return false, "dragon card must have value='d', got: " .. tostring(card.value)
            end
            if card.suit ~= "red" and card.suit ~= "blue" and card.suit ~= "green" then
               return false, "dragon suit must be red/blue/green, got: " .. tostring(card.suit)
            end
         else
            -- numeric card
            if type(card.value) ~= "number" then
               return false, "numeric card value must be number, got: " .. type(card.value)
            end
            if card.value < 2 or card.value > 10 then
               bad_value = card.value
               return false, string.format("numeric card value must be 2-10, got %d", card.value)
            end
            if card.suit ~= "red" and card.suit ~= "blue" and card.suit ~= "green" then
               return false, "numeric card suit must be red/blue/green, got: " .. tostring(card.suit)
            end
            numeric_count = numeric_count + 1
         end
         suits[card.suit] = (suits[card.suit] or 0) + 1
      end
   end

   if numeric_count ~= 27 then
      return false, string.format("expected 27 numeric cards, got %d", numeric_count)
   end
   if dragon_count ~= 12 then
      return false, string.format("expected 12 dragon cards, got %d", dragon_count)
   end
   if flower_count ~= 1 then
      return false, string.format("expected 1 flower card, got %d", flower_count)
   end
   -- Each non-flower suit: 9 numeric + 4 dragon = 13 cards
   for _, suit in ipairs({"red", "blue", "green"}) do
      if suits[suit] ~= 13 then
         return false, string.format("suit '%s' must have 13 cards total, got %d", suit, suits[suit])
      end
   end
   if suits["flower"] ~= 1 then
      return false, string.format("suit 'flower' must have 1 card, got %d", suits["flower"])
   end
   return true
end)

-- (d5) Determinism: same seed -> identical deal
H.test("deal: determinism — same seed produces identical deal", function(rules)
   local seed = 12345
   local s1 = rules.deal(seed)
   local s2 = rules.deal(seed)

   for col_i = 1, 8 do
      for card_i = 1, #s1.tableau[col_i] do
         local c1 = s1.tableau[col_i][card_i]
         local c2 = s2.tableau[col_i][card_i]
         if c1.value ~= c2.value or c1.suit ~= c2.suit then
            return false, string.format(
               "col %d card %d differs: first=%s/%s second=%s/%s",
               col_i, card_i, tostring(c1.value), c1.suit,
               tostring(c2.value), c2.suit)
         end
      end
   end
   return true
end)

-- (d6) Different seeds -> different deals (probabilistic — should differ on first card)
H.test("deal: different seeds produce different deals", function(rules)
   local s1 = rules.deal(1)
   local s2 = rules.deal(2)
   -- Compare all 40 cards as a sequence; if any differ, test passes.
   for col_i = 1, 8 do
      for card_i = 1, 5 do
         local c1 = s1.tableau[col_i][card_i]
         local c2 = s2.tableau[col_i][card_i]
         if c1.value ~= c2.value or c1.suit ~= c2.suit then
            return true  -- found a difference, as expected
         end
      end
   end
   return false, "seed=1 and seed=2 produced identical deals — RNG or shuffle likely broken"
end)

-- (d8) Initial state: foundation_top all at 1 (empty), free_cells empty, flower unoccupied
H.test("deal: initial state has empty foundations, free cells, and flower slot", function(rules)
   local state = rules.deal(7)
   -- foundation_top
   if type(state.foundation_top) ~= "table" then
      return false, "state.foundation_top must be a table"
   end
   for _, suit in ipairs({"red", "blue", "green"}) do
      if state.foundation_top[suit] ~= 1 then
         return false, string.format("foundation_top.%s must start at 1, got %s",
            suit, tostring(state.foundation_top[suit]))
      end
   end
   -- free_cells: 3 slots, unoccupied, unblocked
   if type(state.free_cells) ~= "table" then
      return false, "state.free_cells must be a table"
   end
   if #state.free_cells ~= 3 then
      return false, string.format("expected 3 free_cells, got %d", #state.free_cells)
   end
   for i, fc in ipairs(state.free_cells) do
      if fc.card ~= nil then
         return false, string.format("free_cell[%d].card must be nil initially", i)
      end
      if fc.is_blocked ~= false then
         return false, string.format("free_cell[%d].is_blocked must be false initially", i)
      end
   end
   -- flower slot
   if type(state.flower_slot) ~= "table" then
      return false, "state.flower_slot must be a table"
   end
   if state.flower_slot.occupied ~= false then
      return false, "flower_slot.occupied must be false initially"
   end
   return true
end)

return H
