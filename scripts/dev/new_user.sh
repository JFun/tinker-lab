#!/usr/bin/env bash
# Dev-only: reset the device to a brand-new-user state WITHOUT a fresh install.
#
# Overwrites the device save with first-run defaults: tutorial_seen=false, empty
# board (the workbench re-seeds a starter hand on entry), nothing discovered, no
# quests, streak 0, last_open_date "". On the next launch GameState behaves exactly
# like a first install — check_daily() arms a day-1 crate (skipped during the
# tutorial, by design) and the tutorial opens on the first workshop visit.
#
# Note: this does NOT wipe the analytics identity (user_id / Firebase install id) —
# that needs a true uninstall+reinstall. For feel-testing onboarding the gameplay
# state is what matters, and this is instant. Use `scripts/dev/deploy_ios.sh` after
# an uninstall if you need a fully pristine analytics identity too.
#
# Usage: scripts/dev/new_user.sh
set -euo pipefail

DEVICE_ID="B7CC8868-E918-5043-A37E-32AC17F755E7"   # iPhone 13 Pro
BUNDLE_ID="com.jfun.tinkerlab"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/save.json" <<'JSON'
{"board":[["","","",""],["","","",""],["","","",""],["","","",""]],"discovered":[],"quests":{},"chute":[],"tutorial_seen":false,"muted":false,"workshop_complete_seen":false,"levels_seen":[],"current_level":0,"last_open_date":"","streak":0,"daily_delivery_pending":false}
JSON

echo ">> pushing fresh first-run save"
xcrun devicectl device copy to --device "$DEVICE_ID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source "$TMP/save.json" --destination Documents/save.json 2>&1 | tail -1

echo ">> relaunching as a new user"
xcrun devicectl device process launch --device "$DEVICE_ID" \
  --terminate-existing "$BUNDLE_ID" 2>&1 | tail -1

echo ">> done — tutorial will open on your first workshop visit."
