#!/usr/bin/env bash
# Run headless unit tests. Usage: tools/test.sh [filter]
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-}"
cd "$ROOT/game" && timeout 600 "$ROOT/tools/godot.sh" --headless --path . res://tests/runner.tscn -- --filter="$F" --results="$ROOT/qa/tmp/test_results_${F:-all}.json" --max-seconds=580
