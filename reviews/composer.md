Reviewing the launch plan and related context files for a critical assessment.
Gathering more context on Yandex blockers, i18n, slot validation, and auto-finish logic.
# Critical Review: `plans/launch-global.md`

Review against `PLAN.md`, `CLAUDE.md`, `main.script`, `cursor.script`, and current codebase state. The plan is well-structured as a parallel launch map, but several **mandatory Yandex blockers are missing or under-specified**, Track A has serious fidelity traps, and the dependency graph understates H (i18n) and overstates independence of G.

---

## 1. Missing Blockers / Risks (Moderation & Build)

### D — Yandex SDK path (incomplete vs reality)

| Gap | Evidence |
|-----|----------|
| **D1 not integrated** | Zero `ysdk`/`YaGames` usage in repo; `game_manager.script` has no `LoadingAPI` / `GameplayAPI` hooks. |
| **D2 HTML5 template not compliant** | `html5/engine_template.html` lacks `overscroll-behavior: none`, `touch-action: none` on `#canvas`, and `window.set_listener` mute on `WINDOW_FOCUS_LOST`. D2 lists these; they are not done. |
| **D3 save is greenfield + underspecified** | No `sys.save`/`sys.load`/`ysdk.player.setData` anywhere. Board state spans proxied collection, many GOs, animations, dragon counters — far harder than “play half a game → reload”. No schema, no scope (in-progress only vs menu/settings/tutorial flags). High risk of silent moderation fail. |
| **GameplayAPI lifecycle gaps** | D1 requires start/stop on menu/pause/victory. Settings menu (`ui.gui_script`) opens with no `GameplayAPI.stop`; start screen vs in-game boundary unclear. |
| **H mandatory for RU/BY/KZ not on critical path** | `PLAN.md` §6.4 is mandatory; launch-global puts H parallel to D but critical path is only `D → E → F`. Cyrillic UI can ship broken and still reach F. |

### E — Cleanup scope too narrow

| Gap | Evidence |
|-----|----------|
| **Camera debug UI ships** | `ui.gui` / `ui.gui_script` expose `cam_y_plus`, `cam_fov_minus`, etc. — always pickable, not behind a flag. **Not listed in E.** Moderation risk: debug tooling in production. |
| **E grep misses most debug noise** | `cursor.script` / `main.script` / `tableau_script.script` / `free_cell.script` have many `print`/`pprint`. E only greps `main/Scripts/`; ignores `gui/`, `render.render_script`, etc. |
| **Secrets in tree** | `debug.keystore`, `manifest.*.der` untracked; E mentions removal but not `.gitignore` / CI guard. |

### Gameplay bugs (not in plan, can fail moderation QA)

| Gap | Evidence |
|-----|----------|
| **Premature victory** | `main.script` fires WIN at `base_cards_count >= 27` — only numbered cards, not dragons/flower. A player can “win” with dragons still on tableau. |
| **`can_auto_finish` weaker than design** | Implementation checks “no dragons/flower in tableau + has cards”, not the safe-move rule in `plans/auto-finish.md`. Can trigger auto-finish incorrectly; solver A5 inherits this if it reuses `can_auto_finish`. |

### Not scheduled at all

| Gap | Source |
|-----|--------|
| **Responsive / mobile layout** | `PLAN.md` §5: GUI anchors, multi-resolution testing — absent from launch-global. `game.project` uses `scale_mode = stretch`; custom projection exists but anchors incomplete. Mobile scroll/layout failures are common moderation rejects. |
| **F metadata validation** | F mentions RU+EN description lengths; no acceptance gate, no draft checklist before submit. |
| **Asset dimension inconsistency** | C2 says **800×470**; `PLAN.md` §6.6 says **800×450**. Wrong cover = upload rejection. |

### A — Product risk deferred

Verify-only (A intro) measures solvability % but **does not define action if % is low** (filter deals, reseed, cap retries). Shipping random deals with high unsolvable rate is a moderation/retention risk; plan explicitly defers filter decision.

---

## 2. Weak / Unverifiable Acceptance Criteria

| Section | Criterion | Problem |
|---------|-----------|---------|
| **A** | “≥1 known solved board” + eyeball move sequence | Subjective; no automated replay against `rules.lua`. |
| **A** | “Зафиксирован измеренный %” | Records a number but no threshold, confidence interval, or N≥1000 statistical method. |
| **A** | Auto-finish median/min/max | No pass/fail vs live `can_auto_finish`; distribution alone doesn’t prove correctness. |
| **A** | Cross-check “first N moves” vs `cursor.script` | Wrong layer — cursor delegates to slot scripts; cross-check should be `rules.lua` vs `base_slot`/`card`/`tableau_script`/`free_cell`. |
| **B** | “Отложено, не блокер” | Subjective escape hatch; no severity rubric (crash/data loss vs nit). |
| **B** | “Must-have tests added and pass” | No enumeration of which tests; no CI/`lua` runner gate. |
| **D1** | “Loads in sandbox without SDK errors” | No checklist: `init` timing, `LoadingAPI.ready` moment, `start` after PLAY, `stop` on menu/victory. |
| **D2** | “No scroll on mobile” | Manual only; no device matrix; template not yet compliant. |
| **D3** | “Half game → reload → restored” | No field list, dragon state, foundation tops, free cells, tutorial flag, animation mid-flight. |
| **G** | “Незнакомый человек может назвать цель” | Not measurable; “Claude + grok review” is not user testing. |
| **G** | “Нет дублирующих шагов” | Qualitative; G1 intro may add overlap without step-count update. |
| **G** | “Термины согласованы en/ru/tr” | No glossary artifact or automated key parity check. |
| **H** | “Кириллица без квадратов” | Visual only; no screenshot diff / font atlas coverage test. |
| **H** | “`grep` чисто” | Misses `ui.gui` literals, dynamic `string.format`, render/GUI scripts; false negatives likely. |
| **H** | “Эмуляция `navigator.language`” | Doesn’t require sandbox test of `ysdk.environment.i18n.lang` (H2’s primary source). |
| **E** | `grep DEBUG_\|print(` in `main/Scripts/` | Too narrow; camera debug UI unaffected; many prints elsewhere. |
| **F** | Description 100–1000 chars RU+EN | No automated length/count validation before submit. |
| **C** | “Соответствует требованиям Я.Игр” | No link to current spec version; cover size conflict unresolved. |

---

## 3. Flawed Parallelization / Dependency Ordering

### Contradictions in dependency map (lines 17–41)

1. **“A,B,C,G не блокируют ничего”** — false. **E explicitly waits on A,B,G** (line 232). B’s fixes should gate E too, but B is parallel with no merge barrier before E.

2. **Critical path `D → E → F` omits H** — H1 blocks G8/H3; H is mandatory for RU market per `PLAN.md` §6.4. Real path: `D1 → H2; H1 → H3 → G8; … → E → F`.

3. **G “независим от D”** — G8 requires `i18n.t()`; H2 requires D1 for SDK language. G text rework should not start “clean” until H1+H3 are at least scoped.

4. **Start order (lines 245–247)** starts **G review + H1 in parallel** — OK for audit, but **G implementation (G1–G7) before H3** will cause rework (hardcoded hints, term churn).

5. **B + G “общий прогон grok”** — fine for review, but conflates code review (B) with UX/content review (G); different outputs, no separate acceptance.

6. **C approval gate** — correctly sequential for user, but F depends on C while C can finish late; no buffer for moderation resubmit if assets rejected.

7. **Responsive (PLAN §5)** — not on any track; will collide with D2 mobile testing and F screenshots.

### Recommended ordering fix (conceptual)

```
D1 → H2
H1 → H3 → G (implementation)
D2, D3 (parallel after D1; D3 needs design doc)
A, B (parallel; B fixes block E)
C (parallel early for approval lead time)
E → bob build → F
```

---

## 4. Track A — Solver / Verify % / Auto-Finish

### Is verify-% sound?

**As measurement, partially sound. As launch gate, incomplete.**

- Measuring `solved / unsolvable / timeout` over seeds without changing live deal is reasonable for data gathering.
- Plan correctly separates `timeout` ≠ `unsolvable` (A3, A acceptance).
- **No decision rule**: if `timeout` dominates (likely), reported “solvability %” is a lower bound, not true rate. No guidance on N, seed range, or budget calibration.
- **No connection to player experience**: game still uses `math.randomseed(os.time())` (main.script:368); A2 seed injection is harness-only until integrated.

### Correctness traps

| Trap | Detail |
|------|--------|
| **Rule fidelity — scattered source of truth** | Rules live in `base_slot.script`, `card.script` (`is_correct_card`), `tableau_script.script` (`can_stack_cards`), `free_cell.script`, `flower_slot.script`, plus **automatic moves** in `tableau_script.last_card_to_slot` (2→foundation, flower→slot, dragon→button counter). “Extract from main+cursor” (A1) is **insufficient** — cursor is input routing, not rules. |
| **Implicit auto-moves not in player-move solver** | When a 2 is exposed, game auto-sends to foundation (`send_to_base_slot`). DFS modeling only explicit drags will diverge from reachable states unless solver simulates the same triggers. |
| **Dragon button = compound move** | Collecting 4 dragons + free-cell slot logic + 1.5s delayed `dragons_collected` — solver must model button action, not just card drags. |
| **Win condition mismatch** | Game WIN at 27 foundation cards (`main.script:605`) ≠ full Shenzhen win (dragons + flower). Solver “solved” must define terminal state explicitly or inherit the bug. |
| **`can_auto_finish` terminal (A5)** | Reusing `main.script:464` `can_auto_finish` is **unsafe**: it omits safe-move predicate from `plans/auto-finish.md`. Solver may mark auto-finish point while game still requires stacking moves, or vice versa. |
| **`unsolvable` proof** | Full DFS + transposition for 40-card Shenzhen with free cells is enormous. With node/time budget, almost all hard deals → `timeout`. “Unsolvable” count will be near zero and statistically meaningless. |
| **Shuffle reproducibility** | Live shuffle: `os.time()` + 20 warmup + **3× Fisher-Yates** + optional `DEBUG_DEAL` path. Harness must bit-match this exactly; any drift invalidates verify %. |
| **Sanity test mismatch** | DEBUG_AUTO_FINISH layout is hand-dealt (`deal_auto_finish_test`), not seed-based — sanity checks one path, not seed pipeline. |
| **Stack drag rules** | Visible-stack logic (`update_visible_cards` + consecutive cross-suit descending) must match multi-card moves in solver. |

### Verdict on A

The **architecture** (pure `rules.lua` + harness) is right. The **verification strategy is not yet sound** without: (1) rules extracted from all slot scripts + auto-fly paths, (2) explicit win terminal, (3) auto-finish predicate aligned with design or formally declared as “game’s actual predicate”, (4) calibrated timeouts and honest reporting that `% solved` is “solved within budget”.

---

## 5. Over- / Under-Scoped Tracks

### G — Tutorial

**Over-scoped for launch gate:**
- **G6** (soft feedback on unexpected moves) — polish, not moderation.
- **G7** (accessibility symbols beyond color) — may need art/card atlas changes; large scope for pre-launch.

**Under-scoped:**
- **G4** (free-cell retrieve): current fixed 10-card layout (`deal_tutorial_cards`) never requires picking from free cell — explaining buffer without a step is weak; may need new step + layout change (not planned).
- **G1** intro step: step count still “5” in `tutorial_step` / `EXPECTED_MOVES`; no acceptance update.
- **Visual UX** explicitly deferred (“user provides screenshots later”) — under-scoped for a track whose problem is *comprehension*, not code correctness.
- **SKIP / restart flows** after copy changes — no acceptance.
- **Term unification (G3)** touches code (`base` vs `foundation`), i18n keys, hints — no glossary deliverable; overlaps H but not sequenced.

### H — i18n

**Over-scoped:**
- **H5** full-project grep for user strings — high effort, diminishing returns; needs scoped file list.

**Under-scoped:**
- **Manual language picker** already in settings (`ui.gui_script` LANG_BUTTONS) — not in H requirements; conflicts with H2 “auto from SDK” (need precedence rules).
- **Typography/layout**: RU strings longer than EN; no truncation/overflow criteria for buttons.
- **H4**: restoring diacritics ≠ linguistic QA for TR.
- **Store metadata** (F) separate from H — descriptions “как играть” not in H.
- **PLAN §6.4 ArialBold** vs **H1 Noto Sans** — conflicting font strategy; pick one.
- **Victory / play_again texts**: `update_all_texts()` omits some nodes (e.g. `victory` title, `play_again`) — H3 acceptance may pass grep while UI still shows English from `ui.gui`.

---

## Prioritized Findings

### P0 — Ship / moderation blockers

1. **[D1+D2+D3]** Yandex SDK, HTML5 template compliance, and save — listed but largely unimplemented; D3 has no data model. *Sections D, F.*
2. **[H not on critical path]** Localization mandatory for RU/BY/KZ (`PLAN.md` §6.4) but omitted from `D → E → F`. *§17–41, H.*
3. **[Victory bug]** `base_cards_count >= 27` can declare win before dragons/flower resolved — live bug, not in plan. *Implied by A1 “win condition” but unaddressed.*
4. **[E scope]** Camera debug UI and broad `print` debug not in cleanup — will ship in release. *E.*
5. **[bundle id]** Still `com.example.todo`. *E, game.project.*
6. **[Cover size]** 800×470 (C2) vs 800×450 (`PLAN.md`) — unresolved; wrong asset blocks upload. *C, F.*

### P1 — High risk / likely rework

7. **[A rule fidelity]** Rules extraction from `main`+`cursor` only; misses slot scripts + auto-fly/dragon/flower automation. *A1, A “Как верифицируем”.*
8. **[A auto-finish terminal]** Reuses simplified `can_auto_finish` ≠ `plans/auto-finish.md` safe predicate. *A5, A1.*
9. **[A verify %]** No threshold, no filter policy, timeout-dominated stats; seed path not wired to live deal. *A intro, A2.*
10. **[Parallelization]** G implementation before H3; “A/B/G don’t block” contradicts E; B fixes don’t gate E. *§17–41, §243–250.*
11. **[D3 acceptance]** “Half game reload” unverifiable without save schema. *D3.*
12. **[D1 lifecycle]** `GameplayAPI.start/stop` not mapped to menu, start screen, victory. *D1.*
13. **[Responsive gap]** PLAN §5 absent — mobile layout/scroll risk alongside D2. *Not in plan.*
14. **[F metadata]** No pre-submit validation for title/description/“how to play” lengths. *F.*
15. **[H3 gaps]** Incomplete `update_all_texts()` vs H3 “all UI through i18n”. *H3.*

### P2 — Quality / plan hygiene

16. **[A unsolvable claims]** Full exhaustion impractical; expect timeout-heavy results. *A3.*
17. **[B deferral loophole]** “Отложено, не блокер” without severity matrix. *B.*
18. **[G over-scope]** G6, G7 for launch; defer to post-launch. *G.*
19. **[G under-scope]** G4 needs layout/step change; visual UX deferred. *G.*
20. **[H]** Manual lang buttons vs H2 auto-detect; TR linguistic QA beyond H4. *H.*
21. **[C4]** Optional card reskin — fine as optional, but competes with C1–C3 on calendar. *C.*
22. **[A cross-check]** Against `cursor.script` instead of rule modules. *A verification.*

---

**Bottom line:** The plan correctly identifies D as the longest path and A as valuable technical debt reduction, but **understates H and responsive work as moderation blockers**, **overstates parallel independence of G**, and **Track A’s verify-% pipeline will not be trustworthy** until rules include all slot/auto-move logic and win/auto-finish terminals match actual game behavior (including the `base_cards_count >= 27` bug). E must expand to cover camera debug UI and project-wide debug stripping before any “final build.”
