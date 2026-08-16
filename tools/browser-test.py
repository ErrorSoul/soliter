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
FREE_CELL = {1: (80, 457), 2: (193, 457), 3: (309, 457)}
TABLEAU_X = {1: 77, 2: 193, 3: 309, 4: 425, 5: 541, 6: 657, 7: 773, 8: 889}
TABLEAU_TOP_Y = 299         # depth 0; each further card is 35px lower
CARD_PITCH = 35
FLOWER_SLOT = (541, 457)
PLAY_BUTTON = (480, 232)

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
        """Block until a console line matches, polling the live event log."""
        rx = re.compile(pattern)
        deadline = time.time() + timeout
        seen = 0
        while time.time() < deadline:
            while seen < len(self.log):
                if rx.search(self.log[seen]["text"]):
                    self.note("match", f"{pattern} <- {self.log[seen]['text'][:120]}")
                    return self.log[seen]["text"]
                seen += 1
            self.page.wait_for_timeout(200)
        self.note("timeout", f"no line matched {pattern} in {timeout}s {label}")
        return None

    def shot(self, name):
        self.shots += 1
        path = os.path.join(self.out_dir, f"{self.shots:02d}-{name}.png")
        self.page.screenshot(path=path)
        self.note("shot", os.path.basename(path))
        return path

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
    prints its own verdict from foundation_top."""
    s.boot()
    s.press_play()
    s.shot("dealt")

    # REPLAY_BUDGET is small, so most deals are not solvable; SPACE re-deals.
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
    not assumed."""
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
            r"\[REPLAY\] (SOLVED|budget_exhausted|unsolvable|no_solution|planner desync|снапшот)", 90)
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


SCENARIOS = {"boot": scenario_boot, "hittest": scenario_hittest,
             "stuck": scenario_stuck, "win": scenario_win,
             "freecell": scenario_freecell}


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
    args = ap.parse_args()

    if not os.path.isfile(os.path.join(args.bundle, "index.html")):
        sys.exit(f"no index.html in {args.bundle}")
    os.makedirs(args.out, exist_ok=True)
    vw, vh = (int(v) for v in args.viewport.lower().split("x"))

    httpd, port = serve(args.bundle, coi=not args.no_coi)
    url = f"http://127.0.0.1:{port}/index.html"
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
