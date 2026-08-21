"""Discriminator for the wait_for_log cursor fix (no browser needed).

Feeds a Session a hand-made log and asks the same question twice. With the old
scan-from-zero behaviour the second call returns the FIRST attempt's line; with
the cursor it must not.
"""
import importlib.util, sys, types

spec = importlib.util.spec_from_file_location("bt", "/Users/abu/works/ShenzenSolitare/tools/browser-test.py")
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
