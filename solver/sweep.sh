#!/usr/bin/env bash
# Parallel solvability sweep: splits seeds 1..N across CPU cores, runs one
# run.lua worker per range, aggregates the solved/timeout/unsolvable totals.
#
# Usage:  bash solver/sweep.sh <N_seeds> <budget> [lua_bin] [cores]
#   N_seeds   total seeds (1..N)            e.g. 2000
#   budget    node budget per board         e.g. 300000
#   lua_bin   lua interpreter (default: lua; on tamagochi use lua5.4)
#   cores     parallel workers (default: nproc)
#
# Run from the repo root so that solver/run.lua resolves its requires.
set -u

N="${1:?need N_seeds}"
BUDGET="${2:?need budget}"
LUA="${3:-lua}"
# Default to leaving 2 cores free for other workloads + buffer (min 1).
CORES="${4:-$( (command -v nproc >/dev/null && echo $(( $(nproc) - 2 < 1 ? 1 : $(nproc) - 2 ))) || echo 2 )}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Be a polite co-tenant: lowest CPU priority (yields to other workloads) and
# idle I/O class when available. RAM per worker is small (tens of MB); CPU is the
# shared resource, so workers run niced and you should leave cores free.
NICE="nice -n 19"
command -v ionice >/dev/null 2>&1 && NICE="ionice -c3 $NICE"

echo "Sweep: seeds 1..$N  budget=$BUDGET  cores=$CORES  lua=$LUA  prio='$NICE'"
echo "Splitting into $CORES ranges; workers running (low priority) in background..."

# Split 1..N into CORES contiguous ranges.
chunk=$(( (N + CORES - 1) / CORES ))
w=0
for ((a=1; a<=N; a+=chunk)); do
  b=$(( a + chunk - 1 )); (( b > N )) && b=$N
  w=$(( w + 1 ))
  $NICE "$LUA" solver/run.lua --seeds "$a..$b" --budget "$BUDGET" >"$TMP/w$w.out" 2>"$TMP/w$w.err" &
done
wait
echo "All $w workers done. Aggregating..."

# Sum the "X / T" counts from each worker's summary lines.
sum() { grep -h "$1" "$TMP"/w*.out | grep -oE '[0-9]+ / [0-9]+' | awk '{s+=$1} END{print s+0}'; }
solved=$(sum "solved within budget:")
timeout=$(sum "timeout (NOT proven")
unsolv=$(sum "proven unsolvable:")
total=$(( solved + timeout + unsolv ))

# Surface any worker errors.
if grep -qs . "$TMP"/w*.err; then
  echo "!! worker stderr (first lines):"; head -n 4 "$TMP"/w*.err
fi

pct() { awk -v n="$1" -v t="$2" 'BEGIN{ printf (t>0)?"%.1f":"0.0", 100*n/t }'; }
echo "================ AGGREGATE (seeds 1..$N, budget=$BUDGET) ================"
if [ "$total" -gt 0 ]; then
  printf "solved within budget:            %d / %d (%s%%)\n" "$solved" "$total" "$(pct "$solved" "$total")"
  printf "timeout (NOT proven unsolvable): %d / %d (%s%%)\n" "$timeout" "$total" "$(pct "$timeout" "$total")"
  printf "proven unsolvable (cons. model): %d / %d (%s%%)\n" "$unsolv" "$total" "$(pct "$unsolv" "$total")"
else
  echo "No results parsed — check worker stderr above."
fi
