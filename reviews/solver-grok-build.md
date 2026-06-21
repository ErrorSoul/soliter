**Review of `solver/` (rules.lua + run.lua + tests + SPEC.md) vs. real game rules in `main/Scripts/` (tableau_script.script, cursor.script, base_slot.script, free_cell.script, dragon_button.script, main.script, card.script, flower_slot.script).**

This is a strict, adversarial review focused on fidelity. The solver is an *instrument* for measuring real-game solvable % by seed. Any divergence means it measures a *different game*. All tests currently pass, but they are weak (no cross-validation of deal layout, no adversarial states for dragons-in-free or flower, no layout parity checks against game code).

I read the full game rule sources, solver sources, SPEC, tests (test_moves B1-B7 especially the sequence-break test, test_win, test_deal, test_solvable), harness, run logic, and goldens + executed deals/solves/replays.

### P0 (correctness/fidelity — must fix before any % numbers are trusted)

**solver/rules.lua:191 (compute_dragon_counter) + 292-298 (legal) + 708/799 (mandatory) + 471-508 (apply)**  
Solver counts dragons in non-blocked free cells toward `dragon_counter[suit]`. Game does not.  
- Game: `dragon_button.script:25` (only `send_counter_to_button` from `last_card_to_slot` on tableau top in `tableau_script.script:43-44`) increments `counter`. Free cell occupy (`free_cell.script:32-41`) sends `-1` only to *other* suits' buttons; never increments the owning suit's counter for a parked dragon. Enable is `counter==4 && free_slots_counter>0` (SPEC §3.4 explicitly: "top card of their respective tableau columns").  
- Effect: solver allows `dragon_collect` (and will succeed in search) with e.g. 3 on tops + 1 parked → computed dc=4. Apply only removes current *tableau* tops (leaves the parked one), sets one slot blocked, marks collected. Reaches bogus goal states.  
- Replay may still "pass" (is_win) because 3 removed + marker; real game button inactive.  
- Why fatal: directly falsifies dragon collection rule (user query item 1) and can produce false "solved".  
**Fix**: `compute_dragon_counter` must *only* walk tableau tops (delete the free-cell block, lines ~202-206). Keep parked dragons for state but never for collection gate. Update SPEC comment if needed. Add test case (4 dragons total, 3 tops +1 free unblocked → no collect).

**solver/rules.lua:87-109 (deal) + 69-81 (shuffle) vs. main.script:367-377 + 105-148 (deal_cards)**  
Deal order does not match game for identical seed.  
- Game: `math.randomseed` + 20 warmup + 3 FY (exact match), then `for stack=1..8 do for c=1..5 do table.remove(deck); insert to this stack end end` (consecutive 5 per column; first remove = deck[#] → col1 bottom).  
- Solver: 5 round-robin passes (`for round=1..5; for col=1..8 remove→col`).  
- Concrete (seed 42): game col1 bottoms `d_blue, d_red, 10_blue...`; solver produces entirely different sequence. Same post-shuffle deck → different columns.  
- Tests only assert 8×5 + determinism + composition (pass). Goldens and run.lua `--seeds` are for *solver* deals.  
- Why fatal (user query item 4): "детерминизм раздачи по seed" is broken for measurement. % numbers are for a different distribution of boards.  
**Fix**: rewrite `M.deal` to match game's nested per-column loop exactly (update SPEC §2.2). Regenerate goldens. Add test that for N seeds, the *exact* card at col1[1], col1[5], col2[1] etc. matches a pure-Lua reimplementation of game's deal_cards.

**solver/rules.lua:304-311 (to_free_cell) + 332-368 (single tableau) + 240+ (legal) + 516-525 (flower_auto apply) vs. game auto-fly**  
`legal_moves` generates manual moves for flower (to free cell, to empty tableau). Game never allows this.  
- Game: `tableau_script.script:37 + last_card_to_slot`: the instant flower surfaces as top (`update_stack`/`remove_card`), `send_to_flower_slot` fires; cursor flies it. Manual drag impossible in normal flow. Flower never participates in stacking or free.  
- Solver: no guard on flower for `to_free_cell` or empty `tableau_to_tableau`; only foundation guards it. `apply_mandatory` flies it if top (good), but legal itself is wrong, and a state with flower on top reaching legal (or direct apply) permits illegal actions. Auto only from tableau tops; no path from free→flower_slot.  
- Why P0: violates "моделировать правила" for flower (user query 1) and win (flower must be in slot via correct path).  
**Fix**: add `not card.is_flower` guards in all manual generation sites for flower (to_free, tableau moves). Add dedicated "flower only via auto" test. Make `legal_moves` on a flower-top state return zero manual moves for it.

### P1 (strong fidelity impact, affects paths/% or false modeling)

**solver/rules.lua:453-469 (apply multi) + 370-396 (multi generation) + comments around 340-357; interaction with single loop**  
Single top always generated as `tableau_to_tableau` (correct) + full sub-runs as `multi_to...` (p=s..n-1). Matches cursor `check_tableau_slots` + visible run. B7 passes. Minor: `to_slot` recorded on `to_free_cell` but ignored in `apply` (always re-picks first at apply time). Harmless in DFS/replay but sloppy.

**solver/rules.lua:760-850 (apply_mandatory_tracked) + 671 (unused apply_mandatory) + control flow (goto/continue)**  
Duplicate logic; non-tracked version has no `if changed goto` after flower (falls into 2s check in same sweep). Tracked version has it. 2s auto only on *tableau* (correct vs game `last_card_to_slot`), but safes later greedily pull from free cells (game auto_finish `find_next_auto_card` only does tableau; frees require manual or post-auto). Reachable states same, but recorded paths + onset numbers + greedy behavior diverge. Dead code + inconsistency.

**solver/rules.lua:221-238 (compute_free_slots_counter) + 509-514 (dragon apply only mutates stored fsc) + 292 etc.**  
`compute_*` derives correctly from `free_cells` occupancy/blocked/same-dragon (matches game free_slots_counter mutation rules in free_cell + dragon_button + send_to). But stored `free_slots_counter` in state is only mutated on `dragon_collect` and initial; normal `to_free_cell`/`from_free_cell` do not touch it. After normal play or collect, stored values desync from reality (and from what `compute` would return). `state_hash` correctly omits them; most logic uses compute. Still: vestigial mutable fields + copy in `copy_state`.

**run.lua:183 (replay_and_verify uses is_win) + rules:405-410 (is_win) + 606-619 (is_goal) + test_solvable comments**  
Solver search goal = `is_goal` (tableau empty + no live free cards). Verify uses `is_win` (foundations==10 + flower). For full 40-card deals this coincides (mandatory forces flower_auto + dragon_collect + all nums out). Documented for minis (no flower card) in test_solvable, which does *not* assert is_win. Correct per user query ("все 40 + цветок", not base>=27). But game win paths (`main.script:605 base>=27` on to_base, or `529` all_empty+base>0 in auto) can theoretically trigger with stragglers in free (auto only scans tableau tops). Solver is stricter. Acceptable per explicit request, but note the measurement target.

**solver/rules.lua:448 (tableau_to_tableau always single top) + apply handling of legacy "to_empty_tableau"**  
Legacy move type `"to_empty_tableau"` is handled in apply and serialisation but *never generated* by current `legal_moves` (singles use `tableau_to_tableau` even to empty; multis use their type). Goldens won't contain it. Dead/vestigial.

### P2 (maintainability, minor fidelity, dead code)

- `apply_mandatory` (lines 671-757) completely unused (only `_tracked` called from solve). Delete or make consistent.
- Stored `dragon_counter` / `free_slots_counter` in deal state + copy + manual mutation are misleading (logic always recomputes for dc/fsc).
- In `legal_moves` foundation/to_free etc. generation: order is deterministic but includes many symmetric/equivalent moves; search tree larger than necessary (harmless with budget + visited).
- `state` after deal always includes the counter fields even though derived.
- No simulation of `is_enable=false` beyond `dragons_collected`; fine.
- Long DFS paths (e.g. seed 5 golden ~3k moves) — finds *a* solution, not shortest; within budget or not is a search quality issue, not rules error.
- `can_auto_finish` in solver matches game `main.script:464` scan (full stacks, not visible; live dragon free check). Good.

### Other notes (no bug)

- `can_stack` math (bottom.value == top.value + 1, diff suits, no d/f) matches game `can_stack_cards` + `is_correct_card` (after decoding their inverted param names) and `base_slot.check_correct_cards` (same suit ascending).
- Multi run = only maximal from top, any p >= s sub-suffix to top: matches `update_visible_cards` + `check_tableau_slots`.
- Auto-2 only from tableau tops; flower auto on surface; foundation same-suit +1 or initial 2: modeled.
- Win in verify uses explicit (foundations 10 + flower), not base_count: follows request + SPEC.
- Transposition (state_hash on tableau+found+free status+flower+collected), visited before push, explicit DFS stack, budget on attempts, mandatory after every branch: standard and sound for existence. No obvious cycle/false-positive path to goal.
- Shuffle (seed +20 +3 FY) matches game exactly; tests confirm determinism.

### Summary + priority

1. **Deal layout (P0)** — wrong boards for seeds. Change to game's per-column loop.
2. **Dragon collection gate (P0)** — counts free-cell dragons. Restrict compute to tableau tops only.
3. **Flower manual moves (P1)** — guard them out of legal.
4. Clean dead code, desync fsc fields, unify mandatory logic (P2).

After fixes, re-run full seeds, regenerate goldens, add cross-checks (exact layout for seeds, "3 tops +1 free dragon → no collect", "flower top → no manual moves"). Only then trust the % numbers as measuring *this* game.

The current implementation is close on stacking/multi/foundation/auto-flower/2s/win, has good test coverage for the happy paths it *does* test, and replays pass for the deals it generates. But on the three P0 axes above it models a meaningfully different game.
