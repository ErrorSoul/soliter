#!/usr/bin/env python3
"""Run browser-test scenarios in isolated browsers and retain every result.

Usage: python3 tools/browser-review.py <bundle> --out build/browser-review
Use --browser-channel chrome when using an installed Chrome instead of the
Chromium revision downloaded by Playwright. Exit nonzero on any failed run.
"""
import argparse
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HARNESS = Path(__file__).with_name("browser-test.py").resolve()
spec = importlib.util.spec_from_file_location("browser_test", HARNESS)
browser_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(browser_test)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bundle")
    ap.add_argument("--out", required=True)
    ap.add_argument("--browser-channel", default=None)
    ap.add_argument("--scenarios", nargs="+", choices=sorted(browser_test.SCENARIOS))
    ap.add_argument("--jobs", type=int, choices=(1, 2), default=1)
    ap.add_argument("--viewport", default="960x540")
    ap.add_argument("--dpr", default="1")
    ap.add_argument("--no-coi", action="store_true")
    ap.add_argument("--mobile", action="store_true")
    ap.add_argument("--release", action="store_true")
    args = ap.parse_args()
    args.scenarios = args.scenarios or browser_test.batch_scenarios(args.release)
    if args.release and any(s not in browser_test.RELEASE_SCENARIOS for s in args.scenarios):
        ap.error("release scenarios must use pixel/JavaScript checks: " + " ".join(browser_test.batch_scenarios(True)))
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)

    def run(scenario):
        cmd = [sys.executable, str(HARNESS), str(Path(args.bundle).resolve()),
               "--scenario", scenario, "--out", str(out / scenario),
               "--viewport", args.viewport, "--dpr", args.dpr]
        if args.browser_channel:
            cmd += ["--browser-channel", args.browser_channel]
        if args.no_coi:
            cmd += ["--no-coi"]
        if args.mobile:
            cmd += ["--mobile"]
        if args.release:
            cmd += ["--release"]
        with (out / (scenario + ".log")).open("w") as log:
            try:
                code = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT,
                                      timeout=900).returncode
            except subprocess.TimeoutExpired:
                code = 124
        result = {"scenario": scenario, "exit_code": code}
        print(f"{'PASS' if code == 0 else 'FAIL'} {scenario} (exit {code})", flush=True)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(run, args.scenarios))
    (out / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    failed = sum(r["exit_code"] != 0 for r in results)
    print(f"{len(results) - failed} passed / {failed} failed", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
