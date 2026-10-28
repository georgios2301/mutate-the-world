#!/usr/bin/env bash
# Runs every check that works without Roblox Studio.
#   1. pure-logic test suite (luau CLI)
#   2. property-table checker + Roblox API type check (needs luau-lsp + globalTypes.d.luau)
#   3. rojo build of the place file
# Set LUAU_LSP and LUAU_DEFS to the luau-lsp binary and its Roblox definitions file
# (https://github.com/JohnnyMorganz/luau-lsp/releases, scripts/globalTypes.d.luau).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Logic tests"
python3 tests/run_tests.py

if [[ -n "${LUAU_LSP:-}" && -n "${LUAU_DEFS:-}" ]]; then
  echo "== Property tables"
  python3 tests/check_props.py "$LUAU_DEFS"
  echo "== Roblox API type check"
  rojo sourcemap default.project.json -o sourcemap.json
  out=$("$LUAU_LSP" analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" --formatter=plain src 2>&1 | grep -v '^\[' || true)
  if [[ -n "$out" ]]; then
    echo "$out"
    exit 1
  fi
  echo "clean"
else
  echo "== Skipping type check (set LUAU_LSP and LUAU_DEFS to enable)"
fi

echo "== Build"
rojo build default.project.json -o build/MutateTheWorld.rbxlx
echo "All checks passed."
