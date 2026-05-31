#!/usr/bin/env bash
# Tinker Lab — local self-test (per global CLAUDE.md).
# Runs recipe-tree sanity tests and verifies the project at least parses.
set -euo pipefail

cd "$(dirname "$0")/../.."

echo "==> Importing project (first run may take a moment)..."
godot --headless --quit --import 2>&1 | tail -5 || true

echo "==> Running recipe tests..."
godot --headless --path . -s res://tests/test_recipes.gd

echo "==> Running hint/chute logic tests..."
godot --headless --path . -- --test-hints

echo "==> Smoke-launching main scene (30 frames)..."
godot --headless --path . --quit-after 30 2>&1 | tail -10

echo
echo "✅ All tests passed."
