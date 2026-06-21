**Review of plans/launch-global.md (with PLAN.md, CLAUDE.md, main/Scripts/main.script, main/Scripts/cursor.script + supporting files read for context).** This is a Defold/Lua HTML5 Shenzhen Solitaire (40-card: 3 suits × 9 numbered 2-10 + 12 dragons + 1 flower) targeting Yandex Games. Gameplay core exists; launch focuses on moderation pass + measurement.

I cite plan sections (e.g., track A, §D table, order #1-6, map diagram) and concrete code locations. No files modified.

### (1) Missing blockers/risks that could fail Yandex moderation or break the build
- **SDK integration (D1) is zero in source** — no defold-yagames, no `YaGames.init()`, no `LoadingAPI.ready()`, no `GameplayAPI.start/stop` on start/pause/victory/menu, no `ysdk.environment.i18n.lang`. PLAN §6.1 and launch §D explicitly call these mandatory ("без этого — автоматический отказ"). Current game_manager.script + ui.gui_script + main.script have no hooks. Sandbox run will fail or show as non-compliant.
- **bundle_identifier** remains `com.example.todo` (game.project:31, also [osx]/[android]). PLAN §6.5 and launch §E explicitly flag this. Yandex upload + moderation almost always requires a proper unique ID.
- **HTML5 template gaps vs D2 requirements** (html5/engine_template.html). Some `-webkit-user-select` and body styles exist, but missing or incomplete: explicit `overscroll-behavior: none` (html/body), `touch-action: none` on `#canvas`, full `user-select: none; -webkit-touch-callout: none`, and `window.set_listener` / `WINDOW_FOCUS_LOST` sound mute. D2 table and PLAN §6.2 list these as mandatory.
- **Save/progress (D3) is absent** — zero `sys.save`/`sys.load`/`ysdk.player.setData` anywhere. Board state is distributed (main.tableau_stacks + foundation_top + suit_to_base + base_cards_count, cursor.last_cards/tableau_stacks/free_slots/dragon_buttons, per-slot stacks in tableau/base/free/flower/dragon_button scripts, proxies, GO instances created by factory). "Сыграть пол-партии → reload" is underspecified for verification.
- **Debug pollution + release hygiene** — 59 `print(` / `pprint(` across main/Scripts/* (main.script alone has many in deal/auto/win paths + on_message). DEBUG_DEAL/DEBUG_AUTO_FINISH/DEBUG_DRAGONS/DEBUG_DRAW still present. PLAN §6.5 + launch §E require removal + no debug.keystore/manifest.*.der. Console spam + leftover code risks moderation flags or size.
- **Project title spelling + metadata** — "ShenzenSolitare" (game.project:2, html title, everywhere) vs correct "Shenzhen". Yandex requires RU+EN name/desc/“Как играть” (100-1000 chars) + age rating + categories. None addressed beyond high-level F.
- **Other build/moderation risks**: Font switch (H1) not done (CocomatLight + main_font.font likely lacks full Cyrillic + Turkish diacritics; assets/fonts has ArialBold.ttf but not wired for all GUI text nodes). ui.gui has literal English node texts ("MENU" etc.) that script overrides (risk of flash or fallback). Responsive (PLAN Фаза 5) incomplete per docs. No early sandbox verification called out strongly. Archive structure ("index.html in root") + <100MB must be proven on bob.jar build.

These are mostly in D/E/F + cross-cuts from H. If unaddressed, automatic rejection or broken upload.

### (2) Weak or UNVERIFIABLE acceptance criteria — flagged
- **D3 save AC** ("Перезагрузка страницы → доска восстановлена"): Vague. What exactly is "доска" (card positions + order in 8 stacks + free contents + dragon counters + foundation_top + base_cards_count + blocked flags + tutorial_state)? No schema. Verification ("сыграть пол-партии") is non-deterministic and non-repeatable. (launch §D table, §D3)
- **A4/A5 harness + auto-finish report**: "For ≥1 known solved board выведена последовательность ходов, которую можно проверить глазами" — subjective ("глазами"). No length/complexity bound or golden path file. Auto-finish distrib (median/min/max to can_auto point) is useful but depends on which predicate. (track A criteria)
- **D1 "Игра грузится в песочнице без ошибок" + start/stop on correct boundaries**: Relies on manual sandbox + console. No automated check or list of exact call sites (start on PLAY or post-menu, stop on menu/victory/pause). Settings menu (ui.gui_script) currently does not call stop. (D table, §D1)
- **B4 "Сводная таблица" + "каждая принятая находка → задача"**: Good intent, but "принятая" is undefined (both models? manual override?). No exit criteria for when reviews are "done". (track B)
- **G criteria** ("Незнакомый ... может назвать цель игры и роль free cell/дракона", "Нет дублирующих шагов"): Subjective UX claims. Verifiable only by later playtest (plan acknowledges "визуальный проход ... позже"). Current tutorial_state.lua has rigid 5-step EXPECTED_MOVES + HIGHLIGHTS for a fixed deal; any text/UX change risks breaking it. (track G)
- **C "Каждый ассет явно одобрен" + sizes**: Gate is good, but "без системного UI" and "не скриншот" are visual; `file`/`sips` only catches dimensions. No content policy check. (track C)
- **E "grep ... чисто (или только намеренные)"**: "намеренные" is undefined. Many prints serve cross-collection (e.g. main.update polling sfx.pending). (launch §E)
- **Overall "Геймплей готов" framing**: PLAN still shows open items (card style, effects, full responsive, i18n wiring). Launch assumes core is solid for measurement.

### (3) Flawed parallelization/dependency ordering
Map and order (#1-6) are mostly sound: A/B/C/G parallel, D longest/critical, E waits for A/B/G + D, F waits E+C. H1 early (font blocker), H2 after D1, H3 after H1.

Weak points:
- **B (reviews) + A (solver) + G (tutorial logic review)** run in parallel using the same grok runs, but rule bugs found in B directly invalidate A fidelity work and G "по логике" analysis. Plan notes synergy (A extracts from cursor/main for Фаза 8), but no explicit barrier/synchronization for "rules stable" before heavy solver runs or tutorial text freeze.
- **Debug flags vs E**: Explicitly called out (E blocked until A/B/G closed because DEBUG_* used for A sanity + test deals). Correct, but means A harness must either tolerate or snapshot DEBUG layouts.
- **Save (D3) technically harder than stated**: Distributed state + proxies + factories + animation timing + dragon counters make "пол-партии" reload fragile. No dependency on refactoring (plans/refactoring.md) called out, yet save will likely require central game state snapshot.
- **H3 (all UI/tut texts via i18n) + G8**: Depends on H1 font + runtime set_lang. If font swap affects metrics, tutorial layout + victory/start screen may need tweaks after.
- **C asset apruv gate** is serial (user) — correctly noted as not fully parallel.
- Minor: No callout that A harness (pure Lua) must replicate exact shuffle (main.script:368 `os.time()` + 20 warmups + 3× Fisher-Yates) + Defold Lua PRNG quirks vs host `lua` for run.lua. Det AC is listed but implementation risk.

### (4) Solvability solver design in track A — 'verify %' approach + correctness traps
**Approach is reasonable for initial data** ("раздачу в игре НЕ меняем"; just measure on 1..N; separate filter decision later). Harness (run.lua), three verdicts (solved/unsolvable/timeout), determinism AC, one verifiable path, and auto-finish instrumentation (A5) are good. Parallel per-seed runs ok. Sanity on DEBUG_AUTO_FINISH/DEBUG_DEAL + cross-check vs cursor moves good.

**Soundness issues and traps (rule fidelity, terminal condition, etc.):**
- **Rule source truth is scattered, not just main+cursor** (A1 claim). create_deck/deal (main:62-76, 97+, 367) + cursor hit-tests ok, but actual legality lives in:
  - base_slot.script:13 (`value==2` on empty), 67 (`check_correct_cards`: same suit, +1, reject dragon/flower).
  - tableau_script.script:163 (`can_stack_cards`: different suits, bottom.value == top.value-1, reject specials). Plus visible_cards suffix logic + last_card_to_slot auto-fly (flower/2/d on expose).
  - free_cell.script, dragon_button.script:69 (counter==4 && free_slots_counter>0), free_cell occupy with `complete`/`is_blocked`.
  - card.script:43 (`is_correct_card` has partial duplicate logic).
  Extracting "чистый" rules.lua without missing/dupe edges (stack move of visible suffix, dragon exposure only on top change or free place, free cell single-only, flower only to its slot or auto) is high-risk. Cross-check AC is only "первые N ходов" — insufficient for full paths.
- **Dragon collection modeling is non-trivial**. Not a normal drag; button-only when counters hit 4 (updated via last_card_to_slot + free_cell send_counter_to_button). Collection flies specific tracked cards (dragon_button + cursor get_dragon_cards:640) to one free slot (prefers matching color), sets blocked. Then delayed "dragons_collected" → auto check. Solver must replicate counters, blocked frees, and timing.
- **Auto-finish / terminal condition trap (A1, A5, can_auto_finish main:464)**. Current code predicate: no unblocked dragon in frees + **no dragon/flower anywhere in any tableau_stacks** (deep scan, not just tops) + has_cards. Then auto_finish_step repeatedly does find_next_auto_card (top exposed == foundation_top[suit]+1) and recurses with 0.4s delay; stops (re-enables input) if no next; wins only on all tableau empty post-loop.
  - Contrast with plans/auto-finish.md "safe" predicate (full scan of *all* remaining cards + "for other suits foundation[T] >= V-1" so no blocking for building).
  - Implemented can_auto is weaker. Auto may **halt midway** with input restored even after "can_auto" state. Using the simple predicate as "point where rest доигрывается само" will mis-count moves-to-terminal and mis-label some boards as auto-winning when they require further manual exposes.
  - A5 says "нет драконов/цветка в tableau, все драконы собраны" — close to current code, but "все драконы собраны" is not exact (they can be blocked in frees). Solver must simulate the exact auto sequence or prove remaining cards are always auto-progressible.
- **State space + verdicts**. 40 distinct cards, 8+3+3+1 locations, movable sequences (not arbitrary singles), dragon counters (0-4 per color), blocked flags. IDDFS + transpo will hit explosion or OOM/timeouts on most starting positions. Many "timeout" expected → % of solved among (solved+unsolv) must be carefully reported; raw "solved=N" misleads. Exhaustive "unsolvable" proof only realistic late-game or with heavy domain pruning (not mentioned).
- **Other fidelity**: Win exactly base_cards_count >=27 (main:605, incremented only on numbered card_to_base) **or** (all tableau empty + bases>0). Dragons collected separately. Shuffle must be bit-identical in harness. Tutorial mode and DEBUG layouts must be excluded or isolated.
- **Auto-finish instrumentation** good in principle, but inherits the predicate mismatch.

**Overall**: 'verify %' is sound for measurement phase. Fidelity risk is **high** — one mismatch (e.g., stack visibility, dragon counter, auto stop vs win, 2-auto-fly) invalidates all numbers and paths. Needs golden test deals + move-by-move replay vs live game (beyond "первые N").

### (5) Over- or under-scoped (G tutorial, H i18n)
- **G (tutorial)**: Appropriately scoped for "понятность" review (Claude + grok on logic/texts first). Current implementation is narrow (fixed 10-card/5-step deal in main:284, tutorial_state.lua EXPECTED_MOVES + HIGHLIGHTS + strict check_move that only advances on exact sequence). Findings 1-9 are accurate (no goal stated, terminology mismatch "foundation"/"base"/"база", free cell deposit-only demo, dragon trigger opaque, color-only, no unexpected-move feedback). G1-G8 requirements are concrete and necessary. Not over-scoped; adding symbols (G7) is light accessibility win. Under-scoped risk: real-player validation deferred ("позже"), and fixed-deal may still teach motor pattern more than model. Regress check ("не ломает обычную игру") is listed — good.
- **H (i18n)**: Well-scoped. Current state (i18n.lua:3 lang="en" hardcoded; Turkish mangled "yukle"/"YESIL" etc.; UI texts moved to i18n but .gui nodes + some runtime sets remain; font not switched) matches the description. H1 (real TTF with Cyrillic+diacritics) is the critical shared blocker (affects G, victory, start, counters, settings). H2 (SDK lang → navigator → fallback) correctly depends on D1. H3/H5 audit + wiring is necessary. H4 restore Turkish after font. Not obviously over (no fancy plural/ICU needed). Under risk: font swap may require .font resource changes + atlas regen + layout tweaks (different metrics); lang buttons/runtime switch must actually call set_lang and refresh all nodes (ui.gui_script has partial wiring); numbers ("N/5") + any remaining cam debug labels.

Tutorial + i18n intersect correctly noted. Both tracks are launch-appropriate size.

### Prioritized findings (P0/P1/P2)
**P0 (will fail moderation or build if unaddressed; do first):**
- D1 SDK integration completely missing (no init/ready/start/stop/lang) — automatic rejection per PLAN/launch.
- bundle id still com.example.todo.
- D2 template CSS/JS + focus sound mute incomplete.
- D3 save: no impl + vague AC for complex distributed state.
- E hygiene (debug prints ~59, DEBUG_* flags, bundle artifacts) not started; blocks clean build.
- H1 font (Cyrillic + Turkish) — without it RU/BY/KZ localization fails mandatory req.

**P1 (high correctness/measurement/UX risk; block reliable % or release quality):**
- Track A solver: rule fidelity (scattered logic across 6+ scripts + auto-fly + dragon counters + blocked + visible sequences) + can_auto vs "safe" predicate mismatch + auto may halt. Timeout-heavy % may be noisy. Need exact shuffle replicate + golden replay.
- Save scope underspecified (schema, what to persist, reload invariants during/after anim).
- G tutorial: current rigid deal + check_move means text/UX changes are brittle; goal + terminology + free-cell return + dragon explanation still missing in code.
- Reviews (B) + A/G sharing the same dirty tree: no stabilization gate for rules before heavy solver/tutorial work.
- Debug camera UI + prints always live in prod paths.

**P2 (scope/polish/secondary):**
- C asset policy beyond dimensions (no "non-screenshot" enforcement).
- Weak AC verifiability in several places (eyeball sequence, half-game reload, "понятность" without playtest).
- Minor: project title spelling; potential initial-text flash in .gui before i18n sets; no early sandbox CI step called out; responsive/remaining PLAN items assumed non-blocking.
- Order mostly correct but could add explicit "rules stable" milestone between B and A/G deep work.

The plan is a solid coordination artifact with good parallelism insight and explicit use of the two grok reviewers. The biggest gaps are execution of the mandatory D/E items (currently greenfield in source) and the non-trivial extraction/verification burden in A. Fix P0s before heavy measurement or asset finalization.
