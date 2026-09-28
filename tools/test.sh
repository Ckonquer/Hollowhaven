#!/usr/bin/env bash
# Run headless unit tests. Usage: tools/test.sh [filter]
# The full suite (no filter) takes ~15-25 min since Chapter Two; filtered runs are usually seconds.
# Override the limit with HH_TEST_SECONDS (seconds).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-}"
LIMIT="${HH_TEST_SECONDS:-2400}"
cd "$ROOT/game" && timeout $((LIMIT + 30)) "$ROOT/tools/godot.sh" --headless --path . res://tests/runner.tscn -- --filter="$F" --results="$ROOT/qa/tmp/test_results_${F:-all}.json" --max-seconds="$LIMIT"
