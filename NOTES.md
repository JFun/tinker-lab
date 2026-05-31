# Tinker Lab — Session Notes

Working journal of what's been built and the design decisions behind it. Update
this whenever a major design choice is made or a class of bug gets caught — so
the next session can resume without re-deriving everything.

## Current state (MVP playable scaffold)

- **Engine**: Godot 4.6, Mobile renderer, portrait (720×1280 design).
- **iOS**: bundle `com.jfun.tinkerlab`, team `Y3T546NP6T`. Deploy via
  `scripts/dev/deploy_ios.sh` to the paired iPhone 13 Pro.
- **Local tests**: `scripts/dev/test.sh` runs the recipe-tree test harness +
  smoke-launches the project headlessly. **163 tests** pass.
- **Pixel-render verification**: `scripts/dev/ui_check.sh` renders the village +
  workbench scenes via `godot -- --shoot` to `build/ui-screenshots/`. Required
  for any UI/draw change per global CLAUDE.md.

## Architecture

```
project.godot                 — autoloads: Items, GameState, Npcs, Audio, Ads
data/
  items.gd                    — 55 items, recipe data, validation at startup
  game_state.gd               — board, Steam, discovered, quests, save/load
  npcs.gd                     — 5 Market Square NPCs + 4 districts (3 locked)
systems/
  audio.gd                    — procedural SFX (place/merge/discover/deliver/nope)
  ads.gd                      — stub rewarded/interstitial (no real SDK yet)
scenes/
  main.tscn/.gd               — router (village ↔ workbench), --shoot mode
  village.tscn/.gd            — main menu: title, progress, NPCs, roadmap
  workbench.tscn/.gd          — 6×8 grid, drag-merge, hints, chute, delivery
  invention_book.tscn/.gd     — discovery tracker modal
  tutorial.tscn/.gd           — first-run 4-step overlay
tests/
  test_recipes.gd             — 163 assertions: tree closure, tier integrity,
                                quest reachability, no-phantom-upgrade
  test_glyphs.gd              — diagnostic (non-blocking) for iOS glyph coverage
scripts/dev/
  test.sh                     — full test suite + smoke launch
  deploy_ios.sh               — Godot export → xcodebuild → install → launch
  ui_check.sh                 — render PNGs of village + workbench + drag state
```

## Game mechanics — current state

- **Board**: 6×8 grid, chute spawns junk every 5s (paused if no empty cell).
- **Merge tree**: 10 Junk → 10 Crafted → 10 Parts → 20 Inventions → 5 Masterworks.
  - Same+same upgrade chain runs Junk→Crafted→Part (top of upgrade).
  - Different+different cross-combines at Tier 2 (Parts) make Inventions.
  - Different+different cross-combines at Tier 3 (Inventions) make Masterworks.
- **Steam economy**: 30 cap, regen 1/2min, refill button when <5 (stubbed ad).
  - **Upgrade merges are FREE.** Only invention/masterwork merges cost 1 Steam.
- **Quests**: 5 NPCs in Market Square. Tap NPC → workshop with quest banner
  showing target invention recipe ("Baker wants Oven — combine Boiler + Fuel Tank").
- **Progression**: village shows "Market Square — X/5 quests" + roadmap of
  3 locked districts (Residential Lane, Industrial Quarter, Hilltop Observatory).
- **Tutorial**: auto-opens first workshop visit, 4 steps + color-code legend.

## UI affordances

- **Drag highlight**: green ring on valid merge target, blue on empty cells, red
  on invalid pair. Plus floating dragged item sprite at finger position.
- **Ambient pulse**: small green corner dot on cells that have at least one
  mergeable partner anywhere on the board.
- **Merge demo**: "A + B → C" caption pops above the merge cell + yellow flash.
- **Discover toast**: brass-bordered banner at top of board, 3s fade.
- **Deliver CTA**: full-width bright yellow pulsing banner when quest invention
  appears on the board.
- **Idle hint**: after 8s of no input, dim the board and highlight 1-2
  suggested cells with golden ring + animated arrow + toast. Re-fires every
  10s while still idle.
- **Long-press to delete**: hold any item for 0.7s (no drift) to remove it.
  Red progress arc shows the hold, "Release to remove" appears when full.
  Escape hatch for soft-locked full boards.

## Card visual style (current iteration)

Settled on a **parchment-card** look after iterating away from saturated
backgrounds:
- Cream parchment fill (Color(0.93, 0.86, 0.72))
- Tier-colored border, thickness grows with tier (2→6px)
- Big item-colored glyph as the hero element
- Tiny name caption below the glyph
- Slim tier band at the bottom: JUNK / CRAFTED / PART / INVENT / MASTER

## Glyph coverage (iOS gotcha)

**Emoji-block Unicode (U+2600–27BF, U+1F300+) is unreliable** in Godot's iOS
fallback font. These render as blank `.notdef` boxes:

| Was | Now | Reason |
|---|---|---|
| `♨` oven | `Ω` | hot springs not in iOS fallback |
| `⚙` steam_engine | `Ξ` | gear emoji not in iOS fallback |
| `⚡` generator | `Ζ` | high-voltage not in iOS fallback |
| `✉` mail_sorter | `⊠` | envelope not in iOS fallback |

**Safe Unicode blocks**: Basic Latin, Greek (Α-Ω, α-ω), Math operators (∽ ∿ ‖),
Geometric Shapes U+25xx (○ ● □ ■ ◆ ◇ ▣ ▤ ▥ ▦ ▩ ◐ ◴). Most U+27xx star symbols
work on iOS too (❀ ✦ ✶ ✸ ✺).

**Test**: `godot --headless --path . -s res://tests/test_glyphs.gd` lists
possibly-missing glyphs (treat as hint — desktop fallback is much smaller than
iOS, false positives are common).

## Bugs caught + their tests

- **Variant-from-`max()` parse errors** (recurring): `max()` returns Variant in
  GDScript 4. Always annotate: `var x: int = max(a, b)`.
- **"Drag two Clocks together to upgrade"** suggestion (no recipe exists):
  cell was in `_mergeable_cells` because of a cross-combine partner, but the
  same+same fallback didn't re-verify. Fixed + added regression test
  `_test_no_phantom_upgrade_at_high_tiers`.
- **Workbench rendered blank** (early): full-screen `ColorRect` background as
  child of Workbench covered the parent's `_draw()` output. Removed; rely on
  viewport clear color. **Captured in global CLAUDE.md.**
- **Main scene was Node not Control**: full-anchored Workbench had no parent to
  anchor against → zero size → nothing visible. Fixed.
- **iOS AcceptDialog popups don't show reliably**: replaced NPC-tap popup with
  direct workshop navigation. Tutorial uses an in-scene Control overlay, not
  a Window.

## Open product questions / future work

- **4.3(a) risk**: mechanic differentiation (branching discovery) is genuinely
  unique. Visual presentation is currently placeholder. Real risk is "looks
  like Merge Mansion" until original art lands. Priority before submission:
  60 hand-drawn 64×64 sprites + wood-grain workbench texture.
- **Districts beyond Market Square**: roadmap is shown but only Market Square
  is wired. Post-MVP per PRD.
- **Real audio**: BGM is stubbed. Procedural SFX work but a composed track
  per district is post-MVP.
- **Real ads SDK**: `systems/ads.gd` is a stub.
- **Saved game**: works (`user://save.json`). No manual reset UI — delete the
  app to fresh-start.

## Closest competitors (researched)

| Game | Overlap | App Store |
|---|---|---|
| Merge Mansion | Highest — merge2 + restore + NPCs | `apps.apple.com/us/app/merge-mansion-mystery-puzzles/id1484442152` |
| Travel Town | Merge + town rebuild | `apps.apple.com/us/app/travel-town-merge-adventure/id1521236603` |
| Merge Dragons! | Genre defining ($780M) | (Merge3, not Merge2) |
| Little Alchemy 2 | Pure discovery, no board | `apps.apple.com/us/app/little-alchemy-2/id1214190989` |

**Positioning hook**: "Merge Mansion meets Little Alchemy in a steampunk village."

Avoid the word "merge" in App Store subtitle. Tinker Lab files under Puzzle
(primary) + Simulation (secondary) — keeps out of the Mansion comparison pool.
