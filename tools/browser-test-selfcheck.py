"""Discriminator for the wait_for_log cursor fix (no browser needed).

Feeds a Session a hand-made log and asks the same question twice. With the old
scan-from-zero behaviour the second call returns the FIRST attempt's line; with
the cursor it must not.
"""
import importlib.util, sys, types
from pathlib import Path

spec = importlib.util.spec_from_file_location("bt", Path(__file__).with_name("browser-test.py"))
bt = importlib.util.module_from_spec(spec)
sys.modules["bt"] = bt
spec.loader.exec_module(bt)


class FakePage:
    def wait_for_timeout(self, ms):
        pass


s = bt.Session(FakePage(), "/tmp")
s.note("log", "DEBUG:SCRIPT: [REPLAY] timeout — cannot drive this deal.")

first = s.wait_for_log(r"\[REPLAY\] (SOLVED|timeout)", 1)
assert first and "timeout" in first, f"attempt 1 must read its own verdict, got {first!r}"

# attempt 2: the game prints SOLVED afterwards
s.note("log", "DEBUG:SCRIPT: [REPLAY] SOLVED in 115 moves — driving real cards (115 directives).")
second = s.wait_for_log(r"\[REPLAY\] (SOLVED|timeout)", 1)
assert second and "SOLVED" in second, f"attempt 2 must read the NEW verdict, got {second!r}"

# attempt 3: nothing new printed -> must time out, not recycle an old line
third = s.wait_for_log(r"\[REPLAY\] (SOLVED|timeout)", 1)
assert third is None, f"attempt 3 must find nothing, got {third!r}"

print("OK: wait_for_log consumes each verdict once")


class UnloadTimeoutPage:
    def goto(self, *_args, **_kwargs):
        raise TimeoutError("test: page cannot navigate")


class FakeBrowser:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


s = bt.Session(UnloadTimeoutPage(), "/tmp")
browser = FakeBrowser()
bt.close_browser(s, browser)
assert browser.closed, "unload timeout prevented browser.close"
assert not s.failures, "best-effort navigation changed the scenario verdict"
assert any(e["kind"] == "cleanup-warning" for e in s.log), "cleanup failure was hidden"

browser = FakeBrowser()
try:
    try:
        raise AssertionError("original scenario failure")
    finally:
        bt.close_browser(s, browser)
except AssertionError as exc:
    assert str(exc) == "original scenario failure"
else:
    raise AssertionError("cleanup swallowed the scenario failure")
assert browser.closed
print("OK: cleanup preserves both passing and failing scenario results on unload timeout")

bt.SCENARIOS["future_scenario"] = lambda s: None
assert "future_scenario" in bt.batch_scenarios(), "new scenario omitted from default batch"
assert "future_scenario" not in bt.batch_scenarios(True), "unknown release capability assumed"
assert not (set(bt.batch_scenarios()) & bt.FIXTURE_SCENARIOS)
del bt.SCENARIOS["future_scenario"]
print("OK: batches derive from the scenario registry and respect fixture/release restrictions")
