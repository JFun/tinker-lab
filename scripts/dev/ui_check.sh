#!/usr/bin/env bash
# Render workbench + village to PNGs so we can verify UI without deploying.
# Real Metal renderer required (per global CLAUDE.md) — a window briefly appears.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=build/ui-screenshots
mkdir -p "$OUT"

godot --path . -- --shoot 2>&1 | tail -10

USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/Tinker Lab"
cp "$USER_DATA"/ui_*.png "$OUT/" 2>/dev/null || true
echo
echo "✅ PNGs in $OUT/:"
ls -la "$OUT"
