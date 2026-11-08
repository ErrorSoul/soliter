# grok-4.7 — PR #5 (`fix/test-guards-1108` @ `4501b4b`), 2026-11-08

- Модель: `grok-4.7` (CLI default), effort по умолчанию, `--output-format json`.
- Завершение: `stopReason=end_turn`, exit 0, текст 5469 симв., session `01a1bb40-06d5-7b70-b49e-855aa33ba3a7`.
- Промпт: дифф `master...4501b4b` без JSON-доказательств; вопросы о пустых тестах,
  числах сверх заявленного поведения, ложной зелени/красноте браузерных оракулов и
  прослеживаемости. sha256 промпта `bca26607573341c3…`, 39251 байт.
- Grok работал в detached-worktree на `4501b4b`, только чтение; после прогона worktree чистый.
- Передачу диффа в xAI владелец разрешил 2026-11-08.

Что сделано по замечаниям — в `reviews/test-guards-1108.md`, раздел «Ревью grok-4.7».

## Ответ дословно

I'll review PR #5 against the code, treating the report and comments as claims. First I'll read the new tests, the scripts they load, and the browser scenarios.The review stays read-only, so I will check the tests against the scripts they load and the browser oracles against layout, without running suites.VERDICT: APPROVE

The three stated behaviours are guarded, and the browser regions do not false-green or false-red on the layout in this tree. Two comments claim more than those behaviours. Lua and browser runs in `reviews/test-guards-1108.md` were not re-executed.

**1. Lua tests.** They can fail when the stated behaviour breaks. They are not stub-tautologies.

`loadfile` runs the real scripts into globals. Each new script test calls `stub.install()` and keeps the function it needs before the next load overwrites `on_message`. `go.set_position` with an id does not overwrite `go_self_pos`, and the tableau test sets that slot to y=299 before `update_visible_cards`. `hash` is `tostring`, so `_motion_` matches the id the card posts.

The tableau test fails if covered cards of a 12-card column are not compact, if the last card is compact, or if a column of 3 or 5 is compact. At slot y=299 the pitch stays 35 until 8 cards and is about 19.8 at 12, so those counts match "long column" in `tableau_script.script:163`. It checks the `exposed` flag the card uses (`card.script:137`), not a second animation. The existing covered-layout check still runs the card.

Collected dragons: a parked dragon must animate, or the test stops as blind. `land(complete=true)` plus `exposed=true` fails if the card ignores `collected`. `occupy_slot` with `complete=true` fails if the cell marks it exposed. The positive control calls real `card.script` `update`.

The drop precondition is not vacuous. The first loop is 3.5 s. A hold delay of 0.7–3 s plus a 2.4 s cycle can finish inside it, and the repeat wait is at most 6 s. The second loop is 8 s and breaks only while `motion.age` is set. Deleting `stop_dragon` in `drop_failed` (`card.script:273`) leaves `age` set.

**2. Numbers beyond the stated behaviours.**

`solver/tests/test_dragon_motion.lua:132` — nit. "an idle portrait waits 18-32 s and keeps a 7 s hover cooldown." The stated rule is a 2–6 s repeat while held. 18–32 and cooldown 7 are the current formulas (`dragon_motion.lua:43` and `:44`). `M.stop` already sets `wait` to `interval`, which is `18+seed%15` (`dragon_motion.lua:25` and `:6`). Concrete input: change the idle branch to `s.interval` and leave the held branch at `2+random*4`. The idle bound stays green. `cooldown==7` does fail if that assignment is removed, because the cycle decays the cooldown started at 7. A constant held wait of 4 s also stays inside 2–6. The 2–6 check itself is not vacuous.

`solver/tests/test_dragon_motion.lua:258` — nit. "the card's landing message reaches the real free cell, and the cell's reply reaches the card." The assert is only `not animated`. Concrete input: delete the `occupy_slot` post in `drop_success` (`card.script:254`). `collected` is already set, so this assert stays green. The two contract asserts still guard "does not animate."

`card.script:82` is not what the timing test calls. Concrete input: pass `false` instead of `self.is_dragging`. The module test still passes `held=true` itself. The first cycle still appears within 3.5 s because `hold()` sets the 0.7–3 s delay. The repeat becomes 18–32 s. Nit: the numbers are guarded, the card's held flag is not.

**3. Browser oracles.** No false green or false red from layout or letterboxing.

PLAY and "play again" are the same node: parent at (480, 270), child at (0, −40), size 280×58, so the face is x 340–620, y 201–259. The button patch is (480, 230) ±90×20, inset about 50 px sideways and 9 px vertically. `menu_left` and `menu_right` move ±7×±9 and are drawn behind the opaque face (`menu_motion.lua:7`). The old ±145×33 box stuck out about 5 px and could see them. The new box does not. Scale 0.94 moves the PLAY label, which sits inside the patch, so a flat "no press" face still fails inequality. `patch` and `brightness` both go through `_map`, and `half` is in game pixels times canvas scale, so the inset holds under letterboxing.

`(400, 232)` ±10 is on that same yellow face, right of the icon (icon ends at x=382) and left of "PLAY AGAIN" (glyphs are centered on x=495 at scale 0.6). The control runs after `start_screen` is disabled (`ui.gui_script:128`), so the PLAY button is not in the sample. In `DEBUG_CELL_DRAIN` only columns 1–3 have cards. Column 5 starts at x=436, so the sample does not hit a card. On `assets/background/table.jpg` mapped onto the 960×540 sprite, that patch is about 60 and the free-cell felt patch is about 41, delta 19, under `GAP` 50. `screen_art.png` there is about 77, delta about 36, still under 50, so the dark victory art without the button does not pass. The yellow face is about luminance 207. This is the asset, not a rendered frame.

**4. Traceability.** No unrelated edit and no weakened check. Press still requires a pixel change and no `I am MAIN SCRIPT`. Cancel still requires the same pixels and no load. The edge click is unchanged. `celldrain` still requires the park, the empty cell, and the auto-finish log. The pixel oracle replaces the table-illustration check that the solid victory background made always red. The extra idle bounds are inside the new test. They are the overclaim in finding 1, not a separate drive-by.
