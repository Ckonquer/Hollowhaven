#!/usr/bin/env bash
# Wrapper: run the project-local Godot console binary. Usage: tools/godot.sh <args>
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/.tools/godot/Godot_v4.7.2-stable_win64_console.exe" "$@"
