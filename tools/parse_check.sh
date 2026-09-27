#!/usr/bin/env bash
# Parse/compile-check scripts. Usage: tools/parse_check.sh [res://prefix]
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/game" && timeout 180 "$ROOT/tools/godot.sh" --headless --path . res://tests/runner.tscn -- --filter=parse_all --parse-prefix="${1:-}" --max-seconds=170 2>&1 | grep -E "SCRIPT ERROR|ERROR|PASS|FAIL|===="
