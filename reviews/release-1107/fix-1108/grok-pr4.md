# grok-4.7 — PR #4 (`test/release-validation-1107` @ `4bf6999`), 2026-11-08

- Модель: `grok-4.7` (CLI default), effort по умолчанию, `--output-format json`.
- Завершение: `stopReason=end_turn`, exit 0, текст 5604 симв., session `01a1bb40-0733-7cb2-918d-e23e568d906d`.
- Промпт: дифф `master...4bf6999` без сырых логов и JSON-доказательств, вопросы о ложной
  зелени/красноте оракула, слепоте новых release-сценариев, соответствии доков коду и
  прослеживаемости. sha256 промпта `420716ffd462e7df…`, 72305 байт.
- Grok работал в detached-worktree на `4bf6999`, только чтение; после прогона worktree чистый.
- Передачу диффа в xAI владелец разрешил 2026-11-08 («да, пушь оба и запускай грок»).

Что сделано по замечаниям: nit 2 (R не виден и на решённой раздаче, если первые ~7 ходов
не задели ячейки и первую строку) и nit 3 (возможный ложный красный при отставании игрового
времени) внесены в комментарий харнесса, `reviews/release-1107.md`, CLAUDE.md и описание PR.
Код оракула не менялся.

## Ответ дословно

I'll review PR #4 against the code, starting with the release oracle, the three new scenarios, and the documentation claims.The oracle’s regions and the three new scenarios need to be checked against the board layout and against what a release build actually prints. I’ll verify the `git diff --check` claim the same way.VERDICT: APPROVE

The release oracle can keep a live `debug_flags.enabled` build red, and the three added scenarios do not read Lua logs. I did not re-run the browser matrix. The 11/11 and 6/6 figures match `reviews/release-1107/fix-1108/summary.json`; the older "2 of 7" timeout count is not in this commit.

1. **Question 1 — no scenario-level false green found for a live shared flag.** `strip = (429, 360, 409, 12)` is game x 20–838, y 348–372 (`tools/browser-test.py:874`). Tableau heads sit at y=299; the sprite is offset `(1,-1)` and is 90×150, so its top is y=373. Covered cards use the compact index (image y=1, height 34 on a 300px sheet, about 17 game pixels: `tools/build-vivid.py:64`). That square lies in the strip, including column 1 (left edge x=21). Column 8 loses 1px at x=839; the index is on the left of the card. Space reloads the level and shuffles again (`game_manager.script:87-92`, `main.script:683-689`), so the strip changes. Recorded live-flag runs (`a-neg-debug-1..6`, `a-mflag-1..2`) all fail the Space expect.

Idle portraits do not intersect these rects. The portrait is placed at image y=93 (`tools/build-vivid.py:51`), and `dragon_eligible` requires `exposed` (`main/Scripts/card.script:69-71`). Buried heads stay on the static compact face. Free-cell slots are a static `slot_free` sprite. Hover runs only on a mouse-move action (`cursor.script:77-78`); after PLAY the pointer stays at `(480, 232)` and is not moved again. A normal exposed card (top about y=233) does not reach y=348.

S cannot be seen. `debug_solve` only prints (`main.script:1520-1553`). `tools/browser-test.py:904-905` says so. A live S still fails the scenario when Space changes the strip, because both keys use the same flag.

2. **Nit — R can pass while live, on a solved line that misses both rects.** `reviews/release-1107.md:119-122` names `[REPLAY] timeout` as the remaining limit. The early return is real (`main.script:1570-1573`). A solved replay is also invisible when the directives that land before the sample do not touch the rects. The sample is one frame about 4.25s after key-down: first directive at 0.5s, then every 0.6s (`main.script:37`, `main.script:1700`), so about 7 moves. `to_free_cell` teleports (`free_cell.script:95-98`) and would show up. `to_foundation` / `tableau_to_tableau` do not, once the card has left the rects: foundations are at x=585/689/793, and the lower tableau is below y=348. Concrete input: a debug bundle run with `--release` whose first seven directives are only those two kinds, flights already finished. `after_r == after_s` (`tools/browser-test.py:922-925`) and the R expect passes. In the six recorded negatives this did not happen (first move `to_free_cell` ×4, `to_foundation` ×2, 7 directives, R failed). Those runs still fail on Space, so the scenario does not go green.

3. **Nit — false red if an auto-fly from column 1–3 is inside `cells` on only one sample.** `cells = (169, 457, 149, 60)` is x 20–318, y 397–517 (`tools/browser-test.py:875`), i.e. the bodies of free cells 1–3, not the flower (x=377) or the dragon buttons (x=481). `fly_card_arc` peaks near y=459 (`cursor.script:348-356`), so a 2 or the flower leaving column 1, 2, or 3 crosses that rect for about 0.7s. The idle check is `idle == dealt` after a 4s wait and a 3s wait (`tools/browser-test.py:888-890`). Concrete input: that arc still inside the rect at the first shot and gone three seconds later (game time slowed well behind wall time). The expect fires as "стол меняется сам по себе" on a correct release build. With game time near wall time the deal (~1.05s) plus the arc ends before 4s. The four recorded release `debugkeys` passes did not hit this.

4. **Question 2 — the new scenarios are not log-blind.** `scenario_livingcards`, `scenario_foundationstill`, and `scenario_dragonlife` (`tools/browser-test.py:2451-2587`) never call `wait_for_log` or `logs_matching`. `boot()` skips the "Defold Engine" line when `is_release` is set (`tools/browser-test.py:352-353`). They click the practice button and compare pixels. On a release build they are not forced red by missing prints. `foundationstill` expects stillness, so a frozen portrait passes; the report says that (`reviews/release-1107.md:110-113`), and `a-luaerr-foundationstill` in the summary has an empty failure list while the other two mutants fail on pixel text, with `fatal` 0.

5. **Question 3 — the `--check` sentence matches the tree.** `reviews/release-1107.md:30-33`: `git diff --check 98d8c85 efa3587` reports 43 trailing-whitespace hits, all under `reviews/release-1107/*.log`, and none outside `reviews/`. The same 43 are still present at `4bf6999`. The paragraph does not claim the commit is clean. The R wording in finding 2 is the part that is narrower than the code. Pass counts were not re-run here.

6. **Question 4 — no weakened harness check.** `dev = not s.is_release and ...` (`tools/browser-test.py:837`) forces the pixel oracle on a debug bundle under `--release`. Space is sampled before S and R and compared with `idle`, not with the post-R board (`tools/browser-test.py:906-909`). `PLAN.md` (gate checkbox, shadow, confetti, icons) and `plans/launch-global.md:309` (D3 marked done) are status edits outside this oracle. They do not relax `browser-test.py`.
