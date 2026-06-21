# Shenzhen Solitaire — Pure-Lua Solver Specification

This document is the canonical, self-contained rule specification for a pure-Lua
solver. Every rule is derived directly from the game source; deviations from
"standard Shenzhen IO" are called out explicitly.

---

## 1. Card Model (40 cards total)

### 1.1 Suits
Three suits: `"red"`, `"blue"`, `"green"`.

### 1.2 Numeric cards (27 total)
Each suit contains 9 numeric cards with integer values `2, 3, 4, 5, 6, 7, 8, 9, 10`.
**There is no value-1 card.** The deck starts at 2.
(Standard Shenzhen IO uses 1–9; this game uses 2–10.)

### 1.3 Dragon cards (12 total)
Each suit contains exactly 4 dragons. Dragon cards carry:
- `value = "d"` (string sentinel)
- `is_dragon = true`
- `suit` = one of `"red"`, `"blue"`, `"green"`

### 1.4 Flower card (1 total)
One flower card:
- `value = "f"` (string sentinel)
- `suit = "flower"`
- `is_flower = true`

### 1.5 Deck summary
| Type     | Per suit | Suits | Total |
|----------|----------|-------|-------|
| Numeric  | 9 (2–10) | 3     | 27    |
| Dragon   | 4        | 3     | 12    |
| Flower   | 1        | —     | 1     |
| **Total**|          |       | **40**|

---

## 2. Initial Deal (deterministic by seed)

### 2.1 Shuffle
```lua
math.randomseed(seed)          -- seed = os.time() in live game
for _ = 1, 20 do math.random() end   -- 20 warmup calls discarded
-- 3 passes of Fisher-Yates (descending):
for pass = 1, 3 do
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end
```
Note: three Fisher-Yates passes produce the same distribution as one; the triple
pass is a game-source artifact, not a correctness requirement, but a solver
replaying a seed must replicate it exactly.

### 2.2 Deal layout
8 tableau columns. With 40 cards and 8 columns: 40 / 8 = 5 cards each, no
remainder — all columns get exactly 5 cards.

Deal order: **COLUMN-MAJOR**. The outer loop iterates columns 1–8; the inner loop
fills all 5 cards of that column before moving to the next. Cards are removed from
the END of the shuffled deck (`table.remove(deck)` with no index).

```
for col = 1, 8 do
    for card_index = 1, 5 do
        tableau[col][card_index] = table.remove(deck)
    end
end
```

Column 1 receives deck[40..36] (card_index 1 = bottom), column 2 receives
deck[35..31], …, column 8 receives deck[5..1].

This matches `deal_cards` in `main/Scripts/main.script` (outer `stack_index=1..8`,
inner `card_index=1..cards_in_stack`, each body calls `table.remove(self.deck)`).

Vertical offset within a column: each successive card is 35 px lower on screen
(for display; irrelevant to solver logic).

### 2.3 Board zones
- **Tableau**: 8 columns (stacks), initially 5 cards each.
- **Foundation**: 3 slots, one per suit, initially empty. Tracks `foundation_top[suit]` starting at `1` (meaning "waiting for value 2").
- **Free cells**: 3 slots, initially vacant.
- **Flower slot**: 1 slot, initially empty.
- **Dragon buttons**: 3 buttons (one per suit), initially inactive.

---

## 3. Legal Move Types

### 3.1 Tableau stacking (single card or multi-card run)

#### Legality predicate: `can_stack(bottom, top)`
```
can_stack(bottom, top) =>
    bottom is not nil AND top is not nil
    AND NOT bottom.is_flower AND NOT bottom.is_dragon
    AND NOT top.is_flower AND NOT top.is_dragon
    AND bottom.suit ~= top.suit          -- DIFFERENT suits required
    AND bottom.value == top.value - 1    -- bottom is exactly one less
```

**Critical divergence from standard Shenzhen IO:** standard allows same-suit
stacking; this game requires DIFFERENT suits.

The two predicates used in source (`can_stack_cards` in tableau_script.script and
`is_correct_card` in card.script) encode the same rule from opposite perspectives:
- `can_stack_cards`: `bottom.value == top.value - 1` (bottom is lower)
- `is_correct_card`: `target.value == incoming.value + 1` (target/bottom is higher)

Both mean: place a lower card onto a higher card of a different suit.

#### Single-card tableau move
A single card may be dragged from the top of any tableau column (or from a free
cell) and placed onto the top card of another column if `can_stack` passes, or
onto any empty tableau column unconditionally (any card type accepted).

#### Multi-card run (stack drag)
**Pick-time validity IS enforced by the game** (`update_visible_cards` in
tableau_script.script:86-144 → cursor `set_stack`). Only the **maximal valid run
at the top of a column** is grabbable. Let a column be `cards[1..n]` (index 1 =
bottom, index n = top). Define `s` as the smallest index such that for every
adjacent pair `k` in `[s, n-1]`, `can_stack(cards[k], cards[k+1])` holds (i.e.
`cards[s..n]` is a valid alternating-suit, strictly-descending run). A drag may
pick up `cards[p..n]` for any `p` with `s <= p <= n`. Cards below `s` (buried under
a sequence break) are **not** grabbable and never appear in the selectable set.

> A multi-card grab spanning a sequence break (e.g. column `{8_red, 5_blue, 4_green}`:
> 8_red and 5_blue are not adjacent in value, so the valid run is `5_blue,4_green`;
> grabbing 8_red as part of a multi-card move is ILLEGAL) must NOT be enumerated.

The drop is legal only if:
- The bottom card of the dragged run (`cards[p]`) satisfies `can_stack(target_top, cards[p])`, OR
- The target column is empty (accepts any run; in practice only valid runs are grabbable).

Multi-card runs may only be dropped onto tableau columns (top cards or empty
columns). Free cells, foundation slots, and the flower slot are not valid targets
for multi-card drops.

### 3.2 Foundation placement

Foundation accepts only numeric cards (not dragons, not the flower).

**Empty foundation slot:** accepts any card with `value == 2` (any suit). No suit
is pre-assigned; the first card placed determines the suit of that slot.

**Non-empty foundation slot:** `check_correct_cards(slot, card)` =>
```
NOT card.is_flower
AND NOT card.is_dragon      -- tested as card.id_dragon in source (likely bug;
                            --   harmless because "d" string fails numeric +1 test)
AND card.suit == slot.last_card.suit    -- SAME suit
AND card.value == slot.last_card.value + 1   -- exactly one higher
```

Foundation sequence per suit: 2, 3, 4, 5, 6, 7, 8, 9, 10 (9 cards per suit).
`foundation_top[suit]` is initialised to `1`; first accepted value is `2`
(`foundation_top + 1 == 2`).

### 3.3 Free cell: single-card move in/out

**Move in (occupy):** any single card (numeric, dragon, or flower) may be placed
into a free cell slot that is not occupied (`not self.is_occupied`). No suit or
value restriction.

**Move out (pick):** a card may be removed from a free cell only if
`is_occupied AND NOT is_blocked`. A blocked slot (see dragon collect) cannot be
picked from; it is permanently inaccessible.

### 3.4 Dragon-collect compound move

**Enable condition:** a dragon-collect button for suit S becomes active when ALL
of:
1. `counter[S] == 4` — all 4 dragons of suit S are exposed as the **top card of
   their respective tableau columns**. The counter is incremented by 1 for each
   such exposed dragon via the `send_counter_to_button` message in
   `tableau_script.script:44`, which fires after every stack change.
   **Important:** this counter tracks **tableau-tops only**. A dragon of suit S
   sitting in a free cell (non-blocked) does NOT increment the counter in the
   live game. The solver's `compute_dragon_counter` adds free-cell dragons for
   convenience (to simplify collect eligibility); this deviates from the strict
   game counter but is functionally safe because the collect move still removes
   all 4 dragons from their actual locations.
2. `free_slots_counter[S] > 0` — at least one free cell slot is available from
   the perspective of suit S. This counter starts at 3 and is decremented by 1
   for each occupied free cell (with cross-suit accounting: a dragon of suit S
   already in a free cell does NOT decrement suit S's counter — it will host the
   collected pile; a dragon of another suit or any non-dragon card decrements all
   buttons' counters).

**Effect of collecting dragons for suit S:**
1. Target slot selection: prefer a free cell already holding a dragon of suit S;
   otherwise take the first empty free cell.
2. All 4 dragons fly (animated arc) to that target slot with staggered delays.
3. The target slot's `is_blocked` flag is set to `true` — it becomes permanently
   occupied and inaccessible for the rest of the game.
4. The dragon button for suit S is permanently disabled (`is_enable = false`);
   it cannot be reactivated.
5. After a 1.5 s delay, a `dragons_collected` message triggers an auto-finish
   check.

**Post-collect free cell state:** a blocked slot counts as occupied for all
purposes except the same-suit dragon button's `free_slots_counter` (because that
suit's 4 dragons now reside there). Cards cannot be placed into or removed from a
blocked slot.

### 3.5 Flower auto-to-slot

The flower card (value `"f"`) is never manually playable in normal game flow; it
auto-flies the moment it surfaces as the top card of any tableau column:

- After every `update_stack` or `remove_card` event on a tableau column,
  `last_card_to_slot()` checks the new top card.
- If `top_card.value == "f"`, the card is immediately dispatched via
  `send_to_flower_slot` to the cursor, which animates an arc flight to the
  flower slot.
- The flower slot accepts only the flower card (`value == "f"`) and only when
  empty. After the flower lands the slot is permanently occupied.
- The flower never participates in tableau stacking (`can_stack` returns false if
  either card `is_flower`).

Manual drag of the flower to the flower slot is technically possible (cursor does
check the slot on release), but auto-fly fires before the player can act.

### 3.6 Auto-move of 2s to foundation

After every `update_stack` or `remove_card` event on a tableau column,
`last_card_to_slot()` also checks:
```
if top_card.value == 2 AND NOT tutorial_state.is_tutorial then
    -- auto-fly this card to the foundation (base slot)
end
```

Only value `2` triggers auto-move here. Higher ranks (3–10) do not auto-move;
they cascade only during the `auto_finish` sequence (see section 5).

---

## 4. Win Condition

**Correct win condition for the solver:**

The game is won when:
- All 27 numeric cards (values 2–10 for each of 3 suits) are in the foundation.
- The flower card is in the flower slot.
- All 12 dragon cards are in blocked free cell slots (collected via dragon buttons).

Equivalently: `foundation_top["red"] == 10 AND foundation_top["blue"] == 10 AND
foundation_top["green"] == 10 AND flower_slot.occupied == true AND all 3 dragon
buttons have been activated`.

**Implementation bug in the actual game (base_cards_count >= 27):**

The live game triggers victory at `base_cards_count >= 27` (`main.script:605`).
`base_cards_count` only counts cards sent to foundation slots (numeric cards).
Dragons go to blocked free cells (never incrementing `base_cards_count`); the
flower goes to its own slot (also never incrementing `base_cards_count`). Because
the maximum possible value of `base_cards_count` is exactly 27 (all numeric
cards), the condition `>= 27` is functionally equivalent to `== 27` in practice.

This means **the live game can trigger victory while dragons are still on the
tableau** if, hypothetically, all 27 numeric cards reached the foundation without
dragon collection — `can_auto_finish` guards against this during auto-finish by
blocking when live dragons exist in free cells or on the tableau, but a manual
play sequence could reach the threshold first.

For a correct solver, use the explicit condition:
```
foundation_top.red   == 10
AND foundation_top.blue  == 10
AND foundation_top.green == 10
AND flower_slot.occupied == true
-- (dragons in blocked free cells is implied by the above being reachable)
```

---

## 5. `can_auto_finish` — As Implemented vs. Safe Predicate

### 5.1 As implemented (`main.script:464–498`)

```lua
function can_auto_finish(self, message)
    if self.tutorial_mode then return false end      -- (1)
    if self.auto_finishing then return false end     -- (2)

    -- (3) Live (unblocked) dragon in any free cell blocks auto-finish
    for _, fc in pairs(message.free_cells) do
        if fc.dragon and not fc.is_blocked then
            return false
        end
    end

    -- (4) Any dragon or flower still in any tableau column blocks auto-finish
    for i = 1, 8 do
        local stack = self.tableau_stacks[i]
        if stack and stack.cards then
            for _, card in ipairs(stack.cards) do
                if card.data.is_dragon or card.data.is_flower then
                    return false
                end
            end
        end
    end

    -- (5) At least one tableau column still has cards (not a trivially empty board)
    local all_empty = true
    for i = 1, 8 do
        local stack = self.tableau_stacks[i]
        if stack and stack.cards and #stack.cards > 0 then
            all_empty = false
            break
        end
    end
    if all_empty then return false end

    return true
end
```

**What it checks:**
- Blocks during tutorial.
- Blocks if already running.
- Blocks if any live (non-blocked) dragon is in a free cell.
- Blocks if any dragon or flower remains anywhere in the tableau.
- Blocks if all tableau columns are already empty (no cards left to move).
- Does NOT check whether the remaining numeric cards are actually safe to move
  (i.e., no cross-suit dependency check).
- Does NOT check free cells for numeric cards — a numeric card stranded in a free
  cell will be picked up by `auto_finish_step` which explicitly checks free cells
  in its `find_next_auto_card` loop.

**`find_next_auto_card` (`main.script:500–514`):**
Iterates tableau columns 1–8. For each non-empty column takes the top card.
Skips dragons and flowers. Accepts a card if:
```
top_card.value == foundation_top[top_card.suit] + 1
```
Returns the first such card found (no suit-priority ordering).

**`auto_finish_step` pacing:** 0.4 s delay between moves.

### 5.2 Safe predicate from `plans/auto-finish.md`

The plan defines a tighter "safe auto-move" check per card:

```lua
function can_move_to_foundation(card)
    if card.is_dragon or card.is_flower then return false end
    local foundation_top = get_foundation_top(card.suit)
    if card.value ~= foundation_top + 1 then return false end

    -- Safe check: no other suit is more than 1 behind this card's value
    local min_other = 10
    for _, suit in ipairs({"red", "blue", "green"}) do
        if suit ~= card.suit then
            min_other = math.min(min_other, get_foundation_top(suit))
        end
    end
    return card.value <= min_other + 1
end
```

Semantics: a numeric card of value V and suit S is safe to move to foundation if
`V == foundation[S] + 1` AND for every other suit T: `foundation[T] >= V - 1`.
This guarantees no card of another suit still needs a card of value V-1 for
tableau stacking (since those cards are already in the foundation).

### 5.3 Difference table

| Aspect | As implemented (`main.script`) | Safe predicate (`plans/auto-finish.md`) |
|--------|-------------------------------|----------------------------------------|
| Dragon guard | Checks tableau + non-blocked free cells | Rejects any dragon/flower remaining anywhere |
| Cross-suit dependency | **Not checked** — moves the first sequentially available card regardless of other suits | **Checked** — only moves a card if all other suits are within 1 value behind |
| Free cell numeric cards | Checked by `find_next_auto_card` after tableau check | Checked explicitly in the greedy loop |
| Risk of incorrect auto-finish | Can move a card that another suit still needs for stacking if suits are misaligned | Guaranteed safe — no premature move |
| Trigger condition | Gates the entire auto-finish session (binary start/no-start) | Per-card gate inside a greedy move loop |

**Practical implication for solver:** The as-implemented `can_auto_finish` is a
coarse gate (starts if no dragons/flower remain in play) that trusts all remaining
numeric cards are in order. The safe predicate is a per-move check that prevents
moving a card whose value is needed by other suits for stacking. A solver should
implement the safe predicate to avoid generating illegal or suboptimal move
sequences during its search.

---

## 6. Solver State Representation

Minimum state required for a correct solver:

```lua
state = {
    -- Tableau: 8 columns, each an ordered array (index 1 = bottom)
    tableau = { {card, ...}, ... },   -- 8 arrays

    -- Foundation top value per suit (1 = empty, 2–10 = highest placed)
    foundation_top = { red=1, blue=1, green=1 },

    -- Free cells: 3 slots
    free_cells = {
        { card=nil, is_blocked=false },  -- nil card = empty
        { card=nil, is_blocked=false },
        { card=nil, is_blocked=false },
    },

    -- Flower slot
    flower_slot = { occupied=false },

    -- Dragon buttons (per suit): collected or not
    dragons_collected = { red=false, blue=false, green=false },

    -- Dragon button counters (exposed dragons per suit)
    dragon_counter = { red=0, blue=0, green=0 },

    -- Free-slot counter per suit (for dragon button enable check)
    free_slots_counter = { red=3, blue=3, green=3 },
}
```

A card is represented as:
```lua
card = {
    value  = 2..10 | "d" | "f",
    suit   = "red"|"blue"|"green"|"flower",
    is_dragon  = true|nil,
    is_flower  = true|nil,
}
```

---

## 7. Move Enumeration for Solver

At each state the solver should enumerate moves in these categories:

1. **Flower auto-fly** (mandatory, not a player choice): if any tableau top card
   has `value == "f"`, apply it immediately — it is not a branching move.

2. **Auto-move value-2 to foundation** (mandatory in non-tutorial play): if any
   tableau top card has `value == 2`, apply it immediately.

3. **Dragon collect** for suit S: legal if `dragon_counter[S] == 4` and
   `free_slots_counter[S] > 0`. Effect: removes 4 dragons from their tableau
   tops, occupies+blocks one free cell slot, updates all counters.

4. **Numeric card to foundation**: top card of tableau column i, or card in free
   cell slot j, if `card.value == foundation_top[card.suit] + 1`.

5. **Single card: tableau top to tableau top**: `can_stack(target_top, card)` as
   defined in 3.1.

6. **Single card: tableau top to empty tableau column**: always legal for any
   card.

7. **Single card: tableau top to free cell**: legal if any free cell is unoccupied
   and not blocked.

8. **Single card: free cell to tableau top**: `can_stack(target_top, cell_card)`.

9. **Single card: free cell to empty tableau column**: always legal.

10. **Multi-card run: run to tableau top**: only runs `cards[p..n]` where `p >= s`
    (the maximal valid run from the top, per 3.1); legal if
    `can_stack(target_top, cards[p])`. Do NOT enumerate runs that span a sequence
    break — those are not grabbable in the game.

11. **Multi-card run: run to empty tableau column**: same grabbability constraint
    (`p >= s`); the empty target then accepts the run.

Mandatory moves (1, 2) should be applied deterministically before branching.
Dragon collect and foundation moves should be applied greedily (they are never
harmful). Moves 5–11 are branching moves for the search tree.

---

## 8. Key Implementation Gotchas

- Numeric values are `2..10` (integers), not `1..9`. The solver must never
  generate or accept value `1` or value `11`.
- Dragon value is the string `"d"`, flower value is the string `"f"`. Arithmetic
  on these strings is undefined; always guard with type/sentinel checks.
- `can_stack` requires DIFFERENT suits. Same-suit tableau stacking is ILLEGAL.
- Foundation requires SAME suit, ascending by 1.
- Free cells accept ANY card type (including dragons and flowers); there is no
  type restriction at placement.
- A blocked free cell slot is permanently inaccessible — neither placing into nor
  removing from it is legal.
- Empty tableau columns accept ANY card (no restriction by type or value).
- Multi-card grabs are restricted to the maximal valid run at a column's top (see
  3.1). A run spanning a sequence break is NOT grabbable — the solver must not
  enumerate it, or it will model physically-impossible moves ("different game").
- The `id_dragon` field tested in `base_slot.script` is a likely typo for
  `is_dragon`; in practice the dragon guard on foundation is enforced by the
  value-arithmetic check (`"d" + 1` is not a valid numeric comparison) rather than
  the boolean flag.
- Victory requires `foundation_top.red == 10 AND foundation_top.blue == 10 AND
  foundation_top.green == 10` — do not use `base_cards_count >= 27` as the win
  test in the solver (see section 4).
