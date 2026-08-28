#!/usr/bin/env python3
"""Headless browser play-test for the js-web bundle.

Boots the real Defold HTML5 build in headless Chromium (SwiftShader WebGL),
drives it with real mouse/key events and captures everything the engine prints
(Lua `print`, runtime errors, asset failures) from the browser console.

    python3 tools/browser-test.py <bundle-dir> --scenario win

<bundle-dir> holds index.html, e.g. <bundle-output>/ShenzenSolitare.
Build it with:

    bob --platform js-web --archive --variant debug \
        --bundle-output <dir-OUTSIDE-build/> build bundle

Two engine facts this harness exists to respect:

1. **Input is sampled once per frame.** A playwright `click()` sends
   mousedown+mouseup in the same millisecond; the engine never observes the
   pressed->released transition and the game ignores it completely. Every press
   here is held for HOLD_MS, and drags step with a frame of slack between moves.

2. **Game coords come from the canvas rect, not from a constant.** The world is
   drawn fixed-FIT (min-scaled, centred), so on a non-16:9 canvas the CSS pixel
   of a given game point is not `y = 540 - game_y`. `_map` measures the live
   rect instead of assuming. Note this is NOT the space the engine hands to
   scripts -- `action.x/y` arrive stretched, which is the very bug the
   `hittest` scenario exists to catch (see main/Scripts/coords.lua).

3. **Column depth is not constant.** The flower and any exposed 2 auto-fly
   during the deal, so a column can start 4 deep instead of 5. Scenarios locate
   the exposed card by probing (`exposed_depth`) rather than assuming depth 4;
   assuming it makes a run silently grab nothing on some deals.

Exit code 0 = scenario finished with no engine error and every expectation met.
"""
import argparse
import functools
import http.server
import io
import json
import os
import re
import sys
import threading
import time

GAME_W, GAME_H = 960, 540   # virtual (authored) resolution

FRAME_MS = 17               # one frame at 60fps
HOLD_MS = 250               # press duration; must span several engine frames

# Slot centres in game coords, read from main/Levels/soliter.collection.
# G6: the grid was squeezed left (pitch 116 -> 104, first centre 65) to clear the
# right rail at x 868..946. Keep these in step with the collection -- a stale
# TABLEAU_X does not fail loudly, it just drags from the wrong pixel.
FREE_CELL = {1: (65, 457), 2: (169, 457), 3: (273, 457)}
TABLEAU_X = {1: 65, 2: 169, 3: 273, 4: 377, 5: 481, 6: 585, 7: 689, 8: 793}
TABLEAU_TOP_Y = 299         # depth 0; each further card is 35px lower
CARD_PITCH = 35             # only true while the column fits (config.stack_offset_y)
FLOWER_SLOT = (377, 457)    # G6: flower moved to column 4, dragon buttons to column 5
PLAY_BUTTON = (480, 232)
RESTART_BUTTON = (907, 56)   # G6: правый рельс, см. gui/ui.gui

BENIGN = (re.compile(r"^INFO:"), re.compile(r"Defold Engine \d"), re.compile(r"^Downloading"))
FATAL = (
    re.compile(r"ERROR:(SCRIPT|GAMEOBJECT|RESOURCE|GUI|RENDER|SOUND)"),
    re.compile(r"attempt to (index|call|compare|perform)"),
    re.compile(r"stack traceback"),
    re.compile(r"Assertion failed"),
)


def make_handler(coi):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def end_headers(self):
            if coi:
                # cross-origin isolation -> SharedArrayBuffer -> pthread build
                self.send_header("Cross-Origin-Opener-Policy", "same-origin")
                self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            self.send_header("Cache-Control", "no-store")
            super().end_headers()

        def log_message(self, *a):
            pass

    return Handler


def serve(directory, coi):
    handler = functools.partial(make_handler(coi), directory=directory)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, httpd.server_address[1]


def classify(text):
    for p in FATAL:
        if p.search(text):
            return "FATAL"
    for p in BENIGN:
        if p.search(text):
            return "info"
    return "log"


class Session:
    def __init__(self, page, out_dir):
        self.page = page
        self.out_dir = out_dir
        self.log = []
        self.shots = 0
        self.failures = []
        self.t0 = time.time()
        self.rect = None

    # ---------- observation ----------
    def note(self, kind, text):
        self.log.append({"t": round(time.time() - self.t0, 2), "kind": kind, "text": text})
        if kind != "info":
            print(f"  [{kind}] {text}", flush=True)

    def fail(self, why):
        self.failures.append(why)
        self.note("FAIL", why)

    def expect(self, cond, why):
        if not cond:
            self.fail(why)
        return cond

    def logs_matching(self, pattern):
        rx = re.compile(pattern)
        return [e for e in self.log if rx.search(e["text"])]

    def wait_for_log(self, pattern, timeout, label=""):
        """Block until a NEW console line matches, polling the live event log.

        The cursor matters. Scanning from index 0 (as this did until 2026-08-17)
        re-matches a line an earlier call already consumed, so a scenario that
        retries in a loop keeps reading the first attempt's verdict forever: a
        `freecell` run showed twelve deals each printing `SOLVED`, every one of
        them answered by attempt 1's stale `timeout`. The same flaw inverts just
        as easily — a stale `WIN ✓` handed back as a later attempt's verdict is
        a green run that proves nothing. Lines that arrive between calls are
        still seen; the cursor only skips what was already returned.

        The cursor is taken AFTER the note, not at the matched index: the note
        quotes the line it matched, so leaving it behind the cursor would make
        the harness match its own bookkeeping on the next call (measured).
        """
        rx = re.compile(pattern)
        deadline = time.time() + timeout
        seen = getattr(self, "_log_cursor", 0)
        while time.time() < deadline:
            while seen < len(self.log):
                if rx.search(self.log[seen]["text"]):
                    hit = self.log[seen]["text"]
                    self.note("match", f"{pattern} <- {hit[:120]}")
                    self._log_cursor = len(self.log)
                    return hit
                seen += 1
            self.page.wait_for_timeout(200)
        self.note("timeout", f"no line matched {pattern} in {timeout}s {label}")
        self._log_cursor = len(self.log)
        return None

    def shot(self, name):
        self.shots += 1
        path = os.path.join(self.out_dir, f"{self.shots:02d}-{name}.png")
        self.page.screenshot(path=path)
        self.note("shot", os.path.basename(path))
        return path

    def patch(self, x, y, half_w, half_h):
        """Сырые пиксели прямоугольника в игровых координатах.

        Нужен там, где утверждение звучит как «на экране стало ДРУГОЕ», а не
        «ярче/темнее»: текст на канвасе не прочитать из DOM, но два снимка
        одной и той же кнопки на разных языках обязаны различаться."""
        cx, cy = self._map(x, y)
        sx, sy = self._map(x + half_w, y + half_h)
        w, h = abs(sx - cx) * 2, abs(sy - cy) * 2
        clip = {"x": max(cx - w / 2, 0), "y": max(cy - h / 2, 0), "width": w, "height": h}
        return self.page.screenshot(clip=clip)

    def brightness(self, x, y, half=18):
        """Mean luminance of a small patch at a game coord.

        Card faces are near-white (~200+); an empty slot is the dark felt
        (~50). That gap is what lets a scenario assert 'a card is here' without
        a human looking at the screenshot."""
        from PIL import Image
        cx, cy = self._map(x, y)
        clip = {"x": max(cx - half, 0), "y": max(cy - half, 0), "width": half * 2, "height": half * 2}
        buf = self.page.screenshot(clip=clip)
        img = Image.open(io.BytesIO(buf)).convert("L")
        px = list(img.getdata())
        return sum(px) / len(px)

    # Card faces range from near-white to fairly dark art, so an absolute
    # threshold misjudges some deals. Everything is measured as a delta against
    # a felt sample taken live from a slot known to be empty.
    GAP = 50

    def expect_card_at(self, x, y, felt, label, patch=18):
        b = self.brightness(x, y, patch)
        self.note("pixel", f"{label} luminance={b:.0f} vs felt {felt:.0f}")
        return self.expect(b - felt > self.GAP,
                           f"{label}: nothing rendered there ({b:.0f} vs felt {felt:.0f})")

    def expect_empty_at(self, x, y, felt, label, patch=18):
        b = self.brightness(x, y, patch)
        self.note("pixel", f"{label} luminance={b:.0f} vs felt {felt:.0f}")
        return self.expect(b - felt <= self.GAP,
                           f"{label}: still covered by a card ({b:.0f} vs felt {felt:.0f})")

    def exposed_depth(self, col, felt, max_depth=4):
        """Depth of the column's exposed (draggable) card, or None if empty.

        Columns are dealt 5 deep but the flower and any exposed 2 fly off
        during the deal, so depth 4 is a guess, not a fact. Each card's own
        56px-below-centre sliver is covered by that card ALONE (the next card
        up ends 38px below its centre), so the deepest bright sliver is the
        exposed card.

        LIMIT: probing starts at `max_depth` (4 = the standard deal). A column
        DEEPER than that -- a tutorial deal, or a deal layout change -- makes
        this return 4 silently, and the scenario then grabs a buried card
        instead of the exposed one. Raise max_depth with the deal, do not
        assume the default still fits."""
        x = TABLEAU_X[col]
        for d in range(max_depth, -1, -1):
            y = TABLEAU_TOP_Y - d * CARD_PITCH - 56
            if self.brightness(x, y, 10) - felt > self.GAP:
                self.note("probe", f"column {col} exposed card at depth {d}")
                return d
        self.note("probe", f"column {col} reads as empty")
        return None

    # ---------- coordinate mapping ----------
    def measure(self):
        """Read the live canvas rect; game coords map through it, not through
        the authored constants. Letterboxing under fixed_fit_projection keeps
        the 960x540 aspect, so the virtual viewport is centred in the canvas."""
        r = self.page.evaluate(
            "() => { const c = document.getElementById('canvas'), b = c.getBoundingClientRect();"
            " return {x:b.x, y:b.y, w:b.width, h:b.height}; }"
        )
        scale = min(r["w"] / GAME_W, r["h"] / GAME_H)
        self.rect = {
            "scale": scale,
            "ox": r["x"] + (r["w"] - GAME_W * scale) / 2,
            "oy": r["y"] + (r["h"] - GAME_H * scale) / 2,
            "raw": r,
        }
        self.note("canvas", f"{r['w']}x{r['h']} scale={scale:.3f} "
                            f"letterbox=({self.rect['ox']:.0f},{self.rect['oy']:.0f})")
        return self.rect

    def _map(self, x, y):
        """Game coords (origin bottom-left) -> CSS pixels (origin top-left)."""
        if self.rect is None:
            self.measure()
        return (self.rect["ox"] + x * self.rect["scale"],
                self.rect["oy"] + (GAME_H - y) * self.rect["scale"])

    # ---------- input ----------
    def click_game(self, x, y, label="", hold=HOLD_MS):
        cx, cy = self._map(x, y)
        self.page.mouse.move(cx, cy)
        self.page.wait_for_timeout(FRAME_MS * 2)
        self.page.mouse.down()
        self.page.wait_for_timeout(hold)
        self.page.mouse.up()
        self.page.wait_for_timeout(FRAME_MS * 2)
        self.note("click", f"game({x},{y}) css({cx:.0f},{cy:.0f}) {label}")

    def drag_game(self, x1, y1, x2, y2, label="", steps=10):
        """Press, move across several FRAMES, release.

        The intermediate moves must be spaced in time: playwright's own
        `steps=` dispatches them back-to-back, which the engine samples as a
        single teleport and never as a drag."""
        sx, sy = self._map(x1, y1)
        ex, ey = self._map(x2, y2)
        self.page.mouse.move(sx, sy)
        self.page.wait_for_timeout(FRAME_MS * 2)
        self.page.mouse.down()
        self.page.wait_for_timeout(HOLD_MS)
        for i in range(1, steps + 1):
            self.page.mouse.move(sx + (ex - sx) * i / steps, sy + (ey - sy) * i / steps)
            self.page.wait_for_timeout(FRAME_MS * 2)
        self.page.wait_for_timeout(HOLD_MS)
        self.page.mouse.up()
        self.page.wait_for_timeout(FRAME_MS * 4)
        self.note("drag", f"({x1},{y1})->({x2},{y2}) {label}")

    def key(self, k, label="", hold=HOLD_MS):
        self.page.keyboard.down(k)
        self.page.wait_for_timeout(hold)
        self.page.keyboard.up(k)
        self.page.wait_for_timeout(FRAME_MS * 2)
        self.note("key", f"{k} {label}")

    # ---------- game helpers ----------
    def boot(self):
        self.wait(5, "engine boot")
        self.measure()
        self.expect(self.logs_matching(r"Defold Engine"), "engine never announced itself")

    def wait(self, seconds, label=""):
        self.page.wait_for_timeout(int(seconds * 1000))
        if label:
            self.note("wait", f"{seconds}s {label}")

    def press_play(self):
        self.click_game(*PLAY_BUTTON, label="PLAY")
        got = self.wait_for_log(r"I am MAIN SCRIPT", 20, "level proxy load")
        self.expect(got, "PLAY did not load the level (no main.script init)")
        self.wait(2.5, "deal settles")


# ================= scenarios =================

def scenario_boot(s):
    s.boot()
    s.shot("start-screen")


def scenario_hittest(s):
    """F3: is action.x/y already virtualized under fixed_fit_projection?

    Under a non-16:9 canvas an unprojection bug shifts every hit-test. Dragging
    the exposed bottom card of column 1 into free cell 1 is legal on any deal,
    so the outcome is a pure hit-test verdict: the card either lands in the
    cell (mapping correct) or nothing moves (mapping broken)."""
    s.boot()
    s.shot("start-screen")
    s.press_play()
    s.shot("dealt")

    cell = FREE_CELL[1]
    # Free cell 1 starts empty on every deal -> it is the felt reference.
    felt = s.brightness(*cell)
    s.note("pixel", f"felt reference (empty free cell 1) luminance={felt:.0f}")

    depth = s.exposed_depth(1, felt)
    if not s.expect(depth is not None, "column 1 is empty -- nothing to drag"):
        return
    src = (TABLEAU_X[1], TABLEAU_TOP_Y - depth * CARD_PITCH)

    s.drag_game(src[0], src[1], cell[0], cell[1], "col1 exposed card -> free cell 1")
    s.wait(1.5, "drop settles")
    s.shot("after-drag-to-free-cell")
    # The verdict: the card is in the cell AND has left the column. Both halves
    # matter -- a broken hit-test leaves the column untouched.
    s.expect_card_at(cell[0], cell[1], felt, "free cell 1 after the drag")
    # Sampling the card's own centre proves nothing (the card below is white
    # too), so sample the sliver only the removed card covered.
    s.expect_empty_at(src[0], src[1] - 56, felt, "column 1 bottom edge after the card left", patch=10)


def scenario_win(s):
    """End-to-end: the solver drives the REAL cards to a win.

    `debug_replay` (key R) plans from a live snapshot and then emits the same
    drop_success/move_stack messages a human drag emits, so this exercises the
    whole message flow -- auto-flights, dragon collection, auto-finish -- and
    prints its own verdict from foundation_top.

    Здесь же живёт единственная сквозная проверка D1 «победа гасит геймплей для
    платформы»: фальшивый SDK ставится тем же add_init_script, что в `yasdk`.
    Так решено после того, как ОБА внешних ревьюера показали одну и ту же дыру:
    в `yasdk` единственный `stop` приходит от `visibilitychange`, то есть изнутри
    JS, и мутация «мост глотает gameplay(false)» проходила и юниты, и стенд.
    Победа — единственный путь, где `gameplay(false)` уходит из Lua, а до победы
    доезжает только этот сценарий: дублировать сюда всю езду ради отдельного
    сценария дороже, чем три строки проверки в конце.
    """
    s.page.add_init_script(YA_STUB)
    s.page.goto(s.url)
    s.boot()
    s.press_play()
    s.shot("dealt")

    # REPLAY_BUDGET is small, so most deals are not solvable; SPACE re-deals.
    # ⚠ До правки D4 (2026-08-23) пересдачи внутри одной секунды давали ОДНУ И ТУ
    # ЖЕ колоду — то есть сценарий выбирал доски из узкой полосы и все его
    # прежние зелёные прогоны сделаны на ней. Первая же доска из-за её пределов
    # уронила проверку платформенного `stop` (блок M1 в plans/review-fixes.md).
    for attempt in range(1, 13):
        s.note("attempt", f"deal {attempt}")
        s.key("r", "debug_replay")
        verdict = s.wait_for_log(r"\[REPLAY\] (SOLVED|budget_exhausted|unsolvable|no_solution|planner desync)", 90)
        if verdict and "SOLVED" in verdict:
            n = re.search(r"\((\d+) directives\)", verdict)
            count = int(n.group(1)) if n else 400
            s.note("plan", f"{count} directives; ~{count * 0.6:.0f}s of driving")
            s.shot("replay-start")
            result = s.wait_for_log(r"\[REPLAY\] (WIN|DONE but NOT a win)", count * 0.6 + 120)
            s.shot("replay-end")
            s.expect(result, "replay never reported a verdict (stalled mid-line)")
            s.expect(result and "WIN" in result,
                     f"replay finished without a win: {result}")

            # D1: партия кончилась — платформе обязан уйти GameplayAPI.stop.
            # Вкладку тут никто не прятал, поэтому единственный источник stop —
            # цепочка ui.gui_script → gameplay_over → game_manager → мост.
            s.wait(1.5, "оверлей победы поднялся, сообщение дошло")
            calls = s.page.evaluate("window.__yaStub.calls.join(',')")
            s.note("ya", f"цепочка вызовов платформы за партию: {calls}")
            s.expect(calls.endswith("stop"),
                     f"победа не погасила геймплей для платформы: {calls}")
            s.expect(calls.startswith("ready,start"),
                     f"порядок вызовов за партию нарушен: {calls}")
            return
        s.key("Space", "new deal")  # playwright key name, not "space"
        s.wait(3, "re-deal")
    s.fail("no deal solvable within budget after 12 attempts")


def scenario_stuck(s):
    """Drag-machine smoke test: no card is ever stranded or teleported.

    Drops a card on empty felt, taps a free cell right after, then fires a
    second mousedown with the first still held. Nothing may end up in the free
    cell, in mid-air, or missing from a column.

    HONEST SCOPE -- this does NOT verify the A1/A2 fixes, and both claims were
    checked by mutation rather than assumed:

    * A2 (press arriving while a drag is live): a second CDP `mousePressed`
      with no release in between produces no new pressed-transition -- the
      engine already has the button down -- so the guard is never reached. A
      build with the guard disabled passes this scenario identically.
    * A1 (clean_cursor after a single-card miss): a build with it removed also
      passes, because the A2 guard cleans the stale drag on the following
      press and masks its absence. Discriminating A1 needs both removed.

    Reproducing A2 faithfully needs a mouseup the canvas never sees (release
    outside the browser window), which CDP cannot synthesise. Treat these two
    as still open on the play-test checklist."""
    s.boot()
    s.press_play()
    s.shot("dealt")

    cell = FREE_CELL[1]
    felt = s.brightness(*cell)
    s.note("pixel", f"felt reference luminance={felt:.0f}")
    d1, d2 = s.exposed_depth(1, felt), s.exposed_depth(2, felt)
    if not s.expect(d1 is not None and d2 is not None, "a probed column came up empty"):
        return
    col1 = (TABLEAU_X[1], TABLEAU_TOP_Y - d1 * CARD_PITCH)
    col2 = (TABLEAU_X[2], TABLEAU_TOP_Y - d2 * CARD_PITCH)
    # felt with no slot under it: left of column 1 and below every card
    VOID = (25, 30)

    # ---- A1 ----
    # A column's card centre is useless as evidence -- the card underneath is
    # white too. Only the exposed card's own sliver tells "still there" from
    # "one card shorter".
    def col_intact(col, label):
        return s.expect_card_at(col[0], col[1] - 56, felt, label, patch=10)

    s.drag_game(col1[0], col1[1], VOID[0], VOID[1], "col1 top -> empty felt (miss)")
    s.wait(1.0, "card flies home")
    col_intact(col1, "A1 card returned to column 1")
    s.click_game(cell[0], cell[1], "tap free cell 1 right after the miss")
    s.wait(1.0)
    s.shot("a1-after-miss-and-tap")
    s.expect_empty_at(cell[0], cell[1], felt, "A1 free cell after tapping it post-miss")

    # ---- A2 ----
    # Two mousedowns with no mouseup between them: exactly the state the guard
    # is written for. Playwright refuses a second down(), so drive CDP directly.
    cdp = s.page.context.new_cdp_session(s.page)

    def raw(kind, gx, gy):
        cx, cy = s._map(gx, gy)
        cdp.send("Input.dispatchMouseEvent", {
            "type": kind, "x": cx, "y": cy, "button": "left",
            "buttons": 1 if kind != "mouseReleased" else 0, "clickCount": 1})
        s.page.wait_for_timeout(FRAME_MS * 4)

    raw("mousePressed", *col1)
    raw("mouseMoved", *VOID)             # drag it out over empty felt
    s.page.wait_for_timeout(HOLD_MS)
    s.note("input", "second press with the first drag still live (no mouseup)")
    raw("mousePressed", *col2)           # <- the A2 path
    s.page.wait_for_timeout(HOLD_MS)
    raw("mouseReleased", *col2)
    s.wait(1.5, "everything settles")
    s.shot("a2-after-double-press")

    # Both columns must still be full-depth: without the guard the first card
    # stays attached to the cursor, the second press steals the drag, and the
    # first card is stranded wherever it was last dragged to.
    col_intact(col1, "A2 column 1 got its stuck card back")
    col_intact(col2, "A2 column 2 intact after the interrupting press")
    s.expect_empty_at(VOID[0], VOID[1], felt, "A2 no card stranded on the felt")
    s.expect_empty_at(cell[0], cell[1], felt, "A2 free cell stayed empty")


def scenario_freecell(s):
    """C4: park a card in a free cell, THEN let the solver drive.

    `scenario_win` cannot see this fix: it presses R on a fresh deal where every
    cell is empty, so the honest snapshot and the old hardcoded `{{},{},{}}` are
    the same board. Here one card is physically sitting in a cell before R.
    Without C4 that card is in no mirror at all -- it left tableau_stacks and the
    snapshot claims the cells are empty -- so the solver plans a 26-card board and
    the run ends 'DONE but NOT a win'. Verified A/B against exactly that build,
    not assumed.

    ⚠ Сценарий перебирает раздачи клавишей Space. До правки D4 (2026-08-23)
    пересдачи внутри одной секунды давали ОДНУ И ТУ ЖЕ колоду, поэтому «N
    попыток» означало заметно меньше N разных досок. Сейчас сидирование одно на
    запуск и пересдачи независимы; прежние прогоны читать как выборку меньше
    заявленной."""
    s.boot()
    s.press_play()
    s.shot("dealt")

    cell = FREE_CELL[1]
    for attempt in range(1, 13):
        s.note("attempt", f"deal {attempt}")
        felt = s.brightness(*cell)
        d1 = s.exposed_depth(1, felt)
        if d1 is None:
            s.key("Space", "column 1 empty — re-deal"); s.wait(3); continue
        s.drag_game(TABLEAU_X[1], TABLEAU_TOP_Y - d1 * CARD_PITCH, cell[0], cell[1],
                    "column 1 top -> free cell 1")
        s.wait(1.5, "card lands in the cell")
        if not s.expect_card_at(cell[0], cell[1], felt, "parked card in free cell 1"):
            return
        s.shot("parked")

        s.key("r", "debug_replay")
        verdict = s.wait_for_log(
            r"\[REPLAY\] (SOLVED|timeout|budget_exhausted|unsolvable|no_solution|planner desync|снапшот)", 90)
        if verdict and "SOLVED" in verdict:
            n = re.search(r"\((\d+) directives\)", verdict)
            count = int(n.group(1)) if n else 400
            s.note("plan", f"{count} directives with a card parked in cell 1")
            result = s.wait_for_log(r"\[REPLAY\] (WIN|DONE but NOT a win)", count * 0.6 + 120)
            s.shot("replay-end")
            s.expect(result, "replay never reported a verdict (stalled mid-line)")
            s.expect(result and "WIN" in result,
                     f"replay from a board with a parked card did not win: {result}")
            return
        s.key("Space", "new deal")
        s.wait(3, "re-deal")
    s.fail("no deal solvable within budget after 12 attempts")



def scenario_focus(s):
    """D2: требования Я.Игр к HTML5-обёртке — жесты, меню, звук на потере фокуса.

    Проверяем не «строка есть в шаблоне», а ВЫЧИСЛЕННЫЙ браузером стиль и
    реальную реакцию на событие: шаблон можно поправить и не собрать, а можно
    собрать и получить перекрытое правило.
    """
    s.boot()

    style = s.page.evaluate(
        "() => ({"
        " body: getComputedStyle(document.body).overscrollBehaviorY,"
        " html: getComputedStyle(document.documentElement).overscrollBehaviorY,"
        " canvas: getComputedStyle(document.getElementById('canvas')).touchAction"
        "})")
    s.note("style", f"overscroll html={style['html']} body={style['body']}, canvas touch-action={style['canvas']}")
    s.expect(style["html"] == "none" and style["body"] == "none",
             f"страница всё ещё пружинит/прокручивается: {style}")
    s.expect(style["canvas"] == "none",
             f"жесты над канвасом не отданы игре: touch-action={style['canvas']}")

    # По канвасу меню давит и сам движок, поэтому проверяем страницу целиком:
    # долгий тап на мобиле легко попадает мимо канваса (леттербокс-поля).
    prevented = s.page.evaluate(
        "() => {const out = {};"
        " for (const id of ['canvas', 'app-container']) {"
        "   const e = new MouseEvent('contextmenu', {bubbles: true, cancelable: true});"
        "   document.getElementById(id).dispatchEvent(e); out[id] = e.defaultPrevented; }"
        " const b = new MouseEvent('contextmenu', {bubbles: true, cancelable: true});"
        " document.body.dispatchEvent(b); out.body = b.defaultPrevented; return out;}")
    s.note("menu", f"contextmenu подавлен: {prevented}")
    s.expect(all(prevented.values()),
             f"контекстное меню не подавлено — долгий тап откроет его: {prevented}")

    s.press_play()
    s.wait(2, "звук успел завестись")

    # Видимость подменяем на самой странице: headless-браузер вкладки не
    # переключает, а сторож в шаблоне читает именно document.hidden.
    def visibility(hidden):
        s.page.evaluate(
            "(h) => { Object.defineProperty(document, 'hidden', {value: h, configurable: true});"
            " Object.defineProperty(document, 'visibilityState', {value: h ? 'hidden' : 'visible', configurable: true});"
            " document.dispatchEvent(new Event('visibilitychange')); }", hidden)

    # Читаем ИЗМЕРЕННОЕ состояние контекстов (states=...), а не строку намерения.
    # Ревью блока H: прежняя проверка ловила «[AUDIO] suspended», а эта строка
    # печаталась от флага muted — вырежи из сторожа suspend()/resume() целиком,
    # и сценарий оставался зелёным. Теперь такая мутация его роняет.
    def audio_states(line):
        # wait_for_log отдаёт строку целиком, состояния достаём отдельно.
        m = re.search(r"states=([a-z,]+)", line or "")
        return m.group(1).split(",") if m else []

    visibility(True)
    line = s.wait_for_log(r"\[AUDIO\] suspended ctx=[1-9][0-9]* states=", 10, "focus lost")
    st = audio_states(line)
    s.expect(st and all(x == "suspended" for x in st),
             f"вкладка ушла в фон, а контекст не приглушён: {line}")
    visibility(False)
    line = s.wait_for_log(r"\[AUDIO\] resumed ctx=[1-9][0-9]* states=", 10, "focus back")
    st = audio_states(line)
    s.expect(st and all(x == "running" for x in st),
             f"вкладка вернулась, а звук так и остался выключен: {line}")

    # Быстрый разворот: уйти и вернуться, не дав suspend() доехать. suspend и
    # resume асинхронны, и сторож, который смотрит только на c.state, здесь
    # разъезжается — resume не зовётся (state ещё "running"), а suspend доезжает
    # уже после. Найдено ревью блока I. Вкладка видима — звук обязан играть.
    # Оба события — в ОДНОМ evaluate, синхронно: между двумя отдельными
    # page.evaluate проходит несколько миллисекунд, и suspend() успевает
    # доехать, то есть окно закрывается само (замерено: A/B на стороже без
    # перепроверки такой разворот не ловил).
    s.page.evaluate(
        "() => { const set = (h) => {"
        "   Object.defineProperty(document, 'hidden', {value: h, configurable: true});"
        "   Object.defineProperty(document, 'visibilityState', {value: h ? 'hidden' : 'visible', configurable: true});"
        "   document.dispatchEvent(new Event('visibilitychange')); };"
        " set(true); set(false); }")
    s.wait(3, "промисы аудио осели")
    tail = [e["text"] for e in s.logs_matching(r"\[AUDIO\] .* ctx=[1-9][0-9]* states=")]
    last = tail[-1] if tail else ""
    st = audio_states(last)
    s.note("audio", f"после быстрого разворота: {last}")
    s.expect(st and all(x == "running" for x in st),
             f"после быстрого ухода-возврата звук остался глухим: {last}")



def scenario_restartrace(s):
    """(г) из ревью блока H: show() шлёт unload и тут же async_load одному и
    тому же collectionproxy, не дожидаясь proxy_unloaded.

    Сценарий давит именно в окно: RESTART нажимается дважды подряд без пауз, а
    третий раз — посреди загрузки уровня. Судим по столу и по ошибкам движка:
    после того как пыль осела, стол обязан быть разложен, а в логе не должно
    быть жалоб прокси. Пустой стол или ошибка загрузки — это и есть гонка.
    """
    s.boot()
    s.press_play()

    felt = s.brightness(*FREE_CELL[1])   # пустая ячейка = эталон сукна
    s.note("felt", f"эталон сукна {felt:.0f}")

    # ЗАМЕР, без которого сценарий проверял бы не то: от клика RESTART до
    # «I am MAIN SCRIPT» проходит 60-80 мс, а обычный click_game держит кнопку
    # HOLD_MS=250 мс, то есть нажатия идут раз в ~270 мс. Очередь таких кликов
    # в окно загрузки НЕ ПОПАДАЕТ ни разу — она проверяет восемь честных
    # последовательных рестартов, а не гонку. Поэтому здесь нажатие короткое:
    # 40 мс — это ~2.4 кадра при 60fps, движок его видит, а интервал (~50 мс)
    # меньше окна загрузки, и клики ложатся внутрь него.
    def fast_click(label):
        cx, cy = s._map(*RESTART_BUTTON)
        s.page.mouse.move(cx, cy)
        s.page.mouse.down()
        s.page.wait_for_timeout(40)
        s.page.mouse.up()
        s.note("click", f"fast RESTART {label}")

    board = (480, 300, 380, 200)
    for label, times in (("медленный", 2), ("в окно загрузки", 8)):
        loads_before = len(s.logs_matching(r"I am MAIN SCRIPT"))
        before = s.patch(*board)
        for n in range(times):
            if label == "медленный":
                s.click_game(*RESTART_BUTTON, label=f"RESTART {n + 1} ({label})")
            else:
                fast_click(f"{n + 1}")
        s.wait(5, f"{label} рестарт осел")
        loads = len(s.logs_matching(r"I am MAIN SCRIPT")) - loads_before
        s.note("loads", f"{label}: нажатий {times}, загрузок уровня {loads}")
        # Ноль загрузок означало бы, что короткое нажатие движок не увидел —
        # тогда «гонки нет» доказывало бы только то, что мы не нажимали.
        s.expect(loads > 0, f"{label}: ни одной загрузки уровня — нажатия не дошли до движка")

        if label != "медленный":
            # Ревью блока J (grok-4.5): «загрузка была» не то же самое, что
            # «нажатия перекрыли загрузку». Требуем ровно то, ради чего сценарий
            # существует: каждое нажатие дошло, и интервал между нажатиями
            # МЕНЬШЕ задержки загрузки (замер: 60-80 мс). Тогда очередь по
            # построению ложится внутрь окна, а не рядом с ним.
            s.expect(loads >= times,
                     f"{label}: нажатий {times}, а загрузок {loads} — часть кликов движок проглотил, "
                     f"перекрытия не было")
            clicks = [e["t"] for e in s.log if "fast RESTART" in e["text"]][-times:]
            gaps = [round(b - a, 3) for a, b in zip(clicks, clicks[1:])]
            lat = [e["t"] for e in s.log if "DEBUG:SCRIPT: I am MAIN SCRIPT" in e["text"]][-loads:]
            worst = max(gaps) if gaps else 0
            s.note("overlap", f"интервал между нажатиями {gaps}, загрузок {len(lat)}")
            s.expect(worst < 0.15,
                     f"{label}: нажатия разъехались на {worst:.3f} с — это больше окна загрузки, "
                     f"очередь била мимо гонки")

        # enumerate(dict) отдаёт КЛЮЧИ, а не значения: сюда уезжали x = 1..8
        # вместо 65..793, то есть восемь замеров одной и той же точки у левого
        # края. Поймано ревью блока I. Оракул был бессмысленным, а «8 из 8» в
        # логе — самообманом.
        dealt = sum(1 for x in TABLEAU_X.values()
                    if s.brightness(x, TABLEAU_TOP_Y) - felt > s.GAP)
        s.note("board", f"{label}: колонок с картой {dealt} из {len(TABLEAU_X)}")
        s.expect(dealt == len(TABLEAU_X),
                 f"{label} рестарт: стол разложен не полностью ({dealt} из {len(TABLEAU_X)})")
        # «Восемь ярких верхушек» одинаково верно и для НОВОЙ раздачи, и для
        # старой, оставшейся на экране (ревью блока I). Поэтому ещё и требуем,
        # чтобы стол СТАЛ ДРУГИМ: рестарт тасует заново, две одинаковые раздачи
        # подряд практически невозможны.
        after = s.patch(*board)
        s.expect(after != before,
                 f"{label} рестарт: стол не изменился — старая раздача осталась на экране")

    bad = [e["text"] for e in s.log
           if re.search(r"(?i)proxy", e["text"]) and re.search(r"(?i)error|fail|assert", e["text"])]
    s.expect(not bad, f"движок пожаловался на прокси: {bad[:3]}")


def scenario_debugkeys(s):
    """Блок D: dev-клавиши S / R / Space живут ровно в debug-сборке.

    Сценарий двусторонний и сам определяет, чего ждать, по строке варианта из
    game_manager.init. Гонять его надо на ОБОИХ бандлах: на release он ловит
    клавиши, уехавшие в магазин, на debug — что мы не сломали собственный стенд
    (census и freecell перебирают раздачи клавишей Space, win решает партию R).
    Односторонняя проверка тут ничего не стоит: «клавиша молчит» одинаково верно
    и для правильно закрытого флага, и для сломанного ввода.
    """
    # Релизный движок Defold не печатает в консоль ВООБЩЕ (замерено: в
    # release-бандле нет ни «Defold Engine», ни наших print). Поэтому у
    # сценария две руки: в debug читаем логи, в release — пиксели. Ждать логов
    # от релиза бессмысленно, а «логов нет, значит клавиши мертвы» — ложная
    # зелень: логов нет и у живых клавиш.
    s.wait(6, "движок грузится")
    s.measure()
    variant = s.wait_for_log(r"\[DEBUG\] dev-клавиши: (on|off)", 5, "вариант сборки")
    dev = bool(variant and variant.strip().endswith("on"))
    s.note("variant", f"логи: {'есть' if variant else 'молчат (release)'} → режим {'debug' if dev else 'release'}")

    if dev:
        s.expect(s.logs_matching(r"Defold Engine"), "engine never announced itself")
        s.press_play()
        deals_before = len(s.logs_matching(r"I am MAIN SCRIPT"))

        s.key("s", "solver")
        s.wait(2, "солвер успел бы отчитаться")
        solver_spoke = bool(s.logs_matching(r"\[SOLVER\]"))
        s.key("r", "replay")
        s.wait(2, "реплей успел бы отчитаться")
        replay_spoke = bool(s.logs_matching(r"\[REPLAY\]"))
        s.key("Space", "restart")
        s.wait(3, "уровень успел бы перезагрузиться")
        dealt_again = len(s.logs_matching(r"I am MAIN SCRIPT")) > deals_before

        s.note("keys", f"S→{solver_spoke} R→{replay_spoke} Space→{dealt_again}")
        s.expect(solver_spoke, "debug-сборка: S не запустил солвер — стенд остался без инструмента")
        # R считался, но вердикт по нему не ставился (ревью блока I): сломанный
        # debug_replay оставлял сценарий зелёным, а от R зависят win/census/freecell.
        s.expect(replay_spoke, "debug-сборка: R не отдал партию реплею — сценарий win работать не будет")
        s.expect(dealt_again, "debug-сборка: Space не пересдал — census/freecell работать не будут")
        return

    # ---- release: судим по столу, а не по логам ----
    board = (480, 300, 380, 200)   # весь игровой стол целиком
    before_play = s.patch(*board)
    s.click_game(*PLAY_BUTTON, label="PLAY")
    s.wait(4, "раздача осела")
    dealt = s.patch(*board)
    # Контроль: если PLAY не сработал, дальше «ничего не изменилось» доказывало
    # бы только то, что мы смотрим на пустой экран.
    s.expect(dealt != before_play, "release: PLAY не разложил стол — сравнивать нечего")

    s.wait(3, "стол стоит без ввода")
    idle = s.patch(*board)
    s.expect(idle == dealt, "release: стол меняется сам по себе — пиксельная проверка тут не судья")

    # ⚠ ГРАНИЦА МЕТОДА, уточнена ревью блока I. В release движок молчит, поэтому
    # судить можно только по столу — и по столу видно не всё:
    #   S  — не двигает карты вообще (только считает и печатает), значит живую S
    #        от мёртвой здесь не отличить НИКОГДА;
    #   R  — двигает, но при неразрешимой в бюджете раздаче debug_replay выходит
    #        сразу, ничего не тронув. То есть «R мёртв» иногда ложная зелень
    #        (бюджет реплея 40k; на сидах 1..40 около 12% раздач не решаются).
    #   Space — пересдаёт всегда. Это и есть настоящий различитель флага в
    #        release; мутация M.enabled=true ловится именно им (и, когда повезёт
    #        с раздачей, ещё и R).
    # Все три проверки оставлены: лишняя не мешает, а Space держит вердикт.
    s.key("s", "solver")
    s.wait(3, "солвер успел бы отыграть")
    after_s = s.patch(*board)
    s.expect(after_s == idle, "release: клавиша S всё ещё что-то делает со столом")

    s.key("r", "replay")
    s.wait(4, "реплей успел бы повести карты")
    after_r = s.patch(*board)
    s.expect(after_r == idle, "release: клавиша R всё ещё отдаёт партию автоигроку")

    s.key("Space", "restart")
    s.wait(4, "пересдача успела бы случиться")
    after_space = s.patch(*board)
    s.expect(after_space == idle, "release: пробел всё ещё перезапускает партию")
    s.note("keys", "release: S/R/Space стол не тронули")


def scenario_audiobg(s):
    """D2: игра, загруженная В ФОНЕ, не должна звучать.

    Отдельный сценарий, потому что проверяемый момент — СОЗДАНИЕ контекста, а не
    реакция на событие. Движок создаёт AudioContext асинхронно внутри
    EngineLoader.load; если к этому времени вкладка уже без фокуса, сторож обязан
    приглушить контекст сразу, а не ждать следующего blur/visibilitychange.
    Найдено ревью блока H (обе модели) — до правки в конструкторе не было apply().

    Фокус подменяем ДО первого скрипта страницы (add_init_script), иначе движок
    успеет создать контекст раньше подмены и замер уедет.
    """
    s.page.add_init_script(
        "Object.defineProperty(document, 'hasFocus', {value: function () { return false; },"
        " configurable: true});")
    s.page.goto(s.url)
    s.boot()
    s.press_play()

    # Смотрим ВЕСЬ лог, а не «следующую новую строку»: сторож печатает свой
    # вердикт в момент создания контекста, то есть ещё до press_play, и курсор
    # wait_for_log эту строку уже прошёл бы (замерено: строка есть, проверка
    # мимо). ctx=0 — событие фокуса до рождения контекста, оно не в счёт.
    #
    # ⚠ Что здесь на самом деле различитель (уточнено ревью блока I). Chromium
    # часто рождает AudioContext уже suspended из-за autoplay-политики, поэтому
    # states=suspended сам по себе НИЧЕГО не доказывает — он был бы таким и без
    # сторожа. Доказывает первая проверка: сторож вообще ОТЧИТАЛСЯ о живом
    # контексте, а отчитаться он может только из apply(), которого до этой
    # правки в конструкторе не было. Замерено мутацией: убрать apply() из
    # Patched → «сторож ни разу не отчитался», FAIL.
    hits = [e["text"] for e in s.logs_matching(r"\[AUDIO\] .* ctx=[1-9][0-9]* states=")]
    s.note("audio", f"строк сторожа с живым контекстом: {len(hits)}; последняя: {hits[-1] if hits else '—'}")
    s.expect(bool(hits), "сторож ни разу не отчитался о живом контексте — apply() при создании не сработал")
    bad = [h for h in hits if not all(x == "suspended" for x in re.search(r"states=([a-z,]+)", h).group(1).split(","))]
    s.expect(not bad, f"контекст создан без фокуса и остался звучать: {bad}")


def scenario_i18n(s):
    """H2/H3: язык приходит из ?lang= (так его задают Я.Игры) и реально доезжает
    до подписей на экране.

    Проверка не «в логе написано ru»: логи врут дёшево. Снимаем одну и ту же
    кнопку рельса на двух языках и требуем, чтобы картинка отличалась — если
    подпись осталась английским хардкодом из ui.gui, снимки совпадут побайтно.
    """
    base = s.url.split("?")[0]
    shots = {}
    for lang in ("en", "ru"):
        s.page.goto(f"{base}?lang={lang}")
        s.boot()
        got = s.wait_for_log(r"\[I18N\] язык: (\w+)", 20, f"lang={lang}")
        s.expect(got and got.strip().endswith(lang), f"движок не переключился на {lang}: {got}")
        s.press_play()
        s.wait(2, "раздача осела")
        s.shot(f"rail-{lang}")
        shots[lang] = s.patch(907, 56, 35, 28)   # кнопка RESTART в рельсе

    s.expect(shots["en"] != shots["ru"],
             "подпись кнопки не изменилась при смене языка — текст остался хардкодом в ui.gui")
    from PIL import Image
    for lang, buf in shots.items():
        img = Image.open(io.BytesIO(buf)).convert("L")
        px = list(img.getdata())
        spread = max(px) - min(px)
        s.note("label", f"{lang}: контраст подписи {spread}")
        s.expect(spread > 40, f"на кнопке {lang} не видно текста (контраст {spread}) — тофу или пусто")


def scenario_census(s):
    """C5: press R on a board whose FLOWER HAS ALREADY LANDED.

    Neither `win` nor `freecell` discriminates the C5 census: they press R on a
    just-dealt board, and on most deals the flower is still buried in a column,
    where the snapshot has always counted it. The interesting board is the one
    where the flower auto-flew during the deal -- then it is in no column, and
    only the flower_slot->main mirror keeps it in the snapshot. Measured, not
    assumed: a build with that mirror removed and this scenario refuses with
    'перепись не сошлась: карт f_flower 0 вместо 1', while the same build passes
    `freecell` whenever the deal happens to bury the flower.

    The felt baseline comes from free cell 3, which is empty on every deal."""
    s.boot()
    s.press_play()
    s.shot("dealt")

    felt = s.brightness(*FREE_CELL[3])
    # ⚠ Арифметика ниже считает раздачи НЕЗАВИСИМЫМИ. До правки D4 (2026-08-23)
    # они таковыми не были: `shuffle_deck` пересидировал генератор от `os.time()`
    # на каждую раздачу, и пересдачи внутри одной секунды давали ОДНУ И ТУ ЖЕ
    # колоду (замер: 13 раздач → 3 различных). Значит и здесь, и в `freecell`,
    # и в `stuck` эффективная выборка была в разы меньше номинальной, а
    # приведённые ниже измеренные проценты получены на той же сломанной выборке.
    # Сейчас сидирование одно на запуск (`game_manager.init`), пересдачи
    # независимы, и числа стали честными — переизмерять их специально не стали.
    #
    # Лотерея: цветок улетает во время раздачи, только если оказался верхним в
    # своей колонке — примерно 8 шансов из 40, то есть ~20% на раздачу. При 12
    # попытках сценарий врёт «провал» в 0.8^12 ≈ 7% прогонов, и это измерено:
    # один прогон дал 12 раздач подряд с закопанным цветком, а два следующих на
    # ТОЙ ЖЕ сборке прошли. 25 попыток опускают ложный провал до ~0.4%.
    ATTEMPTS = 25
    landed = 0
    for attempt in range(1, ATTEMPTS + 1):
        s.note("attempt", f"deal {attempt}")
        b = s.brightness(*FLOWER_SLOT)
        s.note("pixel", f"flower slot luminance={b:.0f} vs felt {felt:.0f}")
        if b - felt <= s.GAP:
            s.key("Space", "flower still buried in a column -- re-deal")
            s.wait(3)
            continue
        landed += 1
        s.shot("flower-landed")

        s.key("r", "debug_replay")
        verdict = s.wait_for_log(
            r"\[REPLAY\] (SOLVED|timeout|budget_exhausted|unsolvable|no_solution|planner desync|снапшот)", 90)
        if verdict and "снапшот" in verdict:
            s.fail(f"an honest board was refused after the flower landed: {verdict}")
            return
        if verdict and "SOLVED" in verdict:
            n = re.search(r"\((\d+) directives\)", verdict)
            count = int(n.group(1)) if n else 400
            s.note("plan", f"{count} directives from a board with the flower already down")
            result = s.wait_for_log(r"\[REPLAY\] (WIN|DONE but NOT a win)", count * 0.6 + 120)
            s.shot("replay-end")
            s.expect(result, "replay never reported a verdict (stalled mid-line)")
            s.expect(result and "WIN" in result,
                     f"replay from a flower-already-down board did not win: {result}")
            return
        s.key("Space", "new deal")
        s.wait(3, "re-deal")
    s.fail(f"за {ATTEMPTS} раздач цветок приземлился {landed} раз, и ни одна такая "
           f"партия не решилась в бюджете — если landed==0, это лотерея раздачи, "
           f"а не регрессия")


# Фальшивый SDK платформы. Промис разрешается НАМЕРЕННО ПОЗДНО: без задержки он
# успевает ответить раньше, чем ui.gui_script нарисует подписи в init, и сценарий
# зеленел бы даже без перекраски по language_ready (замерено — так и было).
# 20 с заведомо больше, чем занимают загрузка движка и раздача, поэтому окно
# «SDK ещё думает, а игрок уже играет» гарантированно существует.
YA_STUB_DELAY_MS = 20000
YA_STUB = """
window.__yaStub = { calls: [], lang: "ru" };
window.YaGames = {
    init: function () {
        return new Promise(function (resolve) {
            setTimeout(function () {
                resolve({
                    environment: { i18n: { lang: window.__yaStub.lang } },
                    features: {
                        LoadingAPI: { ready: function () { window.__yaStub.calls.push("ready"); } },
                        GameplayAPI: {
                            start: function () { window.__yaStub.calls.push("start"); },
                            stop: function () { window.__yaStub.calls.push("stop"); }
                        }
                    }
                });
            }, %d);
        });
    }
};
""" % YA_STUB_DELAY_MS


def scenario_yasdk(s):
    """D1: мост к SDK Яндекс.Игр под фальшивым YaGames.

    Настоящую песочницу платформы локально не поднять, поэтому здесь проверяется
    ровно то, что от игры зависит: КАКИЕ вызовы и в КАКОМ ПОРЯДКЕ уходят в SDK и
    доезжает ли язык игрока до подписей. Прогон в песочнице Я.Игр этим НЕ
    заменяется и остаётся открытым пунктом D1.

    Фальшивку ставим через add_init_script — она обязана существовать до первого
    скрипта страницы, иначе мост в шаблоне не увидит YaGames и уйдёт в "absent"
    (та же ошибка, что уже ловилась на гонке звука: page.evaluate поздно). Сам
    /sdk.js при этом честно отдаёт 404 — заодно видно, что 404 не фатален.

    Вердикты берутся из ПИКСЕЛЕЙ и из счётчика вызовов в самой фальшивке, а не
    из консоли движка: в release-сборке движок в консоль молчит, и сценарий,
    завязанный на его print, там был бы слепым. Поэтому гонять можно на обоих
    бандлах.

    Порядок частей важен: снимок БЕЗ SDK снимается первым, потому что
    add_init_script остаётся на все последующие переходы страницы.
    """
    base = s.url.split("?")[0]
    RAIL = (907, 56, 35, 28)   # кнопка RESTART в рельсе
    BOARD = (480, 300, 380, 200)   # весь игровой стол

    # Ни boot(), ни press_play() тут не годятся: обе ждут print движка, а
    # release молчит в консоль. Ждём время и судим по столу.
    def boot():
        s.wait(6, "движок грузится")
        s.measure()

    def play(label):
        before = s.patch(*BOARD)
        s.click_game(*PLAY_BUTTON, label="PLAY")
        s.wait(4, "раздача осела")
        s.expect(s.patch(*BOARD) != before, f"{label}: PLAY не разложил стол")

    # --- 1. Без SDK, ?lang=en: как игра выглядит без платформы.
    s.page.goto(f"{base}?lang=en")
    boot()
    play("без SDK")
    en_shot = s.patch(*RAIL)
    s.shot("rail-no-sdk")

    # --- 2. С SDK. Язык платформы ru, а в адресе по-прежнему ?lang=en: если
    # приоритет перепутан, подпись останется английской. SDK отвечает нарочно
    # медленно, поэтому PLAY успевает случиться РАНЬШЕ ответа — и это же
    # проверяет порядок вызовов для платформы.
    s.page.add_init_script(YA_STUB)
    s.page.goto(f"{base}?lang=en")
    boot()

    def calls():
        return s.page.evaluate("window.__yaStub.calls.join(',')")

    def trace():
        return s.page.evaluate("window.__ya ? window.__ya.trace() : 'нет моста'")

    play("SDK ещё думает")
    s.expect(calls() == "", f"SDK ещё молчит, а платформе уже что-то ушло: {calls()}")
    pending_shot = s.patch(*RAIL)
    s.expect(pending_shot == en_shot,
             "пока SDK не ответил, подпись обязана остаться прежней (en из ?lang=)")

    s.wait(15, "SDK наконец ответил")
    s.note("ya", f"мост: {trace()}")
    # Порядок для платформы: сначала «игра загрузилась», потом «начался геймплей».
    # Дыру нашёл сам сценарий, когда SDK стал медленным: уходило start,ready.
    s.expect(calls() == "ready,start",
             f"порядок для платформы нарушен, ожидали ready,start: {calls()}")

    ru_shot = s.patch(*RAIL)
    s.shot("rail-sdk-ru")
    s.expect(en_shot != ru_shot,
             "подпись кнопки одинакова с ?lang=en и с языком SDK ru — либо приоритет "
             "языка не работает, либо подписи не перекрасили по language_ready")

    # --- 3. Вкладка ушла в фон → геймплей остановлен, вернулась → возобновлён.
    s.page.evaluate(
        "Object.defineProperty(document, 'hidden', {value: true, configurable: true});"
        "document.dispatchEvent(new Event('visibilitychange'));")
    s.wait(0.5, "фон")
    s.expect(calls() == "ready,start,stop",
             f"уход вкладки в фон не остановил геймплей: {calls()}")

    s.page.evaluate(
        "Object.defineProperty(document, 'hidden', {value: false, configurable: true});"
        "document.dispatchEvent(new Event('visibilitychange'));")
    s.wait(0.5, "возврат")
    s.expect(calls() == "ready,start,stop,start",
             f"возврат вкладки не возобновил геймплей: {calls()}")

    # --- 4. Повторный старт уровня не шлёт второй start подряд.
    s.click_game(*RESTART_BUTTON, label="RESTART")
    s.wait(2, "уровень перезагрузился")
    s.expect(calls() == "ready,start,stop,start",
             f"рестарт внутри партии продублировал start: {calls()}")
    s.note("ya", f"цепочка после части 4: {calls()}")

    # --- 5. Негативный контроль осознанного расхождения со сторожем звука.
    # Звук гаснет и по потере ФОКУСА (клик в адресную строку), а геймплей —
    # только по уходу вкладки в фон, иначе в метрики Яндекса полетит start/stop
    # на каждый клик мимо канваса. Проверяется тем, что игра БЕЗ ФОКУСА, но на
    # переднем плане, всё равно даёт GameplayAPI.start.
    #
    # ⚠ Синтетический window.dispatchEvent(new Event('blur')) здесь НЕ годится
    # и сначала стоял тут зря: он не меняет document.hasFocus(), поэтому мутация
    # «гасить геймплей и по фокусу» его проходила (замерено). Фокус подменяем до
    # первого скрипта страницы, как в сценарии focus.
    s.page.add_init_script(
        "Object.defineProperty(document, 'hasFocus', {value: function () { return false; },"
        " configurable: true});")
    s.page.goto(f"{base}?lang=en")
    boot()
    s.wait(YA_STUB_DELAY_MS / 1000.0, "SDK ответил")
    play("без фокуса")
    s.expect(calls() == "ready,start",
             f"вкладка без фокуса, но на переднем плане — геймплей обязан идти: {calls()}")
    s.note("ya", f"без фокуса: {calls()}")


def scenario_resize(s):
    """Требование Я.Игр (раздел 2): игра корректно рендерится при ресайзе окна,
    а на мобиле прогресс не теряется при смене ориентации.

    Это единственная проверка ресайза как СОБЫТИЯ: `hittest` гоняется на разных
    вьюпортах, но каждый раз с нуля — окно там не меняется по ходу партии, и
    сброс раздачи на ресайзе он бы не заметил.

    Оракул — вектор глубин восьми колонок: они обязаны пережить ресайз без
    изменений. Ограничение метода честно: по пикселям НЕ видно, какие именно
    карты лежат, поэтому раздача, случайно совпавшая по глубинам, прошла бы. На
    debug-сборке к этому добавляется прямая проверка, что уровень не грузился
    заново. В конце — негативный контроль: принудительная пересдача обязана
    вектор глубин сломать, иначе весь сценарий ничего не различает.
    """
    s.boot()
    s.press_play()
    s.wait(2, "раздача осела")
    felt = s.brightness(*FREE_CELL[1])   # пустая ячейка = эталон сукна

    def depths(label):
        s.measure()
        v = [s.exposed_depth(c, felt) for c in range(1, 9)]
        s.note("depths", f"{label}: {v}")
        return v

    before = depths("960x540")
    s.expect(any(d is not None for d in before),
             "стол пуст ещё до ресайза — сравнивать нечего")
    deals_before = len(s.logs_matching(r"I am MAIN SCRIPT"))
    s.shot("before-resize")

    for w, h in ((1200, 540), (800, 600), (960, 540)):
        s.page.set_viewport_size({"width": w, "height": h})
        s.wait(2, f"ресайз {w}x{h} осел")
        s.shot(f"resized-{w}x{h}")
        s.expect(depths(f"{w}x{h}") == before,
                 f"после ресайза {w}x{h} раздача изменилась — прогресс потерян")

    if deals_before:   # debug-сборка: движок печатает
        s.expect(len(s.logs_matching(r"I am MAIN SCRIPT")) == deals_before,
                 "ресайз перезагрузил уровень — прогресс потерян")

        # Негативный контроль: пересдача обязана сломать вектор глубин, иначе
        # проверка выше зеленела бы и на потерянном прогрессе.
        s.key("Space", "пересдача")
        s.wait(3, "новая раздача осела")
        s.expect(depths("после пересдачи") != before,
                 "вектор глубин не различает даже полную пересдачу — оракул слепой")


def scenario_dealrng(s):
    """D4: две раздачи, попавшие в одну секунду, обязаны быть РАЗНЫМИ.

    `shuffle_deck` сидировал генератор на каждую раздачу через `os.time()`, а
    тот идёт целыми секундами: два рестарта подряд брали один seed и давали
    побайтово одинаковую колоду. Пиксельные оракулы этого не видят —
    `restartrace` сравнивает стол с тем, что было ДО серии рестартов, и восемь
    одинаковых раздач подряд проходят у него как «стол изменился».

    Оракул — отпечаток разложенного стола из debug-лога вместе с `os.time()`
    той же раздачи. Сценарий сперва доказывает, что вообще попал в окно (есть
    хотя бы одна секунда с ДВУМЯ раздачами) и только потом требует, чтобы их
    отпечатки различались. Без первой проверки зелёный результат означал бы
    всего лишь «мы нажимали слишком медленно, чтобы столкнуться».

    Только debug-сборка: отпечаток печатает `deal_cards` под `debug_flags`.
    """
    s.boot()
    s.press_play()
    # Не wait_for_log: press_play возвращается уже ПОСЛЕ первой раздачи, и её
    # строку курсор лога успевает пройти — первый прогон сценария из-за этого
    # ругался «отпечатка нет», печатая отпечатки строкой выше.
    s.expect(s.logs_matching(r"\[DEAL\] fingerprint="),
             "раздача не напечатала отпечаток — сборка не debug или лог не тот")

    # hold=40 мс вместо штатных 250: движок такое нажатие видит (замерено в
    # restartrace), а раздачи ложатся плотнее — иначе на секунду приходится
    # меньше двух пересдач и столкновению просто негде случиться.
    for n in range(12):
        s.key("Space", f"пересдача {n + 1}", hold=40)
    s.wait(3, "последняя раздача осела")

    rx = re.compile(r"\[DEAL\] fingerprint=(\d+) t=(\d+)")
    deals = []
    for e in s.logs_matching(r"\[DEAL\] fingerprint="):
        m = rx.search(e["text"])
        if m:
            deals.append((m.group(1), int(m.group(2))))
    s.expect(len(deals) >= 3, f"раздач в логе {len(deals)} — нажатия не дошли до движка")

    by_sec = {}
    for fp, t in deals:
        by_sec.setdefault(t, []).append(fp)
    crowded = {t: fps for t, fps in by_sec.items() if len(fps) >= 2}
    s.note("deals", f"раздач {len(deals)}, разных секунд {len(by_sec)}, "
                    f"секунд с ≥2 раздачами {len(crowded)}")
    s.expect(crowded,
             "ни одна секунда не собрала двух раздач — сценарий не попал в окно бага, "
             "проверять нечего")
    for t, fps in sorted(crowded.items()):
        s.note("second", f"t={t}: раздач {len(fps)}, различных колод {len(set(fps))}")
        s.expect(len(set(fps)) == len(fps),
                 f"в секунду t={t} попало {len(fps)} раздач, а различных колод "
                 f"{len(set(fps))} — генератор сидируется от os.time() на каждую раздачу")

    all_fps = [fp for fp, _ in deals]
    # Формулировка «совпадение невозможно» была бы завышена: сравниваются не
    # колоды, а 30-битные отпечатки, и четыре дракона одной масти неразличимы по
    # id — коллизия в принципе бывает. Для нынешнего бага os.time() этого хватает
    # с запасом: там совпадали не отпечатки, а сами колоды, десятками подряд.
    s.expect(len(set(all_fps)) == len(all_fps),
             f"{len(all_fps)} раздач дали всего {len(set(all_fps))} различных отпечатков — "
             f"случайная коллизия хеша так часто не бывает, это одинаковые колоды")


DRAGON_BUTTON = {1: (481, 508), 2: (481, 406), 3: (481, 457)}


def scenario_guilock(s):
    """H7: кнопки рельса не спрашивают замок авто-сбора — ЧТО именно от этого ломается.

    Это замер, а не починка. Претензия ревью звучала так: `disable_input`
    глушит только `cursor.on_input`, а RESTART/TUTORIAL живут в
    `ui.gui_script` и остаются нажимаемыми — нажатие посреди полёта карт
    уводит в `game_manager.show`, то есть выгружает коллекцию, пока
    `go.animate` ещё летит и её колбэк собирается постить `drop_success`.

    Два окна, в каждом жмём RESTART:
      A) раздача: цветок и открытые двойки летят дугой (`flying_count > 0`);
      B) середина реплея: `cursor.input_disabled = true` — игрок заглушен
         движком НАМЕРЕННО, и рельс остаётся единственной живой поверхностью.
    Третье — ручной сбор драконов — в сценарии `dragonrestart`: на честной
    раздаче кнопка не загорается (замер ниже), нужен бандл DEBUG_DRAGONS.

    Оракул на каждую фазу: ни одной FATAL-строки, новая раздача приехала
    (`I am MAIN SCRIPT`), стол разложен и в него МОЖНО ИГРАТЬ — карта из
    первой колонки паркуется в свободную ячейку. Последнее обязательно:
    выгрузка посреди анимации может оставить не труп, а живого калеку —
    например, курсор с ненулевым `flying_count`, который молча съедает нажатия.
    """
    def fatals():
        return len([e for e in s.log if e["kind"] == "FATAL"])

    def playable(tag):
        """Стол разложен и принимает ход: верхушка колонки 1 -> свободная ячейка 1."""
        cell = FREE_CELL[1]
        felt = s.brightness(*cell)
        d = s.exposed_depth(1, felt)
        if not s.expect(d is not None, f"{tag}: колонка 1 пуста — раздачи не случилось"):
            return
        s.expect_empty_at(cell[0], cell[1], felt, f"{tag}: ячейка 1 до хода")
        s.drag_game(TABLEAU_X[1], TABLEAU_TOP_Y - d * CARD_PITCH, cell[0], cell[1],
                    f"{tag}: верхушка колонки 1 -> ячейка 1")
        s.wait(1.5, "карта садится")
        s.expect_card_at(cell[0], cell[1], felt, f"{tag}: карта доехала до ячейки")

    def restart_now(tag, hold=40):
        before = fatals()
        s.click_game(*RESTART_BUTTON, label=f"{tag}: RESTART", hold=hold)
        got = s.wait_for_log(r"I am MAIN SCRIPT", 20, f"{tag}: пересдача")
        s.expect(got, f"{tag}: RESTART не перезагрузил уровень")
        s.wait(3, "раздача осела")
        s.expect(fatals() == before,
                 f"{tag}: выгрузка посреди полёта дала {fatals() - before} фатальных строк")
        s.shot(tag)
        playable(tag)

    s.boot()
    # --- A: рестарт прямо в дуге раздачи -------------------------------------
    # press_play ждёт 2.5 с и промахивается мимо окна: цветок садится за ~0.7 с.
    s.click_game(*PLAY_BUTTON, label="PLAY")
    s.expect(s.wait_for_log(r"I am MAIN SCRIPT", 20, "первая раздача"),
             "PLAY не загрузил уровень")
    s.page.wait_for_timeout(250)   # середина дуги цветка/двоек
    restart_now("A-deal-flight")

    # --- B: рестарт посреди реплея -------------------------------------------
    # Директивы теперь печатаются по одной (M4), поэтому окно ловится точно, а
    # не «через N секунд после старта».
    hit_b = False
    for attempt in range(1, 7):
        s.key("r", f"debug_replay {attempt}")
        verdict = s.wait_for_log(
            r"\[REPLAY\] (SOLVED|timeout|budget_exhausted|unsolvable|no_solution|planner desync|снапшот)", 90)
        if verdict and "SOLVED" in verdict:
            s.expect(s.wait_for_log(r"\[REPLAY\] d (\d+)/", 30, "первая директива"),
                     "реплей не напечатал ни одной директивы")
            s.wait(4, "реплей разогнался, карты в полёте")
            restart_now("B-replay")
            hit_b = True
            break
        s.key("Space", "новая раздача", hold=40)
        s.wait(3, "пересдача")
    s.expect(hit_b, "за 6 попыток ни одна раздача не решилась в бюджете — фазы B не было")

    # Фаза C (рестарт посреди РУЧНОГО сбора драконов) живёт отдельным сценарием
    # `dragonrestart`: на честной раздаче кнопка не загорается — замерено, 24
    # пересдачи подряд не дали ни одной. Оно и понятно: чтобы масть собралась
    # сама собой, все четыре её дракона должны оказаться верхушками, а раздача
    # такого не обещает. Нужна раскладка DEBUG_DRAGONS, то есть другой бандл.


def _lit_dragon_button(s):
    """Номер пульсирующей кнопки или None.

    Ищем по ПУЛЬСУ, а не по цвету: `dragon_button.check_state` гоняет scale
    пингпонгом ровно у горящей кнопки, поэтому два снимка одного пятачка с
    интервалом дают разные байты только у живой анимации. Цветовой порог
    пришлось бы подбирать под каждый спрайт масти."""
    for n, (x, y) in DRAGON_BUTTON.items():
        a = s.patch(x, y, 24, 24)
        s.page.wait_for_timeout(260)
        b = s.patch(x, y, 24, 24)
        if a != b:
            s.note("dragon", f"кнопка {n} пульсирует — масть собрана")
            return n
    return None


def scenario_dragonrestart(s):
    """H7, фаза C: RESTART посреди РУЧНОГО сбора драконов.

    ⚠ ТРЕБУЕТ бандла, собранного с `DEBUG_DRAGONS = true` в main.script:
    честная раздача горящую кнопку почти никогда не даёт (замер в `guilock` —
    24 пересдачи подряд, ни одной). Отладочная раскладка кладёт красных
    драконов верхушками четырёх колонок, и кнопка горит с первого кадра.

    Это тот самый путь из претензии ревью: кнопку жмёт палец, `input_disabled`
    на нём не выставляется вовсе, единственный замок — `flying_count` внутри
    `cursor.on_input`, до которого рельс GUI не имеет отношения. Четыре дракона
    летят 0.35+0.35 с плюс 0.1 с задержки на карту — окно около секунды.

    Ненайденная горящая кнопка здесь не «нет окна», а провал: на этой сборке
    она обязана гореть, и её отсутствие означает, что сломан детектор пульса,
    а не игра. Так проверка детектора получает положительный контроль."""
    s.boot()
    s.press_play()
    s.shot("dragon-deal")

    n = _lit_dragon_button(s)
    if not s.expect(n, "на сборке DEBUG_DRAGONS ни одна кнопка не пульсирует — "
                       "либо бандл собран без флага, либо сломан детектор пульса"):
        return

    before = len([e for e in s.log if e["kind"] == "FATAL"])
    x, y = DRAGON_BUTTON[n]
    s.click_game(x, y, label=f"сбор драконов кнопкой {n}", hold=40)
    s.page.wait_for_timeout(300)   # середина дуги: 0.7 с полёта + 0.1 с на карту
    s.shot("mid-arc")
    s.click_game(*RESTART_BUTTON, label="RESTART посреди дуги", hold=40)
    got = s.wait_for_log(r"I am MAIN SCRIPT", 20, "пересдача")
    s.expect(got, "RESTART посреди сбора не перезагрузил уровень")
    s.wait(3, "раздача осела")
    after = len([e for e in s.log if e["kind"] == "FATAL"])
    s.expect(after == before,
             f"выгрузка посреди сбора дала {after - before} фатальных строк")
    s.shot("after-restart")

    # Стол обязан не просто перезагрузиться, а принимать ход: выгрузка посреди
    # анимации могла оставить курсор с ненулевым flying_count, и тогда игра
    # молча ест нажатия. Раскладка DEBUG_DRAGONS кладёт драконов, их можно
    # таскать в ячейки.
    cell = FREE_CELL[1]
    felt = s.brightness(*cell)
    d = s.exposed_depth(1, felt)
    if s.expect(d is not None, "колонка 1 пуста — пересдачи не случилось"):
        s.drag_game(TABLEAU_X[1], TABLEAU_TOP_Y - d * CARD_PITCH, cell[0], cell[1],
                    "верхушка колонки 1 -> ячейка 1")
        s.wait(1.5, "карта садится")
        s.expect_card_at(cell[0], cell[1], felt, "карта доехала до ячейки после рестарта")


def scenario_celldrain(s):
    """L2: авто-финиш обязан забрать последнюю карту ИЗ СВОБОДНОЙ ЯЧЕЙКИ.

    ⚠ ТРЕБУЕТ бандла с `DEBUG_CELL_DRAIN = true` в main.script. Собрать такую
    доску настоящей раздачей стенд не может: нужно, чтобы у игрока остался
    ровно один ход и он вёл в ячейку.

    Раскладка (main.script, deal_cell_drain_test): колонка 1 = [2_red, 3_red],
    колонки 2 и 3 — по двойке. Двойки 2 и 3 улетают сами (blue=2, green=2),
    2_red закопана под 3_red. Сценарий делает единственный доступный ход —
    уводит 3_red в ячейку, — после чего 2_red открывается и улетает сама.
    Стол пуст, в ячейке лежит 3_red, foundation ждёт ровно её.

    ДО правки L2 здесь не происходило ничего: `can_auto_finish` считал
    оставшиеся карты по одним колонкам, получал ноль и отказывал, а победу
    держала (правильно!) проверка cell_occupied в auto_finish_step. Игрок
    дотаскивал последнюю карту руками. Этот сценарий — негативный контроль к
    правке: на сборке без неё он обязан ПАДАТЬ по таймауту победы.

    Оракул тройной, потому что каждый по отдельности врёт: строка лога
    (авто-финиш мог бы отработать и без победы), пустая ячейка (карту мог
    забрать кто угодно) и поднявшийся экран победы в пикселях."""
    s.boot()
    s.press_play()
    s.shot("dealt")

    cell = FREE_CELL[1]
    felt = s.brightness(*cell)
    # Колонка 1 раздаётся на две карты, поэтому верхушка на глубине 1.
    d = s.exposed_depth(1, felt, max_depth=2)
    if not s.expect(d is not None, "колонка 1 пуста — бандл собран без DEBUG_CELL_DRAIN?"):
        return
    s.expect(s.logs_matching(r"I am MAIN SCRIPT"), "уровень не загрузился")

    s.drag_game(TABLEAU_X[1], TABLEAU_TOP_Y - d * CARD_PITCH, cell[0], cell[1],
                "3_red -> свободная ячейка 1")

    # Дальше СЛЕДИМ, а не ждём. Оракул — порядок трёх событий: карта легла в
    # ячейку, потом ячейка опустела, потом объявлена победа. Ждать паузой здесь
    # нельзя, и это измерено: первая версия делала wait(2.0), а к этому моменту
    # авто-финиш успевал отработать целиком и поднять экран победы — тот
    # закрывает весь кадр иллюстрацией, и пятачок ячейки читался ярким. Проверка
    # «карта в ячейке» проходила по картинке победы, а проверка «ячейка пуста»
    # по ней же падала. Оба вывода были про оверлей, а не про карту.
    saw_parked, saw_empty, victory = False, False, None
    for _ in range(150):
        b = s.brightness(cell[0], cell[1])
        if not saw_parked:
            if b - felt > s.GAP:
                saw_parked = True
                s.note("pixel", f"3_red села в ячейку (luminance={b:.0f} vs felt {felt:.0f})")
        elif not saw_empty and b - felt <= s.GAP:
            saw_empty = True
            s.note("pixel", f"ячейка опустела — карту забрал авто-финиш (luminance={b:.0f})")
        hits = s.logs_matching(r"\[MAIN\] auto-finish complete")
        if hits:
            victory = hits[-1]["text"]
            break
        s.page.wait_for_timeout(100)

    s.expect(saw_parked, "3_red не доехала до ячейки — ход не состоялся, проверять нечего")
    s.expect(victory, "авто-финиш не забрал последнюю карту из ячейки: "
                      "стол пуст, ход есть, а победы нет")
    s.expect(saw_empty, "победа объявлена, но ячейка ни разу не была замечена пустой — "
                        "значит победу дали поверх карты в ячейке")
    s.wait(2.0, "экран победы поднялся")
    s.shot("after")
    # Экран победы закрывает весь кадр: там, где был стол, теперь иллюстрация.
    s.expect(s.brightness(TABLEAU_X[8], TABLEAU_TOP_Y) - felt > s.GAP,
             "экран победы не поднялся — на месте стола по-прежнему фон")


SCENARIOS = {"boot": scenario_boot, "hittest": scenario_hittest,
             "guilock": scenario_guilock, "dragonrestart": scenario_dragonrestart,
             "celldrain": scenario_celldrain,
             "stuck": scenario_stuck, "win": scenario_win,
             "freecell": scenario_freecell, "census": scenario_census,
             "focus": scenario_focus, "audiobg": scenario_audiobg,
             "debugkeys": scenario_debugkeys, "restartrace": scenario_restartrace,
             "i18n": scenario_i18n, "yasdk": scenario_yasdk,
             "resize": scenario_resize, "dealrng": scenario_dealrng}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bundle")
    ap.add_argument("--scenario", default="boot", choices=sorted(SCENARIOS))
    ap.add_argument("--out", default="/tmp/browser-test")
    ap.add_argument("--viewport", default="960x540", help="e.g. 1200x540 (20:9) or 800x600 (4:3)")
    ap.add_argument("--dpr", type=float, default=1.0,
                    help="devicePixelRatio. game.project sets high_dpi=1, so on dpr>1 the "
                         "canvas backing store is scaled and window.get_size() may report "
                         "physical pixels while action.x/y stay logical -- which is exactly "
                         "what the coords conversion divides by. Mobile is dpr 2-3.")
    ap.add_argument("--no-coi", action="store_true",
                    help="serve WITHOUT cross-origin isolation (no SharedArrayBuffer), "
                         "which is what a host that omits COOP/COEP gives you")
    ap.add_argument("--headed", action="store_true")
    ap.add_argument("--query", default="",
                    help="query-строка к index.html, например lang=ru (H2: так язык задают Я.Игры)")
    args = ap.parse_args()

    if not os.path.isfile(os.path.join(args.bundle, "index.html")):
        sys.exit(f"no index.html in {args.bundle}")
    os.makedirs(args.out, exist_ok=True)
    vw, vh = (int(v) for v in args.viewport.lower().split("x"))

    httpd, port = serve(args.bundle, coi=not args.no_coi)
    url = f"http://127.0.0.1:{port}/index.html" + (f"?{args.query}" if args.query else "")
    print(f"serving {args.bundle}\n  at {url}  viewport={vw}x{vh} dpr={args.dpr}  "
          f"cross-origin-isolated={not args.no_coi}\n")

    from playwright.sync_api import sync_playwright

    fatal, binaries = [], []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=not args.headed,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                  "--disable-gpu-sandbox", "--autoplay-policy=no-user-gesture-required"],
        )
        page = browser.new_page(viewport={"width": vw, "height": vh},
                                device_scale_factor=args.dpr)
        s = Session(page, args.out)
        s.url = url

        def on_console(m):
            kind = classify(m.text)
            if kind == "FATAL":
                fatal.append(m.text)
            s.note(kind, m.text)

        def on_request(r):
            if r.url.endswith((".wasm", ".js")):
                name = r.url.rsplit("/", 1)[-1]
                binaries.append(name)
                s.note("req", name)

        page.on("console", on_console)
        page.on("pageerror", lambda e: (fatal.append(str(e)), s.note("FATAL", f"pageerror {e}")))
        page.on("request", on_request)
        page.on("requestfailed", lambda r: s.note("net-fail", f"{r.url} {r.failure}"))

        page.goto(url)
        try:
            SCENARIOS[args.scenario](s)
        finally:
            report = {
                "scenario": args.scenario, "viewport": [vw, vh],
                "cross_origin_isolated": not args.no_coi,
                "binaries": binaries, "fatal": fatal,
                "failures": s.failures, "log": s.log,
            }
            with open(os.path.join(args.out, "report.json"), "w") as f:
                json.dump(report, f, indent=1)
            browser.close()
    httpd.shutdown()

    print(f"\n=== scenario={args.scenario} viewport={vw}x{vh} coi={not args.no_coi} ===")
    print(f"binaries served: {', '.join(sorted(set(binaries))) or '(none)'}")
    print(f"{len(s.log)} events, {len(fatal)} fatal, {len(s.failures)} failed expectations")
    for f_ in fatal:
        print("FATAL:", f_[:300])
    for f_ in s.failures:
        print("FAIL: ", f_)
    ok = not fatal and not s.failures
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
