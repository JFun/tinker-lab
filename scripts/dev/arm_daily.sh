#!/usr/bin/env bash
# Dev-only: simulate a daily-return WITHOUT waiting real calendar days.
#
# The streak lives in the device save as `last_open_date` + `streak`. At every
# launch GameState.check_daily() compares last_open_date to *today*:
#   - gap == 1 day  -> streak += 1   (consecutive return)
#   - gap >  1 / "" -> streak  = 1   (first run, or a missed day resets)
# and arms `daily_delivery_pending`. This script back-dates the save so the next
# launch lands on the streak you ask for, then relaunches onto the village (which
# never autosaves, so the edit can't be clobbered). Tap a workshop to see the card.
#
# Usage:
#   scripts/dev/arm_daily.sh <streak>     # e.g. 1, 3, 7
#     1     -> reward = 1 Component   (also tests the "missed day -> reset" path)
#     2     -> reward = 1 Component
#     3..6  -> reward = 1 Part
#     7+    -> reward = 2 Parts
#
# How it works: for streak N>1 we write last_open_date = YESTERDAY and streak = N-1,
# so check_daily() bumps it to N on launch (exercising the REAL transition logic +
# the daily_return analytics event). For N==1 we write a 5-days-ago date so the gap
# forces a reset to 1.
set -euo pipefail

STREAK="${1:-3}"
DEVICE_ID="B7CC8868-E918-5043-A37E-32AC17F755E7"   # iPhone 13 Pro
BUNDLE_ID="com.jfun.tinkerlab"

if ! [[ "$STREAK" =~ ^[0-9]+$ ]] || [ "$STREAK" -lt 1 ]; then
  echo "usage: $0 <streak>=1+   (got '$STREAK')" >&2
  exit 1
fi

if [ "$STREAK" -eq 1 ]; then
  PREV_DATE="$(date -v-5d +%Y-%m-%d)"   # >1 day gap -> check_daily resets to 1
  PREV_STREAK=99                         # value is irrelevant; reset wins
else
  PREV_DATE="$(date -v-1d +%Y-%m-%d)"   # exactly yesterday -> +1
  PREV_STREAK=$((STREAK - 1))
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ">> pulling current save"
xcrun devicectl device copy from --device "$DEVICE_ID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source Documents/save.json --destination "$TMP/save.json" 2>&1 | tail -1

echo ">> back-dating: last_open_date=$PREV_DATE streak=$PREV_STREAK (target streak=$STREAK)"
PREV_DATE="$PREV_DATE" PREV_STREAK="$PREV_STREAK" python3 - "$TMP/save.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["last_open_date"] = os.environ["PREV_DATE"]
d["streak"] = int(os.environ["PREV_STREAK"])
d["daily_delivery_pending"] = False   # let check_daily() arm it on launch
json.dump(d, open(p, "w"))
print("   wrote", {k: d[k] for k in ("last_open_date", "streak", "daily_delivery_pending")})
PY

echo ">> pushing save back"
xcrun devicectl device copy to --device "$DEVICE_ID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source "$TMP/save.json" --destination Documents/save.json 2>&1 | tail -1

echo ">> relaunching (lands on village, idle)"
xcrun devicectl device process launch --device "$DEVICE_ID" \
  --terminate-existing "$BUNDLE_ID" 2>&1 | tail -1

echo ">> done — streak will be $STREAK on launch. Tap a workshop to see the delivery card."
