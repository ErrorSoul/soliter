# Advisor gate — 2026-11-07

APPROVE for `5cb671d...25068c871efb39ffa79fc213b661c4790c48a7a0`.

Independent advisor agent `advisor_merge_1107`, fresh context, read-only.
No blocking correctness or regression findings.

Reviewed runtime changes, inherited gameplay fixes, design/animation integration,
regression tests, and recorded evidence. Confirmed:
- foundation disables motion for all accepted/restored cards, including covered ranks;
- foundation arrival callbacks capture each card's final layer;
- GUI on_input consumes button gestures and cancelled releases;
- tutorial preserves normal saves, explicit restart redeals.

Verified five foundation evidence hashes against candidate files and ran
`git diff --check`. Recorded evidence: 287/287 Lua PASS, two browser scenarios
PASS, foundation portrait pixel difference 0.00000 over 55 seconds.

Limitations: advisor did not independently rerun Lua/build/browser tests;
runtime validation relies on inspected author evidence. This is advisor sign-off,
not Grok sign-off. Agent changed no files.
