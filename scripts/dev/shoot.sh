#!/usr/bin/env bash
# Render named UI screenshots via the in-game harness (main.gd --shoot=<name>).
# Wipes the on-disk save before EVERY shot so each starts from clean first-run
# state (GameState loads save.json at boot — a stale save poisons "fresh" shots,
# e.g. discovered items leaking into the tiers/tutorial renders).
#
# Real Metal renderer required (no --headless) — a window briefly appears.
#
# Usage: scripts/dev/shoot.sh <shot> [<shot> ...]
#   e.g. scripts/dev/shoot.sh workbench tiers tutorial_pop
# Shot names = the `shots` array in scenes/main.gd. No args = run ui_check.sh
# behavior is NOT replicated here; pass names explicitly.
set -euo pipefail
cd "$(dirname "$0")/../.."

USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/Tinker Lab"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

[ $# -ge 1 ] || { echo "usage: $0 <shot> [<shot> ...]" >&2; exit 2; }

for s in "$@"; do
	rm -f "$USER_DATA/save.json"
	"$GODOT" --path . -- --shoot="$s" 2>&1 | tail -1
done

echo "PNGs in: $USER_DATA"
