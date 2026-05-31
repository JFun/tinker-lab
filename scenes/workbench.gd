extends Control
## The Workbench: 6×8 merge grid, drag-merge, chute spawner, deliver-to-NPC button.

signal go_village
signal go_workbench(npc_id: StringName)  # main re-instantiates the board (crossfade)

@export var active_quest_npc: StringName = &""

const UIIcon := preload("res://scenes/ui_icon.gd")
const CELL_PAD := 4.0
const CHUTE_INTERVAL := 2.0  # seconds between auto-spawns (tight: keep the board flowing)

var _cell_size: float = 64.0
var _board_rect: Rect2 = Rect2()
var _dragging_cell: Vector2i = Vector2i(-1, -1)
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_pos: Vector2 = Vector2.ZERO

var _goal_banner: Control  # permanent goal + progress bar
var _goal_label: Label
var _goal_fill: ColorRect
var _goal_track: ColorRect
var _goal_track_sb: StyleBoxFlat  # border tint per NPC
# Quest-recipe banner — visible whenever a quest is active. Shows the parts
var _hint_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer: Timer
var _book_btn: Button
var _back_btn: Button
var _help_btn: Button  # in bottom tab bar (renamed from local var)
var _tab_bar_bg: PanelContainer
var _deliver_btn: Button
var _quest_label: Label
var _board_node: Control
var _chute_timer: Timer
var _failed_experiments: int = 0
# Re-entry guard: _break_soft_lock_if_needed calls set_cell which emits
# board_changed which re-invokes this handler. Without the guard, a full
# board with no mergeable pairs (e.g. all masterworks + lone parts) blows
# the iOS main-thread 1MB stack via GDScript signal recursion.
var _in_break_soft_lock: bool = false

# Recycle blacklist: items the player just scrapped. Chute + soft-lock breaker
# avoid pushing these (or their seed chains, indirectly via skipping the target)
# for ~5 chute ticks (~10s). Stops the "recycled X → X immediately reappears"
# loop that the player called "repetitive endless" — see recycle handler.
var _recent_recycles: Dictionary = {}  # StringName -> ticks remaining
const RECYCLE_BLACKLIST_TICKS := 5
# Cell the player most recently recycled FROM. Soft-lock breaker avoids
# overwriting this slot for a few seconds so the player doesn't see the
# replacement land at the exact spot they just emptied.
var _recent_recycle_cell: Vector2i = Vector2i(-1, -1)
var _recent_recycle_cell_t: float = 0.0
const RECYCLE_CELL_PROTECT_S := 8.0

# Rect for the bin ICON itself (the square box inside the recycle panel).
# Set by _draw_recycle_bin so the hint arrow + glow target the actual bin,
# not the empty space next to it. _recycle_rect is the full panel hit area.
var _recycle_icon_rect: Rect2 = Rect2()

# Recycle target — drag any item onto this to clear its slot and free a space.
# The primary "I'm stuck" escape (replaces long-press-delete; long-press still
# works as a fallback). Clearing a dead duplicate frees the board to flow again.
var _recycle_panel: PanelContainer
var _recycle_label: Label
var _recycle_rect: Rect2 = Rect2()

# Inline discoveries — shows ONLY the current level's 5 targets with big
# legible cells (name + glyph). A small dot-strip above shows level progress
# (1..5: ✓ done, ● current, ○ future). Tap any cell to open the full Book.
var _discoveries_panel: Control
var _cur_grid: GridContainer
var _cur_cells: Array = []  # PanelContainer per target

# Transient merge demo: shows "A + B → C" at the merge cell for a short beat.
var _demo_text: String = ""
var _demo_pos: Vector2 = Vector2.ZERO
var _demo_t: float = 0.0  # 0..1 fade timer
const DEMO_DURATION := 1.6
var _flash_cell: Vector2i = Vector2i(-1, -1)
var _flash_t: float = 0.0

# Idle hint — if the player hasn't done anything for a while, highlight a
# suggested next move so newcomers aren't stuck wondering what to do.
var _idle_t: float = 0.0
var _last_hint_t: float = -1000.0
var _suggest_cells: Array = []  # of Vector2i to pulse as a "do this" hint
var _suggest_recycle: bool = false  # when true, draw arrow to recycle zone
const IDLE_HINT_AFTER := 8.0
const HINT_RETRIGGER_EVERY := 12.0  # re-suggest while still idle

# Cells (Vector2i) that have at least one mergeable partner currently on the
# board. Recomputed when board changes. Used by the soft-lock breaker and the
# idle-hint fallback — keep this "ANY merge", don't narrow it.
var _mergeable_cells: Dictionary = {}
var _pulse_t: float = 0.0
# When a quest just finished, defer the "Level Complete" congrats modal until the
# per-invention discovery card is dismissed, so the two don't stack. -1 = none.
var _pending_level_complete: int = -1

func _ready() -> void:
	# Make sure we fill the parent (defensive — parents may be Node or Control).
	anchor_right = 1.0; anchor_bottom = 1.0
	_build_ui()
	GameState.board_changed.connect(func():
		_recompute_mergeable()
		_break_soft_lock_if_needed()
		_refresh())
	GameState.invention_discovered.connect(_on_discovered)
	set_process(true)
	Audio.play_bgm("workshop")
	# Seed a starting hand from the CURRENT LEVEL's junk pool if board empty.
	if _board_is_empty():
		_seed_starter_hand()
	_refresh_quest_ui()
	_refresh_progress()
	_recompute_mergeable()
	# Defer layout until viewport has propagated a real size to this Control.
	await get_tree().process_frame
	_layout()
	await get_tree().process_frame
	_layout()
	# Auto-open tutorial on first visit.
	if not GameState.tutorial_seen:
		_open_tutorial()

func _process(delta: float) -> void:
	_pulse_t += delta
	# Cheap redraw: only every ~3 frames (~50ms) — pulse looks smooth, CPU low.
	if int(_pulse_t * 20) != int((_pulse_t - delta) * 20):
		queue_redraw()
	# Advance demo + flash timers
	if _demo_t > 0.0:
		_demo_t = max(0.0, _demo_t - delta / DEMO_DURATION)
		queue_redraw()
	if _flash_t > 0.0:
		_flash_t = max(0.0, _flash_t - delta * 4.0)
		queue_redraw()
	# Decay the recycled-cell protect timer so the soft-lock breaker eventually
	# can use that slot again if it remains the only sensible one.
	if _recent_recycle_cell_t > 0.0:
		_recent_recycle_cell_t = max(0.0, _recent_recycle_cell_t - delta)
		if _recent_recycle_cell_t == 0.0:
			_recent_recycle_cell = Vector2i(-1, -1)
	# Pulse the deliver CTA while quest invention is on the board.
	if _deliver_btn and _deliver_btn.visible:
		var s := 0.85 + 0.15 * sin(_pulse_t * 6.0)
		_deliver_btn.modulate = Color(1, s, s * 0.7)
	# Idle-hint: trigger after IDLE_HINT_AFTER, then re-trigger every
	# HINT_RETRIGGER_EVERY while the player stays idle (in case they missed
	# the first toast or didn't act on the suggestion).
	_idle_t += delta
	if _idle_t > IDLE_HINT_AFTER and (_pulse_t - _last_hint_t) > HINT_RETRIGGER_EVERY:
		_suggest_next_action()
		_last_hint_t = _pulse_t

func _suggest_next_action() -> void:
	_suggest_cells.clear()
	_suggest_recycle = false
	# 1. Cross-combine pair on board that produces an UNDISCOVERED invention.
	# Don't suggest re-making something the player already has — that just
	# clogs the board with duplicates (e.g. 12 Fans). If the only mergeable
	# pair gives a discovered result, fall through to the "missing recipe"
	# hint at step 4.5 instead.
	var best_pair: Array = []
	var best_rid: StringName = &""
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var a: StringName = GameState.get_cell(x, y)
			if a == &"": continue
			var da: Items.ItemDef = Items.get_def(a)
			if da == null or da.tier < Items.Tier.PART: continue
			for y2 in GameState.BOARD_H:
				for x2 in GameState.BOARD_W:
					if x == x2 and y == y2: continue
					var b: StringName = GameState.get_cell(x2, y2)
					if b == &"" or a == b: continue
					var rid := Items.try_merge(a, b)
					if rid == &"": continue
					# Don't suggest re-making discovered inventions.
					if GameState.is_discovered(rid): continue
					best_pair = [Vector2i(x, y), Vector2i(x2, y2)]
					best_rid = rid
					break
				if best_rid != &"": break
			if best_rid != &"": break
		if best_rid != &"": break
	if best_rid != &"":
		_suggest_cells = best_pair
		_show_toast("Combine these to INVENT the %s!" % Items.get_def(best_rid).name, 5.0)
		queue_redraw()
		return
	# 4. Any upgrade pair (same+same WITH a defined upgrade)? Suggest one.
	# Must verify try_merge(id,id) — a cell can be in _mergeable_cells purely
	# because of a cross-combine partner (e.g. Clock+Lamp Post), but Clock+Clock
	# itself has no upgrade. Don't suggest a merge that won't work.
	for c in _mergeable_cells.keys():
		var id := GameState.get_cell(c.x, c.y)
		if Items.try_merge(id, id) == &"": continue  # no same+same upgrade
		# Find its partner.
		for c2 in _mergeable_cells.keys():
			if c == c2: continue
			if GameState.get_cell(c2.x, c2.y) == id:
				_suggest_cells = [c, c2]
				var d: Items.ItemDef = Items.get_def(id)
				_show_toast("Drag two %ss together to upgrade them." % d.name, 5.0)
				queue_redraw()
				return
	# 4.5. Concrete missing-recipe hint. The most useful guidance late-game:
	# tell the player WHICH invention they're missing and HOW to make the next
	# ingredient. Walks back through the upgrade chain so the player isn't told
	# "you need a Gearbox" without learning Gearbox = upgrade(2x Gear).
	var nudge: Array = _closest_undiscovered()
	if nudge.size() == 2:
		var target: StringName = nudge[0]
		var missing: StringName = nudge[1]
		var td: Items.ItemDef = Items.get_def(target)
		var md: Items.ItemDef = Items.get_def(missing)
		if td and md:
			var target_label := "%s %s" % [td.glyph, td.name]
			# Walk back from the missing ingredient — same logic as the quest
			# path, so the player learns "Gearbox is made by merging 2 Gears,
			# which come from 2 Cogs each" rather than just "need Gearbox".
			var lead := ""
			if _hint_for_missing(missing, target_label, lead): return
			# Walk-back produced nothing actionable — fall back to highlighting
			# the OTHER ingredient if it's on the board.
			var other_id: StringName = &""
			for key in Items.cross:
				if Items.cross[key] == target:
					var ps: PackedStringArray = String(key).split("|")
					var a := StringName(ps[0]); var b := StringName(ps[1])
					other_id = b if a == missing else a
					break
			var other_pos := _find_on_board(other_id) if other_id != &"" else Vector2i(-1, -1)
			if other_pos.x >= 0:
				_suggest_cells = [other_pos]
			_show_toast("%s %s — needs %s %s." % [
				lead, target_label, md.glyph, md.name], 7.0)
			queue_redraw()
			return
	# 5. Fallback hints based on board state.
	var board_full := GameState.find_empty_cell().x < 0
	if board_full:
		var junk_cell := _find_best_recycle_cell()
		if junk_cell.x >= 0:
			_suggest_cells = [junk_cell]
			_suggest_recycle = true
			queue_redraw()
			var jid := GameState.get_cell(junk_cell.x, junk_cell.y)
			var jd: Items.ItemDef = Items.get_def(jid)
			if jd:
				_show_toast("Board full — recycle a %s %s to free a slot." % [jd.glyph, jd.name], 6.0)
			else:
				_show_toast("Board full — recycle something to free a slot.", 6.0)
		else:
			_show_toast("Board full — merge items to free space.", 6.0)
	else:
		_show_toast("Wait for the chute to drop more junk, or merge what you have.", 5.0)

# Tries to show an actionable hint for making `missing_id`. Returns true if a
# toast was fired (and `_suggest_cells` set when there's a cell pulse to draw).
# `target_label` is a bare item reference like "🛠 Oven" or "Θ Clock". `lead`
# is the toast prefix — "💡" for the normal case, "⏭ Meanwhile," when we're
# pivoting from an unreachable quest to a level-target alternative.
func _hint_for_missing(missing_id: StringName, target_label: String, lead: String = "") -> bool:
	var md: Items.ItemDef = Items.get_def(missing_id)
	if md == null: return false
	var missing_name: String = "%s %s" % [md.glyph, md.name]
	# (a) Same-tier pair on board that upgrades into `missing_id`? Best hint —
	# we can point at the two cells the player should merge right now.
	var pair := _find_pair_path_to(missing_id)
	if pair.size() == 2:
		_suggest_cells = pair
		var src1 = GameState.get_cell(pair[0].x, pair[0].y)
		var d1: Items.ItemDef = Items.get_def(src1)
		_show_toast("%s For %s: merge these two %s %ss → %s." % [
			lead, target_label, d1.glyph, d1.name, missing_name], 6.0)
		queue_redraw()
		return true
	# (a2) Cross-combine parts on board that produce `missing_id`?
	# Handles multi-level chains: e.g. quest needs Factory (= Generator + Oven),
	# Oven is missing, but Boiler + Fuel Tank are on the board → "Combine them!"
	for key in Items.cross:
		if Items.cross[key] == missing_id:
			var cps: PackedStringArray = String(key).split("|")
			var ca := StringName(cps[0])
			var cb := StringName(cps[1])
			var cpos_a := _find_on_board(ca)
			var cpos_b := _find_on_board(cb)
			if cpos_a.x >= 0 and cpos_b.x >= 0:
				var cda: Items.ItemDef = Items.get_def(ca)
				var cdb: Items.ItemDef = Items.get_def(cb)
				_suggest_cells = [cpos_a, cpos_b]
				_show_toast("%s For %s: combine %s %s + %s %s → %s!" % [
					lead, target_label, cda.glyph, cda.name,
					cdb.glyph, cdb.name, missing_name], 6.0)
				queue_redraw()
				return true
			break
	# (b) Precursor of `missing_id` on board? Walk one step deeper so the hint
	# stays actionable ("upgrade two Cogs to get a Gear, then you need 2 Gears
	# for Gearbox"). We point at the precursor cell to anchor it visually.
	var seeds := _junk_seeds_for(missing_id)
	var seed_on_board: StringName = &""
	for s in seeds:
		if _find_on_board(s).x >= 0:
			seed_on_board = s
			break
	var board_full := GameState.find_empty_cell().x < 0
	if seed_on_board != &"":
		var sd: Items.ItemDef = Items.get_def(seed_on_board)
		var seed_label := "%s %s" % [sd.glyph, sd.name] if sd else String(seed_on_board)
		var seed_pos := _find_on_board(seed_on_board)
		if board_full:
			var any_pair := _find_any_mergeable_pair()
			if any_pair.size() == 2:
				_suggest_cells = any_pair
				_show_toast("%s Board full — merge these to free a slot." % lead, 6.0)
			else:
				var junk_cell := _find_best_recycle_cell()
				if junk_cell.x >= 0:
					_suggest_cells = [junk_cell]
					_suggest_recycle = true
					var jid := GameState.get_cell(junk_cell.x, junk_cell.y)
					var jd: Items.ItemDef = Items.get_def(jid)
					if jd:
						_show_toast("%s Board full — recycle a %s %s to free a slot." % [
							lead, jd.glyph, jd.name], 6.0)
					else:
						_show_toast("%s Board full — recycle something to free a slot." % lead, 6.0)
				else:
					_show_toast("%s Board full — recycle something to free a slot." % lead, 6.0)
			queue_redraw()
			return true
		if seed_pos.x >= 0:
			_suggest_cells = [seed_pos]
		_show_toast("%s For %s: need %s — wait for another %s, then keep merging up." % [
			lead, target_label, missing_name, seed_label], 6.0)
		queue_redraw()
		return true
	# (c) Nothing on board yet. Name the base junk to watch the chute for.
	if seeds.size() > 0:
		if board_full:
			var any_pair := _find_any_mergeable_pair()
			if any_pair.size() == 2:
				_suggest_cells = any_pair
				_show_toast("%s Board full — merge these to free a slot." % lead, 6.0)
			else:
				var junk_cell := _find_best_recycle_cell()
				if junk_cell.x >= 0:
					_suggest_cells = [junk_cell]
					_suggest_recycle = true
					var jid := GameState.get_cell(junk_cell.x, junk_cell.y)
					var jd: Items.ItemDef = Items.get_def(jid)
					if jd:
						_show_toast("%s Board full — recycle a %s %s to free a slot." % [
							lead, jd.glyph, jd.name], 6.0)
					else:
						_show_toast("%s Board full — recycle something to free a slot." % lead, 6.0)
				else:
					_show_toast("%s Board full — recycle something to free a slot." % lead, 6.0)
			queue_redraw()
			return true
		var names: Array = []
		for s in seeds:
			var sd2: Items.ItemDef = Items.get_def(s)
			if sd2: names.append("%s %s" % [sd2.glyph, sd2.name])
		if names.size() > 0:
			_show_toast("%s For %s: need %s — watch the chute for %s." % [
				lead, target_label, missing_name, ", ".join(names)], 6.0)
			return true
	return false

func _quest_parents(invention_id: StringName) -> Array:
	for key in Items.cross:
		if Items.cross[key] == invention_id:
			var ps: PackedStringArray = String(key).split("|")
			return [StringName(ps[0]), StringName(ps[1])]
	return []

# Undiscovered targets in the player's CURRENT level. The chute and the hint
# system focus here so each level is a bounded, completable challenge.
func _undiscovered_targets() -> Array:
	var out: Array = []
	var lvl_idx: int = GameState.current_level
	if lvl_idx < 0 or lvl_idx >= Items.LEVELS.size():
		return out
	var current: Dictionary = Items.LEVELS[lvl_idx]
	for t in current.targets:
		if not GameState.is_discovered(t):
			out.append(t)
	return out

# Walk back from any item id to its junk-tier roots, following BOTH the
# upgrade chain (tier 0→1→2) AND cross-combine ingredients (tier 2→3→4).
# Returns a deduped list of junk StringNames that could ultimately feed `id`.
func _junk_seeds_for(id: StringName, seen: Dictionary = {}) -> Array:
	if seen.has(id): return []
	seen[id] = true
	var d: Items.ItemDef = Items.get_def(id)
	if d == null: return []
	if d.tier == Items.Tier.JUNK: return [id]
	# Cross-combine target → recurse into both ingredients.
	for key in Items.cross:
		if Items.cross[key] == id:
			var parts: PackedStringArray = String(key).split("|")
			var out: Array = []
			for p in parts:
				for s in _junk_seeds_for(StringName(p), seen):
					if not out.has(s): out.append(s)
			if out.size() > 0: return out
	# Upgrade chain (component/part) → walk back one step.
	for src in Items.upgrade:
		if Items.upgrade[src] == id:
			return _junk_seeds_for(src, seen)
	return []

# Returns [target_id, ingredient_to_make] for the closest undiscovered target
# (one whose ingredients are MOST present on the board), or empty if there
# are no undiscovered targets.
func _closest_undiscovered() -> Array:
	var on_board: Dictionary = {}
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id != &"": on_board[id] = true
	var best_target: StringName = &""
	var best_missing: StringName = &""
	var best_score := -1
	for target in _undiscovered_targets():
		# If the target itself was recently recycled, don't push toward it.
		if _recent_recycles.has(target): continue
		for key in Items.cross:
			if Items.cross[key] != target: continue
			var parts: PackedStringArray = String(key).split("|")
			var a := StringName(parts[0])
			var b := StringName(parts[1])
			var have_a := on_board.has(a)
			var have_b := on_board.has(b)
			# Both already on board → player just needs to merge them. Pushing
			# more seeds here was the old bug ("missing = b" picked an item
			# that's actually present and wasted the chute drop).
			if have_a and have_b: continue
			# When both are missing (score=0), randomize which one the chute
			# seeds — otherwise it always picks `a` (alphabetically first),
			# building e.g. Boiler while Fuel Tank never gets started.
			var missing: StringName
			if have_a:
				missing = b
			elif have_b:
				missing = a
			else:
				missing = [a, b][randi() % 2]
			# If the missing ingredient was recently recycled, skip this target
			# so the chute doesn't immediately rebuild what the player scrapped.
			if _recent_recycles.has(missing): continue
			var score := (1 if have_a else 0) + (1 if have_b else 0)
			if score > best_score:
				best_score = score
				best_target = target
				best_missing = missing
	if best_target == &"": return []
	return [best_target, best_missing]

func _find_pair_path_to(target_id: StringName) -> Array:
	# Find a same-item pair on the board whose upgrade chain leads to target_id.
	# Walks one merge ahead — good enough for new-player hints.
	var seen: Dictionary = {}
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id == &"": continue
			if seen.has(id):
				var up := Items.try_merge(id, id)
				if up != &"" and (up == target_id or Items.try_merge(up, up) == target_id):
					return [seen[id], Vector2i(x, y)]
			else:
				seen[id] = Vector2i(x, y)
	return []

func _find_best_recycle_cell() -> Vector2i:
	# Pick the BEST cell to clear: prefer over-supplied items (most duplicates on
	# the board), then highest tier. Skip junk — clearing a surplus Fan is safer
	# advice than clearing a lone Bolt the player may still need to merge up.
	var counts: Dictionary = {}  # id -> count
	var first_pos: Dictionary = {}  # id -> Vector2i (first occurrence)
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id == &"": continue
			var d: Items.ItemDef = Items.get_def(id)
			if d == null: continue
			if d.tier <= Items.Tier.JUNK: continue  # don't suggest clearing raw junk
			counts[id] = counts.get(id, 0) + 1
			if not first_pos.has(id):
				first_pos[id] = Vector2i(x, y)
	if counts.is_empty(): return Vector2i(-1, -1)
	# Sort: most duplicates first, then highest tier.
	var best_id: StringName = &""
	var best_count := 0
	var best_tier := -1
	for id in counts:
		var c: int = counts[id]
		var d: Items.ItemDef = Items.get_def(id)
		var t: int = d.tier if d else 0
		if c > best_count or (c == best_count and t > best_tier):
			best_count = c
			best_tier = t
			best_id = id
	return first_pos.get(best_id, Vector2i(-1, -1))

func _find_any_mergeable_pair() -> Array:
	var cells: Array = []
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id != &"":
				cells.append({"pos": Vector2i(x, y), "id": id})
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			if Items.try_merge(cells[i].id, cells[j].id) != &"":
				return [cells[i].pos, cells[j].pos]
	return []

func _show_merge_demo(a: StringName, b: StringName, c: StringName, cell: Vector2i) -> void:
	var da: Items.ItemDef = Items.get_def(a)
	var db: Items.ItemDef = Items.get_def(b)
	var dc: Items.ItemDef = Items.get_def(c)
	if da == null or db == null or dc == null: return
	_demo_text = "%s + %s  →  %s" % [da.name, db.name, dc.name]
	_demo_pos = _cell_origin(cell.x, cell.y) + Vector2(_cell_size, _cell_size) * 0.5
	_demo_t = 1.0
	_flash_cell = cell
	_flash_t = 1.0
	queue_redraw()

func _recompute_mergeable() -> void:
	_mergeable_cells.clear()
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var a: StringName = GameState.get_cell(x, y)
			if a == &"": continue
			# Look for ANY other cell that produces a result with this one.
			for y2 in GameState.BOARD_H:
				for x2 in GameState.BOARD_W:
					if x == x2 and y == y2: continue
					var b: StringName = GameState.get_cell(x2, y2)
					if b == &"": continue
					if Items.try_merge(a, b) != &"":
						_mergeable_cells[Vector2i(x, y)] = true
						break
				if _mergeable_cells.has(Vector2i(x, y)): break

func _build_ui() -> void:
	# NOTE: do NOT add a background ColorRect here — child CanvasItems draw on
	# top of the parent's _draw(), so a full-screen ColorRect child would cover
	# the board. The viewport clear color (project.godot) handles the bg.

	# No top bar — the old magnifier + "N/N" discovery counter was removed (it read
	# as a search box that doesn't exist, and the Recipes tab already opens the
	# book + the dot strip conveys overall progress). safe_top is still computed
	# for the (now-hidden) quest label's anchor.
	var safe_top: float = 50.0
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0:
		safe_top = max(safe_top, float(safe.position.y))

	# Bottom tab bar — iOS-style: panel background + 3 equal-width tabs with
	# icon + label stacked. Matches the village screen.
	_tab_bar_bg = PanelContainer.new()
	var tab_sb := StyleBoxFlat.new()
	tab_sb.bg_color = Color(0.10, 0.07, 0.05)
	tab_sb.border_color = Color(0.50, 0.38, 0.22)
	tab_sb.border_width_top = 2
	_tab_bar_bg.add_theme_stylebox_override("panel", tab_sb)
	_tab_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tab_bar_bg)

	_back_btn = _make_tab_button("arrow_left", "Village", false,
		func(): go_village.emit())
	_back_btn.tooltip_text = "Back to village"
	add_child(_back_btn)

	_book_btn = _make_tab_button("book", "Recipes", true, _open_book)
	_book_btn.tooltip_text = "Recipes — all 25 inventions; undiscovered show recipe."
	add_child(_book_btn)

	_help_btn = _make_tab_button("?", "Help", false, _open_tutorial)
	_help_btn.tooltip_text = "How to play (recipes are under the Recipes tab, not here)"
	add_child(_help_btn)

	# Quest label — sits below the top bar (which now respects safe-area inset).
	_quest_label = Label.new()
	_quest_label.position = Vector2(12, safe_top + 52)
	_quest_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_quest_label.add_theme_font_size_override("font_size", 17)
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_quest_label)

	# Goal banner: chunky, always-visible progress bar with the label centered
	# OVER the fill. Replaces the old thin sliver that was easy to overlook.
	_goal_banner = Control.new()
	add_child(_goal_banner)
	# Track: warm dark with a bright border so it reads as a "bar" against the
	# brown workbench background. Drawn via a Panel under the fill+label.
	var track_panel := PanelContainer.new()
	track_panel.anchor_right = 1.0; track_panel.anchor_bottom = 1.0
	track_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_track_sb = StyleBoxFlat.new()
	_goal_track_sb.bg_color = Color(0.30, 0.22, 0.12, 1.0)
	_goal_track_sb.border_color = Color(0.85, 0.65, 0.30, 1.0)
	_goal_track_sb.set_border_width_all(2)
	_goal_track_sb.set_corner_radius_all(6)
	track_panel.add_theme_stylebox_override("panel", _goal_track_sb)
	_goal_banner.add_child(track_panel)
	_goal_track = ColorRect.new()
	_goal_track.color = Color(0, 0, 0, 0)  # invisible — track_panel paints the bg
	_goal_banner.add_child(_goal_track)
	_goal_fill = ColorRect.new()
	_goal_fill.color = Color(0.40, 0.75, 0.35, 1.0)
	_goal_banner.add_child(_goal_fill)
	_goal_label = Label.new()
	_goal_label.add_theme_font_size_override("font_size", 20)
	_goal_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_goal_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_goal_label.add_theme_constant_override("shadow_offset_x", 1)
	_goal_label.add_theme_constant_override("shadow_offset_y", 1)
	_goal_label.add_theme_constant_override("shadow_outline_size", 3)
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal_banner.add_child(_goal_label)

	# Hint label
	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	add_child(_hint_label)

	# Deliver button (appears when quest's required invention is on the board).
	# Styled as a bright CTA so a new player can't miss it.
	_deliver_btn = Button.new()
	_deliver_btn.text = ""
	# Truck icon + label in a centered row — 🚚 tofus on iOS, so it's drawn.
	var deliver_row := HBoxContainer.new()
	deliver_row.alignment = BoxContainer.ALIGNMENT_CENTER
	deliver_row.add_theme_constant_override("separation", 8)
	deliver_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	deliver_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var deliver_ink := Color(0.12, 0.06, 0.02)
	var truck := UIIcon.new("truck", deliver_ink)
	truck.custom_minimum_size = Vector2(34, 26)
	deliver_row.add_child(truck)
	var deliver_lbl := Label.new()
	deliver_lbl.text = "Deliver"
	deliver_lbl.add_theme_font_size_override("font_size", 20)
	deliver_lbl.add_theme_color_override("font_color", deliver_ink)
	deliver_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deliver_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deliver_row.add_child(deliver_lbl)
	_deliver_btn.add_child(deliver_row)
	var cta := StyleBoxFlat.new()
	cta.bg_color = Color(1.0, 0.78, 0.30)
	cta.border_color = Color(1.0, 0.95, 0.55)
	cta.set_border_width_all(3)
	cta.set_corner_radius_all(10)
	_deliver_btn.add_theme_stylebox_override("normal", cta)
	_deliver_btn.add_theme_stylebox_override("hover", cta)
	_deliver_btn.add_theme_stylebox_override("pressed", cta)
	_deliver_btn.pressed.connect(_deliver)
	_deliver_btn.visible = false
	add_child(_deliver_btn)

	# Board container
	_board_node = Control.new()
	add_child(_board_node)

	# Toast — a prominent banner that pops up over the board for 3s when
	# something important happens (invention discovered, failed merge, etc).
	_toast = PanelContainer.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var toast_sb := StyleBoxFlat.new()
	toast_sb.bg_color = Color(0.18, 0.12, 0.06, 0.95)
	toast_sb.border_color = Color(1.0, 0.78, 0.30)
	toast_sb.set_border_width_all(3)
	toast_sb.set_corner_radius_all(10)
	toast_sb.content_margin_left = 14; toast_sb.content_margin_right = 14
	toast_sb.content_margin_top = 10;  toast_sb.content_margin_bottom = 10
	_toast.add_theme_stylebox_override("panel", toast_sb)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 20)
	_toast_label.add_theme_color_override("font_color", Color(1, 0.95, 0.70))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_child(_toast_label)
	add_child(_toast)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func():
		_toast.visible = false
		# Restore the right banner for the current quest state.
		_refresh_quest_ui())
	add_child(_toast_timer)

	# Recycle panel — sits below the board, above the discoveries strip.
	# Drag any item onto it to clear its slot. Mouse-filter IGNORE so it
	# never blocks board input; hit-testing is manual via _recycle_rect.
	# Recycle zone is drawn entirely in _draw() — bin icon + text.
	# The panel is invisible; it only exists for layout sizing / _recycle_rect.
	_recycle_panel = PanelContainer.new()
	_recycle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0)
	rsb.border_color = Color(0, 0, 0, 0)
	rsb.set_border_width_all(0)
	_recycle_panel.add_theme_stylebox_override("panel", rsb)
	_recycle_label = Label.new()  # keep ref so var decl doesn't break
	_recycle_label.visible = false
	_recycle_panel.add_child(_recycle_label)
	add_child(_recycle_panel)

	# Inline discoveries: ONLY the current level's 5 targets, big cells with
	# glyph + name. (Dot strip + level-title text removed — both were redundant
	# with the top goal banner and with the cards themselves; Qi found the region
	# too cluttered. Just the 5 target cards remain.)
	_discoveries_panel = Control.new()
	_discoveries_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_discoveries_panel)
	_cur_grid = GridContainer.new()
	_cur_grid.columns = 5
	_cur_grid.add_theme_constant_override("h_separation", 8)
	_discoveries_panel.add_child(_cur_grid)
	# 5 cells; each holds a glyph label + a name label. Restyled per refresh.
	# Tapping a cell opens the Book scrolled+highlighted to THAT entry — so a
	# player who can't read the silhouette can jump straight to its recipe.
	for i in 5:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		cell.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(v)
		var glyph_lbl := Label.new()
		glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph_lbl.add_theme_font_size_override("font_size", 32)
		glyph_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(glyph_lbl)
		var name_lbl := Label.new()
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_lbl)
		_cur_grid.add_child(cell)
		_cur_cells.append(cell)
		cell.gui_input.connect(_on_discovery_cell_input.bind(i))
	# Tap empty space on the panel → open the Book at the top (no highlight).
	_discoveries_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed: _open_book()
		elif ev is InputEventScreenTouch and ev.pressed: _open_book())

	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var w := size.x
	var h := size.y
	# Top bar starts at the safe-area inset; add room for it + quest + goal banner.
	var safe_top: float = 50.0
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0:
		safe_top = max(safe_top, float(safe.position.y))
	# Bottom safe-area inset (home-indicator strip on Face-ID iPhones).
	var safe_bot: float = 16.0
	if safe.size.x > 0:
		var inset_bot := float(get_viewport_rect().size.y - (safe.position.y + safe.size.y))
		safe_bot = max(safe_bot, inset_bot)
	var top_h: float = safe_top + 76.0  # goal banner (~40) + pad (top bar removed)
	var tab_h: float = 88.0  # matches village.gd's tab bar height
	# Bar absorbs the home-indicator inset by extending tab_h with safe_bot.
	var bottom_h: float = 270.0 + tab_h + safe_bot + 8.0
	var avail_w := w - 16
	var avail_h := h - top_h - bottom_h
	_cell_size = min(avail_w / GameState.BOARD_W, avail_h / GameState.BOARD_H) - CELL_PAD
	var board_w := _cell_size * GameState.BOARD_W + CELL_PAD * (GameState.BOARD_W - 1)
	var board_h := _cell_size * GameState.BOARD_H + CELL_PAD * (GameState.BOARD_H - 1)
	var ox := (w - board_w) / 2.0
	var oy := top_h
	_board_rect = Rect2(ox, oy, board_w, board_h)
	# Goal banner just above the board — tall, full-width, label centered inside.
	# Recipe banner shares the same slot (only one of them shows at a time:
	# goal banner when no quest, recipe banner when a quest is active).
	var gb_h: float = 40.0
	_goal_banner.position = Vector2(12, oy - gb_h - 8)
	_goal_banner.size = Vector2(w - 24, gb_h)
	_goal_track.position = Vector2.ZERO
	_goal_track.size = _goal_banner.size
	_goal_label.position = Vector2.ZERO
	_goal_label.size = _goal_banner.size
	_goal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_refresh_goal_bar()
	_hint_label.position = Vector2(12, oy + board_h + 8)
	_hint_label.size = Vector2(w - 24, 24)
	# Toast sits just under the top bar, ABOVE the board — impossible to miss.
	_toast.position = Vector2(12, top_h - 36)
	_toast.size = Vector2(w - 24, 60)
	# Deliver = full-width banner directly under the board: impossible to miss.
	_deliver_btn.position = Vector2(12, oy + board_h + 36)
	_deliver_btn.size = Vector2(w - 24, 60)
	# Recycle panel + discoveries stack in the space between the board and the
	# tab bar. The board is width-constrained on tall phones, so that space has
	# slack — distribute it as three equal gaps (under board / between panels /
	# above tab bar) so nothing floats. Re-aligned after the discoveries panel
	# shrank to a single card row.
	var recycle_h: float = 86.0
	var disc_h: float = 96.0  # one row of big cells (dots + title rows removed)
	var stack_top: float = oy + board_h
	var stack_bot: float = h - (tab_h + safe_bot)  # tab bar top edge
	var gap: float = max(8.0, (stack_bot - stack_top - recycle_h - disc_h) / 3.0)
	var rec_y: float = stack_top + gap
	_recycle_panel.position = Vector2(12, rec_y)
	_recycle_panel.size = Vector2(w - 24, recycle_h)
	_recycle_rect = Rect2(_recycle_panel.position, _recycle_panel.size)
	# Discoveries: current level only — just the 5 target cards now.
	_discoveries_panel.position = Vector2(12, rec_y + recycle_h + gap)
	_discoveries_panel.size = Vector2(w - 24, disc_h)
	var pw: float = w - 24
	_cur_grid.position = Vector2(0, 0)
	_cur_grid.size = Vector2(pw, disc_h)
	var cell_w: float = (pw - 32) / 5.0  # 5 cols, 4 gaps of 8
	for c in _cur_grid.get_children():
		c.custom_minimum_size = Vector2(cell_w, disc_h)
	# Bottom tab bar — iOS-style: single bar flush to the screen edge, three
	# equal-width tabs. The bar height absorbs the home-indicator inset so
	# the panel paints all the way to the bottom of the device.
	var bar_h: float = tab_h + safe_bot
	var bar_y: float = h - bar_h
	_tab_bar_bg.position = Vector2(0, bar_y)
	_tab_bar_bg.size = Vector2(w, bar_h)
	var tab_w: float = w / 3.0
	_back_btn.position = Vector2(0, bar_y)
	_back_btn.size = Vector2(tab_w, tab_h)
	_book_btn.position = Vector2(tab_w, bar_y)
	_book_btn.size = Vector2(tab_w, tab_h)
	_help_btn.position = Vector2(tab_w * 2, bar_y)
	_help_btn.size = Vector2(tab_w, tab_h)
	_refresh_discoveries()
	_refresh()

func _cell_origin(x: int, y: int) -> Vector2:
	return _board_rect.position + Vector2(
		x * (_cell_size + CELL_PAD),
		y * (_cell_size + CELL_PAD))

func _cell_at_point(p: Vector2) -> Vector2i:
	if not _board_rect.grow(CELL_PAD).has_point(p): return Vector2i(-1, -1)
	var rel := p - _board_rect.position
	var x := int(rel.x / (_cell_size + CELL_PAD))
	var y := int(rel.y / (_cell_size + CELL_PAD))
	if x < 0 or x >= GameState.BOARD_W or y < 0 or y >= GameState.BOARD_H:
		return Vector2i(-1, -1)
	return Vector2i(x, y)

func _board_is_empty() -> bool:
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			if GameState.get_cell(x, y) != &"": return false
	return true

func _refresh() -> void:
	queue_redraw()
	_refresh_deliver_button()
	_refresh_goal_bar()  # update NPC ingredient dots live

func _draw() -> void:
	# Board background
	draw_rect(_board_rect.grow(CELL_PAD * 2), Color(0.12, 0.08, 0.05), true)
	# Pre-compute drag source id if dragging (for highlight logic)
	var dragging := _dragging_cell.x >= 0
	var src_id: StringName = &""
	if dragging:
		src_id = GameState.get_cell(_dragging_cell.x, _dragging_cell.y)
	# Cells
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var origin := _cell_origin(x, y)
			var cell_rect := Rect2(origin, Vector2(_cell_size, _cell_size))
			draw_rect(cell_rect, Color(0.28, 0.20, 0.12), true)
			draw_rect(cell_rect, Color(0.10, 0.06, 0.03), false, 1.0)
			var id: StringName = GameState.get_cell(x, y)
			var is_src := (x == _dragging_cell.x and y == _dragging_cell.y)
			if id != &"" and not is_src:
				_draw_item(id, cell_rect)
			# Highlight ring while dragging so the player can SEE what works.
			if dragging and not is_src:
				var ring := _highlight_color(src_id, id)
				if ring.a > 0:
					draw_rect(cell_rect.grow(-2), ring, false, 3.0)
	# --- Recycle bin zone (always drawn) ---
	# While dragging an item, the bin shows "Clear slot" INSTEAD of the static
	# label so the two don't overlap.
	var _dragging_item := dragging and src_id != &"" and _recycle_rect.size.x > 0
	if _recycle_rect.size.x > 0:
		_draw_recycle_bin(_dragging_item)
	# Recycle drop hint — outline the bin icon while dragging anything.
	if _dragging_item and _recycle_icon_rect.size.x > 0:
		var hover := _recycle_rect.has_point(_drag_pos)
		var glow: float = 0.65 + 0.30 * sin(_pulse_t * 4.0)
		var col := Color(0.55, 0.95, 0.45, 1.0 if hover else glow)
		draw_rect(_recycle_icon_rect.grow(3), col, false, 4.0)
	# Drag overlay
	if dragging and src_id != &"":
		var r := Rect2(_drag_pos - Vector2(_cell_size, _cell_size) * 0.5, Vector2(_cell_size, _cell_size))
		_draw_item(src_id, r, 1.15)
	# Idle-hint: DIM the entire board, then spotlight the suggested cells with
	# a thick bright ring + a connecting arrow. Impossible to miss.
	if _suggest_cells.size() > 0 and not dragging:
		# Dim everyone except suggested cells.
		var dim := Color(0, 0, 0, 0.55)
		for y in GameState.BOARD_H:
			for x in GameState.BOARD_W:
				var is_suggested := false
				for sc in _suggest_cells:
					if sc.x == x and sc.y == y: is_suggested = true; break
				if not is_suggested:
					draw_rect(Rect2(_cell_origin(x, y),
						Vector2(_cell_size, _cell_size)), dim, true)
		# Glowing ring on the suggested cells.
		var pulse := 0.70 + 0.30 * sin(_pulse_t * 4.5)
		for c in _suggest_cells:
			var sr := Rect2(_cell_origin(c.x, c.y),
				Vector2(_cell_size, _cell_size))
			# Outer halo
			draw_rect(sr.grow(6), Color(1.0, 0.80, 0.20, pulse * 0.55), false, 8.0)
			# Sharp inner ring
			draw_rect(sr.grow(2), Color(1.0, 0.95, 0.45, pulse), false, 5.0)
		# Animated arrow between the two suggested cells (for merge pairs).
		if _suggest_cells.size() == 2:
			var c0: Vector2i = _suggest_cells[0]
			var c1: Vector2i = _suggest_cells[1]
			var p0 := _cell_origin(c0.x, c0.y) + Vector2(_cell_size, _cell_size) * 0.5
			var p1 := _cell_origin(c1.x, c1.y) + Vector2(_cell_size, _cell_size) * 0.5
			# Animate stroke from p0 → p1 with a moving dot.
			var t: float = fmod(_pulse_t, 1.2) / 1.2
			var arrow_col := Color(1.0, 0.90, 0.40, pulse)
			draw_line(p0, p1, Color(arrow_col.r, arrow_col.g, arrow_col.b, 0.5), 4.0)
			# Moving dot
			var dot_pos := p0.lerp(p1, t)
			draw_circle(dot_pos, 9.0, arrow_col)
			# Arrow head at p1
			var dir := (p1 - p0).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var head_base := p1 - dir * 16.0
			var head_pts: PackedVector2Array = [
				p1 - dir * 4.0,
				head_base + perp * 8.0,
				head_base - perp * 8.0,
			]
			draw_polygon(head_pts, [arrow_col, arrow_col, arrow_col])
		# Animated arrow from suggested cell → recycle bin icon (NOT the panel
		# center — the bin lives in a square box on the left of the panel).
		if _suggest_recycle and _suggest_cells.size() == 1 and _recycle_icon_rect.size.x > 0:
			var rc: Vector2i = _suggest_cells[0]
			var p0 := _cell_origin(rc.x, rc.y) + Vector2(_cell_size, _cell_size) * 0.5
			var p1 := _recycle_icon_rect.get_center()
			var t: float = fmod(_pulse_t, 1.2) / 1.2
			var rcol := Color(0.55, 0.95, 0.45, pulse)  # green — matches recycle color
			draw_line(p0, p1, Color(rcol.r, rcol.g, rcol.b, 0.4), 4.0)
			var dot_pos := p0.lerp(p1, t)
			draw_circle(dot_pos, 9.0, rcol)
			# Arrow head at p1
			var dir := (p1 - p0).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var head_base := p1 - dir * 16.0
			var rhead_pts: PackedVector2Array = [
				p1 - dir * 4.0,
				head_base + perp * 8.0,
				head_base - perp * 8.0,
			]
			draw_polygon(rhead_pts, [rcol, rcol, rcol])
			# Glow ring around the bin box itself (tight, not the whole panel)
			draw_rect(_recycle_icon_rect.grow(4), Color(0.55, 0.95, 0.45, pulse * 0.7), false, 4.0)
			draw_rect(_recycle_icon_rect.grow(1), Color(0.55, 0.95, 0.45, pulse), false, 2.5)
	# Merge flash — bright burst on the destination cell that fades fast.
	if _flash_t > 0.0 and _flash_cell.x >= 0:
		var fr := Rect2(_cell_origin(_flash_cell.x, _flash_cell.y),
			Vector2(_cell_size, _cell_size))
		draw_rect(fr, Color(1.0, 0.95, 0.55, _flash_t * 0.55), true)
		draw_rect(fr.grow(3), Color(1.0, 0.85, 0.30, _flash_t * 0.9), false, 4.0)
	# Demo "A + B → C" caption floating above the merge cell.
	if _demo_t > 0.0 and _demo_text != "":
		var font := ThemeDB.fallback_font
		var fs := 18
		var sz := font.get_string_size(_demo_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		# Drift upward as it fades.
		var rise := (1.0 - _demo_t) * 26.0
		var origin := _demo_pos + Vector2(-sz.x * 0.5 - 8, -_cell_size * 0.5 - 14 - rise)
		var bg_rect := Rect2(origin, Vector2(sz.x + 16, sz.y + 10))
		# Keep the caption on-screen even at the board edges.
		if bg_rect.position.x < _board_rect.position.x:
			bg_rect.position.x = _board_rect.position.x + 2
		if bg_rect.end.x > _board_rect.end.x:
			bg_rect.position.x = _board_rect.end.x - bg_rect.size.x - 2
		draw_rect(bg_rect, Color(0.18, 0.12, 0.06, 0.92 * _demo_t), true)
		draw_rect(bg_rect, Color(1.0, 0.85, 0.40, _demo_t), false, 2.0)
		draw_string(font, bg_rect.position + Vector2(8, sz.y + 3),
			_demo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 0.95, 0.70, _demo_t))

func _draw_recycle_bin(is_dragging: bool) -> void:
	# While dragging, replace the static "RECYCLE / drag items here" label with
	# "Clear slot" so the two don't overlap.
	var r := _recycle_rect
	var base_col := Color(0.60, 0.90, 0.50)
	var dim_col := Color(0.55, 0.78, 0.45, 0.95)
	var col := base_col if is_dragging else dim_col
	# --- Square box on the left for the bin icon ---
	var box_pad := 6.0
	var box_size := r.size.y - box_pad * 2.0  # square, fills panel height
	var box_x := r.position.x + box_pad
	var box_y := r.position.y + box_pad
	var box := Rect2(box_x, box_y, box_size, box_size)
	_recycle_icon_rect = box  # publish for hint arrow + glow targeting
	# Box background (slightly darker than panel) + green border
	var box_bg := Color(0.10, 0.14, 0.08, 0.95)
	draw_rect(box, box_bg, true)
	draw_rect(box, Color(col.r * 0.7, col.g * 0.75, col.b * 0.65, 1.0), false, 2.0)
	# --- Bin icon inside the square (properly proportioned, taller than wide) ---
	var bx := box.position.x + box.size.x * 0.5  # center x
	var inner_top := box.position.y + 6.0
	var inner_bot := box.position.y + box.size.y - 4.0
	var bin_h := inner_bot - inner_top  # ~66
	# Vertical layout: handle (10) + lid (6) + body (rest)
	var handle_h := 9.0
	var lid_h := 5.0
	var handle_top := inner_top
	var lid_top := handle_top + handle_h
	var body_top := lid_top + lid_h
	var body_bot := inner_bot
	# Horizontal proportions (bin width ~75% of box)
	var body_w_top := box.size.x * 0.62
	var body_w_bot := body_w_top - 8.0  # taper
	var lid_w := body_w_top + 10.0  # lid sticks out slightly
	# --- Lid (filled, with shadow stripe under it for depth) ---
	# Shadow stripe under lid
	draw_rect(Rect2(bx - body_w_top * 0.5, body_top, body_w_top, 3),
		Color(0, 0, 0, 0.35), true)
	# The lid itself
	var lid_rect := Rect2(bx - lid_w * 0.5, lid_top, lid_w, lid_h)
	draw_rect(lid_rect, col, true)
	# Subtle highlight on top of lid
	draw_rect(Rect2(lid_rect.position.x, lid_rect.position.y, lid_rect.size.x, 1),
		Color(1, 1, 1, 0.25), true)
	# --- Handle (arch on top of lid) ---
	var hw := 14.0
	var hx := bx - hw * 0.5
	var hy := handle_top + 1.0
	draw_line(Vector2(hx, lid_top), Vector2(hx, hy + 2), col, 2.5)
	draw_line(Vector2(hx, hy + 2), Vector2(hx + hw, hy + 2), col, 2.5)
	draw_line(Vector2(hx + hw, hy + 2), Vector2(hx + hw, lid_top), col, 2.5)
	# --- Body (tapered trapezoid, taller than wide) ---
	var body_fill := Color(col.r * 0.55, col.g * 0.62, col.b * 0.50, 0.45)
	var body_pts := PackedVector2Array([
		Vector2(bx - body_w_top * 0.5, body_top),
		Vector2(bx + body_w_top * 0.5, body_top),
		Vector2(bx + body_w_bot * 0.5, body_bot),
		Vector2(bx - body_w_bot * 0.5, body_bot),
	])
	draw_polygon(body_pts, [body_fill])
	draw_polyline(PackedVector2Array([body_pts[0], body_pts[1], body_pts[2], body_pts[3], body_pts[0]]), col, 2.0)
	# --- Vertical ridges (3 prominent ones, evenly spaced) ---
	var ridge_col := Color(col.r, col.g, col.b, 0.55)
	for i in 3:
		var t: float = (i + 1.0) / 4.0
		var rx_top := lerpf(bx - body_w_top * 0.5 + 6.0, bx + body_w_top * 0.5 - 6.0, t)
		var rx_bot := lerpf(bx - body_w_bot * 0.5 + 5.0, bx + body_w_bot * 0.5 - 5.0, t)
		draw_line(Vector2(rx_top, body_top + 5), Vector2(rx_bot, body_bot - 4), ridge_col, 1.5)
	# --- Label block to the right of the box ---
	var font := ThemeDB.fallback_font
	var text_x := box.position.x + box.size.x + 14.0
	var text_cy := r.position.y + r.size.y * 0.5
	if is_dragging:
		# Dragging an item → show "Clear slot" INSTEAD of the static label
		# (avoids overlapping "RECYCLE" and the drop prompt on top of each other).
		var pre := "Clear slot"
		var pre_fsz := 22
		var glow: float = 0.65 + 0.30 * sin(_pulse_t * 4.0)
		var pcol := Color(0.55, 0.95, 0.45, 1.0 if _recycle_rect.has_point(_drag_pos) else glow)
		draw_string(font, Vector2(text_x, text_cy + 6),
			pre, HORIZONTAL_ALIGNMENT_LEFT, -1, pre_fsz, pcol)
	else:
		# Default: "RECYCLE" + subtitle
		var label_txt := "RECYCLE"
		var label_fsz := 22
		var label_sz := font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fsz)
		draw_string(font, Vector2(text_x, text_cy + 2),
			label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fsz, col)
		var sub_txt := "drag items here to clear a slot"
		var sub_fsz := 16
		draw_string(font, Vector2(text_x, text_cy + label_sz.y * 0.85 + 4),
			sub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fsz, Color(col.r, col.g, col.b, 0.70))

func _highlight_color(src_id: StringName, dst_id: StringName) -> Color:
	# Green  = produces an item (upgrade or invention)
	# Blue   = empty cell (move only)
	# Red    = non-empty, no recipe — would bounce back
	if dst_id == &"":
		return Color(0.30, 0.65, 0.95, 0.85)  # blue: move target
	var result := Items.try_merge(src_id, dst_id)
	if result != &"":
		return Color(0.30, 0.85, 0.40, 0.95)  # green: valid merge
	# Same+same with no upgrade → dropping clears the duplicate (cyan ring).
	if src_id == dst_id:
		return Color(0.45, 0.85, 0.95, 0.85)  # cyan: clear duplicate
	return Color(0.85, 0.30, 0.30, 0.70)  # red: invalid pair

const TIER_COLORS := [
	Color(0.55, 0.50, 0.42),  # T0 Junk — muted
	Color(0.75, 0.65, 0.45),  # T1 Component — warm
	Color(0.90, 0.78, 0.45),  # T2 Part — brass
	Color(1.00, 0.90, 0.40),  # T3 Invention — gold
	Color(1.00, 0.65, 0.25),  # T4 Masterwork — fire
]
const TIER_NAMES := ["Junk", "Crafted", "Part", "Invent", "Master"]

# Warm neutral tile backgrounds by tier — cohesive base, color comes from glyph.
const TILE_BG := [
	Color(0.28, 0.24, 0.18),   # Junk — dark warm brown
	Color(0.32, 0.27, 0.19),   # Crafted — slightly lighter
	Color(0.36, 0.30, 0.20),   # Part — warmer, richer
	Color(0.22, 0.18, 0.12),   # Invention — darker, premium feel
	Color(0.20, 0.16, 0.10),   # Masterwork — deepest, luxurious
]

func _draw_item(id: StringName, rect: Rect2, scale: float = 1.0) -> void:
	var d: Items.ItemDef = Items.get_def(id)
	if d == null: return
	var pad := 4.0
	var inner := Rect2(rect.position + Vector2(pad, pad), rect.size - Vector2(pad, pad) * 2)
	# Warm neutral background — same family across all tiles for visual calm.
	var bg: Color = TILE_BG[d.tier] if d.tier < TILE_BG.size() else TILE_BG[0]
	draw_rect(inner, bg, true)
	# Subtle top highlight for depth
	var hi := Rect2(inner.position, Vector2(inner.size.x, 2))
	draw_rect(hi, Color(1, 1, 1, 0.08), true)
	# Border — item color tint for Invention/Masterwork, subtle for lower tiers
	var thickness: float = 1.5
	var border_color: Color
	if d.tier >= Items.Tier.INVENTION:
		thickness = 2.5
		border_color = d.color.lightened(0.15)
		border_color.a = 0.85
	else:
		border_color = Color(0.55, 0.45, 0.30, 0.50)
	draw_rect(inner, border_color, false, thickness)
	var font := ThemeDB.fallback_font

	# Slim tier band at the BOTTOM
	var band_h: float = max(12.0, inner.size.y * 0.14)
	var band_rect := Rect2(
		inner.position + Vector2(0, inner.size.y - band_h),
		Vector2(inner.size.x, band_h))
	# Invention/masterwork: colored band accent; lower tiers: subtle dark band.
	var band_color: Color
	if d.tier >= Items.Tier.INVENTION:
		band_color = d.color.darkened(0.45)
		band_color.a = 0.70
	else:
		band_color = Color(0, 0, 0, 0.25)
	draw_rect(band_rect, band_color, true)
	var tier_fs: int = max(9, int(band_h * 0.62))
	var tier_text: String = TIER_NAMES[d.tier].to_upper()
	var ts := font.get_string_size(tier_text, HORIZONTAL_ALIGNMENT_CENTER, -1, tier_fs)
	var tier_ink := Color(0.75, 0.65, 0.45, 0.85) if d.tier < Items.Tier.INVENTION \
		else Color(1, 1, 1, 0.85)
	draw_string(font,
		band_rect.position + Vector2((band_rect.size.x - ts.x) * 0.5,
			(band_rect.size.y + ts.y * 0.7) * 0.5),
		tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tier_fs, tier_ink)

	# HERO glyph — item's own color, big, centered. THIS is where color lives.
	var name_fs: int = max(10, int(inner.size.y * 0.13))
	var glyph_area := Rect2(
		inner.position + Vector2(2, 2),
		Vector2(inner.size.x - 4, inner.size.y - band_h - name_fs - 6))
	var glyph_fs: int = int(glyph_area.size.y * 0.85 * scale)
	glyph_fs = clamp(glyph_fs, 16, 80)
	var gsz := font.get_string_size(d.glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_fs)
	var gpos := glyph_area.position + Vector2(
		(glyph_area.size.x - gsz.x) * 0.5,
		(glyph_area.size.y + gsz.y * 0.62) * 0.5)
	# Dark shadow for legibility, then the vibrant colored glyph.
	var glyph_ink: Color = d.color.lightened(0.35)
	glyph_ink.a = 0.95
	draw_string(font, gpos + Vector2(1, 2), d.glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_fs, Color(0, 0, 0, 0.40))
	draw_string(font, gpos, d.glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_fs, glyph_ink)

	# Name caption — warm light text, readable on the neutral bg.
	var name_ink := Color(0.90, 0.82, 0.60) if d.tier < Items.Tier.INVENTION \
		else d.color.lightened(0.55)
	var nsz := font.get_string_size(d.name, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs)
	while nsz.x > inner.size.x - 6 and name_fs > 8:
		name_fs -= 1
		nsz = font.get_string_size(d.name, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs)
	draw_string(font,
		Vector2(inner.position.x + (inner.size.x - nsz.x) * 0.5,
			inner.position.y + inner.size.y - band_h - 3),
		d.name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, name_ink)

func _draw_item_name(font: Font, name: String, area: Rect2, scale: float) -> void:
	# Pick lines: split a 2-word name across two lines.
	var lines: PackedStringArray
	var sp := name.find(" ")
	if sp > 0 and sp < name.length() - 1:
		lines = [name.substr(0, sp), name.substr(sp + 1)]
	else:
		lines = [name]
	# Auto-fit font size so the widest line fits in the area.
	var fs: int = int(area.size.y / lines.size() * 0.75 * scale)
	fs = clamp(fs, 10, 40)
	while fs > 10:
		var widest := 0.0
		for ln in lines:
			widest = max(widest, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x)
		if widest <= area.size.x - 4: break
		fs -= 1
	var line_h := fs * 1.05
	var block_h := line_h * lines.size()
	var y0 := area.position.y + (area.size.y - block_h) * 0.5 + line_h * 0.8
	for i in lines.size():
		var ln: String = lines[i]
		var sz := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var pos := Vector2(area.position.x + (area.size.x - sz.x) * 0.5, y0 + i * line_h)
		draw_string(font, pos, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.90, 0.82, 0.60))

func _gui_input(event: InputEvent) -> void:
	# Reset idle clock only on intentional input. Plain hover-motion would
	# otherwise pin _idle_t to 0 on desktop and the idle hint would never
	# fire (especially noticeable on a full board where the player is staring
	# at the screen wondering what to do).
	if event is InputEventMouseButton:
		_reset_idle()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin_drag(event.position)
			else: _end_drag(event.position)
	elif event is InputEventScreenTouch:
		_reset_idle()
		if event.pressed: _begin_drag(event.position)
		else: _end_drag(event.position)
	elif event is InputEventMouseMotion and _dragging_cell.x >= 0:
		_reset_idle()
		_drag_pos = event.position
		queue_redraw()
	elif event is InputEventScreenDrag and _dragging_cell.x >= 0:
		_reset_idle()
		_drag_pos = event.position
		queue_redraw()

func _reset_idle() -> void:
	_idle_t = 0.0
	_last_hint_t = _pulse_t  # don't refire immediately after input
	if _suggest_cells.size() > 0:
		_suggest_cells.clear()
		queue_redraw()

func _debug_force_drag(src: Vector2i, hover: Vector2) -> void:
	# Used by the screenshot harness to render a drag-in-progress for verification.
	_dragging_cell = src
	_drag_pos = hover
	queue_redraw()

func _begin_drag(p: Vector2) -> void:
	var cell := _cell_at_point(p)
	if cell.x < 0: return
	if GameState.get_cell(cell.x, cell.y) == &"": return
	_dragging_cell = cell
	_drag_pos = p
	_drag_offset = p - _cell_origin(cell.x, cell.y)
	queue_redraw()

func _end_drag(p: Vector2) -> void:
	if _dragging_cell.x < 0: return
	var src := _dragging_cell
	_dragging_cell = Vector2i(-1, -1)
	# Recycle drop — dragging onto the recycle panel clears the item to free a slot.
	# Checked BEFORE board cells so it works even when the panel overlaps cells.
	if _recycle_rect.has_point(p):
		var rid := GameState.get_cell(src.x, src.y)
		var rdef: Items.ItemDef = Items.get_def(rid)
		if rdef:
			GameState.set_cell(src.x, src.y, &"")
			_show_toast("Cleared %s" % rdef.name, 2.0)
			Audio.play_sfx("place")
			# Delay the chute so the freed slot stays open long enough to use.
			_chute_timer.start(4.0)
			# Blacklist the recycled item so the chute and soft-lock breaker
			# stop pushing seeds toward it for ~10s. Otherwise the player keeps
			# seeing the same item reappear at the same spot.
			_recent_recycles[rid] = RECYCLE_BLACKLIST_TICKS
			_recent_recycle_cell = src
			_recent_recycle_cell_t = RECYCLE_CELL_PROTECT_S
			GameState.save_game()
			queue_redraw()
			return
	var dst := _cell_at_point(p)
	if dst.x < 0 or dst == src:
		queue_redraw()
		return
	var src_id := GameState.get_cell(src.x, src.y)
	var dst_id := GameState.get_cell(dst.x, dst.y)
	if dst_id == &"":
		# Move
		GameState.set_cell(dst.x, dst.y, src_id)
		GameState.set_cell(src.x, src.y, &"")
		Audio.play_sfx("place")
	else:
		# Try merge. All merges are free now — combine freely and experiment.
		var result := Items.try_merge(src_id, dst_id)
		if result == &"":
			# Same+same with no upgrade (e.g. two Winches) → clear the src.
			# Uses the same drag gesture as a merge, so dropping a duplicate onto
			# its twin clears the board without dragging each item to the bin.
			if src_id == dst_id and Items.try_merge(src_id, src_id) == &"":
				var sdef: Items.ItemDef = Items.get_def(src_id)
				GameState.set_cell(src.x, src.y, &"")
				Audio.play_sfx("place")
				if sdef:
					_show_toast("Cleared duplicate %s" % sdef.name, 2.0)
				GameState.save_game()
				queue_redraw()
				return
			Audio.play_sfx("nope")
			_show_hint(_explain_failed_merge(src_id, dst_id))
			_failed_experiments += 1
		else:
			GameState.set_cell(dst.x, dst.y, result)
			GameState.set_cell(src.x, src.y, &"")
			Audio.play_sfx("merge")
			var def: Items.ItemDef = Items.get_def(result)
			# Brief merge demo on the destination cell.
			_show_merge_demo(src_id, dst_id, result, dst)
			if def.tier >= Items.Tier.INVENTION:
				if GameState.discover(result):
					Audio.play_sfx("discover")
					_failed_experiments = 0
					_show_discovery_card(result)
				_show_hint(_post_invention_message(result, def))
			GameState.save_game()
	queue_redraw()

func _show_hint(s: String) -> void:
	# Small persistent hint at bottom (kept for context).
	_hint_label.text = s
	# Also display a big toast — players were missing the bottom hint entirely.
	_show_toast(s, 3.0)

func _show_toast(text: String, seconds: float) -> void:
	if _toast == null: return
	# `lead` prefixes are now empty (emoji tofu on iOS) — trim any leading space.
	_toast_label.text = text.strip_edges(true, false)
	_toast.visible = true
	_toast.modulate = Color(1, 1, 1, 1)
	# Goal banner shares this slot — hide it so the toast reads cleanly.
	# It reappears when the toast times out via _refresh_quest_ui.
	if _goal_banner: _goal_banner.visible = false
	_toast_timer.start(seconds)

func _show_discovery_card(id: StringName) -> void:
	var card := preload("res://scenes/discovery_card.gd").new()
	card.invention_id = id
	# When this card is dismissed, chain the Level Complete congrats modal if a
	# quest just finished (set by _on_discovered before this card was created).
	card.tree_exited.connect(_on_discovery_card_closed)
	add_child(card)

func _on_discovery_card_closed() -> void:
	if _pending_level_complete < 0:
		return
	var lvl := _pending_level_complete
	_pending_level_complete = -1
	# The all-30 grand finale (workshop_complete) handles the very last invention;
	# don't stack the per-level congrats on top of it.
	if GameState.discovered.size() >= Items.all_inventions().size():
		return
	_show_level_complete(lvl)

func _post_invention_message(id: StringName, def: Items.ItemDef) -> String:
	# Quest invention? Tell them to deliver, period.
	if active_quest_npc != &"":
		var npc := Npcs.by_id(active_quest_npc)
		if npc and npc.wants == id:
			return "%s ready! Tap the green button below to finish the quest." % def.name
	# Masterwork they just made — pure celebration.
	if def.tier == Items.Tier.MASTERWORK:
		return "Masterwork! %s is one of the rarest inventions." % def.name
	# Only hint masterwork combos if the result is a target in the current level.
	var cur_targets: Array = Items.LEVELS[GameState.current_level].targets \
		if GameState.current_level < Items.LEVELS.size() else []
	for key in Items.cross:
		var k := String(key)
		var sid := String(id)
		if k.begins_with(sid + "|") or k.ends_with("|" + sid):
			var result_id: StringName = Items.cross[key]
			if result_id in cur_targets and not GameState.is_discovered(result_id):
				var other := k.replace(sid, "").replace("|", "")
				var od: Items.ItemDef = Items.get_def(StringName(other))
				var rd: Items.ItemDef = Items.get_def(result_id)
				if od and rd:
					return "%s invented! Combine with %s to make %s." % [
						def.name, od.name, rd.name]
	return "%s invented! Tap Recipes below to see more." % def.name

func _explain_failed_merge(a_id: StringName, b_id: StringName) -> String:
	var a: Items.ItemDef = Items.get_def(a_id)
	var b: Items.ItemDef = Items.get_def(b_id)
	if a == null or b == null:
		return "Those don't fit together."
	# Same item, top of upgrade chain — needs a DIFFERENT partner.
	if a_id == b_id and a.tier >= Items.Tier.PART:
		return "Two %ss don't combine. %s is a Part — pair it with a DIFFERENT part to invent." % [a.name, a.name]
	# Same item with no upgrade defined (shouldn't happen for T0/T1 but defensive).
	if a_id == b_id:
		return "%s has no further upgrade yet." % a.name
	# Different items, low tier — junk/components can't cross-combine; only parts do.
	if a.tier < Items.Tier.PART or b.tier < Items.Tier.PART:
		return "Junk only merges with the SAME junk. Upgrade them to Parts first, then combine different ones."
	# Different parts, no invention defined for this pair.
	if _failed_experiments >= 3:
		return _make_hint()
	return "%s + %s isn't a known invention. Try other part pairs!" % [a.name, b.name]

func _make_hint() -> String:
	# After 3 failures, give a vague clue about the active quest invention
	if active_quest_npc == &"": return "Try mixing parts from different categories."
	var npc := Npcs.by_id(active_quest_npc)
	if npc == null: return ""
	var d: Items.ItemDef = Items.get_def(npc.wants)
	if d == null: return ""
	return "Hint: %s needs two different parts combined." % d.name

func _refresh_progress() -> void:
	_refresh_goal_bar()
	_refresh_discoveries()
	# Mark level as seen when all targets discovered (for dot-strip ✓ display).
	# No overlay — NPC quest auto-completes via _on_discovered and returns to village.
	var cur := GameState.current_level
	if cur >= 0 and cur < Items.LEVELS.size():
		var lvl: Dictionary = Items.LEVELS[cur]
		var all_done := true
		for t in lvl.targets:
			if not GameState.is_discovered(t): all_done = false; break
		if all_done and not GameState.levels_seen.has(cur):
			GameState.levels_seen[cur] = true
			GameState.save_game()
	var total: int = Items.all_inventions().size()
	var got: int = GameState.discovered.size()
	if got >= total and total > 0 and not GameState.workshop_complete_seen:
		GameState.workshop_complete_seen = true
		GameState.save_game()
		Audio.play_sfx("discover")
		add_child(preload("res://scenes/workshop_complete.tscn").instantiate())

func _show_level_complete(level_idx: int) -> void:
	# Congrats modal shown after the discovery card when a level's quest is done.
	# Primary CTA jumps straight into the next level (the board crossfades to a
	# fresh one); the village hub stays reachable via the bottom tab.
	var overlay := preload("res://scenes/level_complete.tscn").instantiate()
	overlay.level_idx = level_idx
	# Personalize with the just-finished NPC's building + thank-you line.
	if active_quest_npc != &"":
		var npc := Npcs.by_id(active_quest_npc)
		if npc:
			overlay.building_label = npc.building_label
			overlay.thanks = npc.thanks
	overlay.advance_to_next.connect(func(): _advance_to_next_level(level_idx))
	overlay.return_to_village.connect(func(): go_village.emit())
	add_child(overlay)

func _advance_to_next_level(from_level: int) -> void:
	# Switch the active quest to the next level's NPC and ask main to crossfade to
	# a fresh workbench for it — same path the village hub uses to launch a level.
	var next: int = from_level + 1
	if next >= Items.LEVELS.size():
		go_village.emit()  # no further level — fall back to the hub
		return
	var npc := Npcs.by_level(next)
	if npc == null:
		go_village.emit()
		return
	GameState.advance_to_level(next)
	if GameState.quest_status(npc.id) != "done":
		GameState.set_quest_status(npc.id, "active")
	GameState.save_game()
	go_workbench.emit(npc.id)

func _refresh_discoveries() -> void:
	if _cur_grid == null: return
	var cur: int = GameState.current_level
	var total_levels: int = Items.LEVELS.size()
	if cur < 0 or cur >= total_levels:
		for c in _cur_cells: c.visible = false
		return
	var lvl: Dictionary = Items.LEVELS[cur]
	# Style each of the 5 target cells.
	for j in 5:
		var cell: PanelContainer = _cur_cells[j]
		cell.visible = true
		var id: StringName = lvl.targets[j]
		var d: Items.ItemDef = Items.get_def(id)
		var v: VBoxContainer = cell.get_child(0)
		var glyph_lbl: Label = v.get_child(0)
		var name_lbl: Label = v.get_child(1)
		var sb: StyleBoxFlat = cell.get_theme_stylebox("panel")
		var discovered := GameState.is_discovered(id)
		if discovered:
			sb.bg_color = Color(0.22, 0.18, 0.12)
			sb.border_color = d.color.lightened(0.15)
			sb.border_color.a = 0.85
			sb.set_border_width_all(2)
			glyph_lbl.text = d.glyph
			var gi: Color = d.color.lightened(0.35)
			gi.a = 0.95
			glyph_lbl.add_theme_color_override("font_color", gi)
			name_lbl.text = d.name
			name_lbl.add_theme_color_override("font_color", d.color.lightened(0.55))
			cell.tooltip_text = "%s (Tier %d)" % [d.name, d.tier]
		else:
			sb.bg_color = Color(0.14, 0.12, 0.10, 1.0)
			sb.border_color = Color(0.40, 0.38, 0.32)
			sb.set_border_width_all(1)
			glyph_lbl.text = "?"
			glyph_lbl.add_theme_color_override("font_color", Color(0.50, 0.48, 0.40))
			name_lbl.text = d.name
			name_lbl.add_theme_color_override("font_color", Color(0.50, 0.48, 0.40))
			cell.tooltip_text = "Undiscovered (%s)" % d.name

func _refresh_goal_bar() -> void:
	if _goal_banner == null or _goal_fill == null: return
	var lvl_idx: int = GameState.current_level
	var total_levels: int = Items.LEVELS.size()
	if lvl_idx >= total_levels:
		_goal_fill.position = Vector2.ZERO
		_goal_fill.size = _goal_banner.size
		_goal_fill.color = Color(1.00, 0.80, 0.30, 1.0)
		_goal_track_sb.border_color = Color(0.85, 0.65, 0.30, 1.0)
		_goal_label.text = "Workshop Master — all %d levels complete!" % total_levels
		return
	var lvl: Dictionary = Items.LEVELS[lvl_idx]
	var targets: Array = lvl.targets
	var lvl_got := 0
	for t in targets:
		if GameState.is_discovered(t): lvl_got += 1
	# When a quest is active, the goal bar becomes a "building project" panel
	# (like Royal Match areas). NPC color, building name, ingredient progress
	# dots that fill in as you build — each ● is like placing a decoration.
	var npc: Npcs.NpcDef = Npcs.by_id(active_quest_npc) if active_quest_npc != &"" else null
	if npc:
		var c: Color = npc.color
		# NPC = themed level. Use the NPC's OWN level targets (not current_level)
		# so the bar is always correct even if current_level lags behind.
		var npc_targets: Array = Items.LEVELS[npc.level].targets if npc.level >= 0 and npc.level < Items.LEVELS.size() else targets
		var npc_total: int = npc_targets.size()
		var npc_got := 0
		for t in npc_targets:
			if GameState.is_discovered(t): npc_got += 1
		var pct: float = float(npc_got) / float(max(1, npc_total))
		_goal_fill.position = Vector2.ZERO
		_goal_fill.size = Vector2(_goal_banner.size.x * pct, _goal_banner.size.y)
		_goal_fill.color = Color(c.r * 0.55, c.g * 0.50, c.b * 0.45, 1.0)
		_goal_track_sb.border_color = Color(c.r, c.g, c.b, 0.85)
		_goal_track_sb.bg_color = Color(c.r * 0.18, c.g * 0.14, c.b * 0.10, 1.0)
		if npc_got >= npc_total:
			_goal_label.text = "%s  ✓ Complete!" % npc.building_label
		else:
			_goal_label.text = "%s  %d/%d" % [npc.building_label, npc_got, npc_total]
	else:
		var pct: float = float(lvl_got) / float(max(1, targets.size()))
		_goal_fill.position = Vector2.ZERO
		_goal_fill.size = Vector2(_goal_banner.size.x * pct, _goal_banner.size.y)
		_goal_fill.color = Color(0.55, 0.85, 0.45, 1.0)
		_goal_track_sb.border_color = Color(0.85, 0.65, 0.30, 1.0)
		_goal_track_sb.bg_color = Color(0.30, 0.22, 0.12, 1.0)
		_goal_label.text = "%s  %d/%d" % [lvl.name, lvl_got, targets.size()]

func _on_discovered(_id: StringName) -> void:
	_refresh_progress()
	_refresh_discoveries()
	_refresh_goal_bar()
	# Auto-complete NPC quest when all level targets discovered.
	if active_quest_npc != &"":
		var npc := Npcs.by_id(active_quest_npc)
		if npc and npc.level >= 0 and npc.level < Items.LEVELS.size():
			var lvl_def: Dictionary = Items.LEVELS[npc.level]
			var all_done := true
			for t in lvl_def.targets:
				if not GameState.is_discovered(t):
					all_done = false
					break
			if all_done and GameState.quest_status(active_quest_npc) != "done":
				GameState.set_quest_status(active_quest_npc, "done")
				GameState.save_game()
				Audio.play_sfx("deliver")
				# Defer the congrats modal until the discovery card is dismissed
				# (the card is shown for this same invention). _on_discovery_card_closed
				# picks this up and chains the "Level Complete" overlay after it.
				_pending_level_complete = npc.level

func _open_book(highlight_id: StringName = &"") -> void:
	var book := preload("res://scenes/invention_book.tscn").instantiate()
	if highlight_id != &"":
		book.highlight_id = highlight_id
	add_child(book)

func _on_discovery_cell_input(event: InputEvent, idx: int) -> void:
	# Click/tap on a single discoveries-row cell → open the Book targeted to
	# that level target. Player who can't decode the silhouette gets exactly
	# the recipe they need.
	var pressed: bool = false
	if event is InputEventMouseButton and event.pressed: pressed = true
	elif event is InputEventScreenTouch and event.pressed: pressed = true
	if not pressed: return
	var lvl: Dictionary = Items.LEVELS[GameState.current_level]
	if idx < 0 or idx >= lvl.targets.size(): return
	_open_book(lvl.targets[idx])

func _open_tutorial() -> void:
	add_child(preload("res://scenes/tutorial.tscn").instantiate())

func _make_tab_button(icon: String, label: String, primary: bool, on_press: Callable) -> Button:
	# iOS-style tab: icon (24pt) over label (12pt), no fill. Primary tab is
	# gold-tinted; secondary tabs are warm tan. All same size — emphasis
	# comes from color, not from enlarging one button.
	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.pressed.connect(on_press)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.anchor_right = 1.0; v.anchor_bottom = 1.0
	btn.add_child(v)
	var tint := Color(1.0, 0.82, 0.32) if primary else Color(0.85, 0.76, 0.55)
	# Known kinds are CUSTOM-DRAWN (UIIcon) so they don't tofu on iOS; plain
	# ASCII like "?" stays a Label (it's font-safe).
	const DRAW_KINDS := ["arrow_left", "book", "dots", "house", "magnify", "target", "truck"]
	if icon in DRAW_KINDS:
		var ic := UIIcon.new(icon, tint)
		ic.custom_minimum_size = Vector2(30, 28)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
	else:
		var icon_lbl := Label.new()
		icon_lbl.text = icon
		icon_lbl.add_theme_font_size_override("font_size", 24)
		icon_lbl.add_theme_color_override("font_color", tint)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(icon_lbl)
	var text_lbl := Label.new()
	text_lbl.text = label
	text_lbl.add_theme_font_size_override("font_size", 14)
	text_lbl.add_theme_color_override("font_color", tint)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text_lbl)
	return btn

func _enter_tree() -> void:
	_chute_timer = Timer.new()
	_chute_timer.wait_time = CHUTE_INTERVAL
	_chute_timer.autostart = true
	_chute_timer.timeout.connect(_on_chute_tick)
	add_child(_chute_timer)

func _on_chute_tick() -> void:
	# Decrement recycle blacklist counters; entries drop off when they hit 0.
	# Keeps recently-rejected items off the chute for ~10s after recycling.
	for k in _recent_recycles.keys():
		_recent_recycles[k] -= 1
		if _recent_recycles[k] <= 0:
			_recent_recycles.erase(k)
	# Scale drops with empty count — 1-by-1 feels silly when 8 cells are open,
	# but filling ALL at once floods the board and creates an endless recycle
	# cycle. Compromise: 1 drop when few slots open, 2 when 4+, 3 when 8+.
	# Each call to _pick_helpful_junk sees the updated board from the previous
	# set_cell, so we get varied junk instead of N copies of the same thing.
	var empties: Array = _empty_cells_excluding_protected()
	if empties.is_empty(): return
	empties.shuffle()
	var drop_count := 1
	if empties.size() >= 8: drop_count = 3
	elif empties.size() >= 4: drop_count = 2
	for i in drop_count:
		if i >= empties.size(): break
		var id := _pick_helpful_junk()
		GameState.set_cell(empties[i].x, empties[i].y, id)
	_reset_idle()

func _empty_cells_excluding_protected() -> Array:
	var out: Array = []
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			if GameState.get_cell(x, y) != &"": continue
			var pos := Vector2i(x, y)
			if _recent_recycle_cell_t > 0.0 and pos == _recent_recycle_cell:
				continue  # protect — keep slot open for the player to use
			out.append(pos)
	# If protection left us with zero options AND the board has empties,
	# release the protect so we don't starve the chute forever.
	if out.is_empty() and GameState.find_empty_cell().x >= 0:
		for y in GameState.BOARD_H:
			for x in GameState.BOARD_W:
				if GameState.get_cell(x, y) == &"":
					out.append(Vector2i(x, y))
	return out

func _pick_helpful_junk() -> StringName:
	# Smart chute: drops a junk that *progresses* the existing board.
	# Priorities (REORDERED — undiscovered targets first, to prevent the
	# pre-fix bug where the chute looped on Old Bulbs forever because of a
	# single Lit Bulb on the board):
	#   1. Closest undiscovered target → seed for its missing ingredient.
	#   2. Complete an unpaired JUNK pair on the board (immediate merge).
	#   3. Junk-root of unpaired tier-1/tier-2 — only if that line ALSO
	#      feeds an undiscovered target (no more over-producing Lanterns).
	#   4. Fallback random.
	var on_board: Dictionary = {}
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id == &"": continue
			on_board[id] = on_board.get(id, 0) + 1
	# 1. UNDISCOVERED target → seed for missing ingredient. (Highest priority.)
	var nudge := _closest_undiscovered()
	if nudge.size() == 2:
		var missing: StringName = nudge[1]
		# Don't flood the board when the missing ingredient can already be
		# assembled from parts present on the board (e.g., Oven needs
		# Boiler + Fuel Tank — if both are here, stop dropping pipe/oil).
		var can_assemble := false
		for key in Items.cross:
			if Items.cross[key] == missing:
				var cps: PackedStringArray = String(key).split("|")
				if on_board.has(StringName(cps[0])) and on_board.has(StringName(cps[1])):
					can_assemble = true
				break
		if not can_assemble:
			var seeds := _junk_seeds_for(missing)
			if seeds.size() > 0:
				return seeds[randi() % seeds.size()]
	# 2. Unpaired junk on board (only if NO undiscovered target found, very rare).
	var junk_unpaired: Array = []
	for id in on_board:
		if _recent_recycles.has(id): continue  # don't double down on rejected item
		var d: Items.ItemDef = Items.get_def(id)
		if d and d.tier == Items.Tier.JUNK and int(on_board[id]) % 2 == 1:
			junk_unpaired.append(id)
	if junk_unpaired.size() > 0:
		return junk_unpaired[randi() % junk_unpaired.size()]
	# 3. Junk-root of unpaired tier-1/tier-2 (only if its upgrade chain leads
	# to an undiscovered cross-combine — skip dead-end lines).
	var helpful_roots: Array = []
	for id in on_board:
		if _recent_recycles.has(id): continue  # don't rebuild the recycled chain
		var d: Items.ItemDef = Items.get_def(id)
		if d == null: continue
		if d.tier == Items.Tier.COMPONENT or d.tier == Items.Tier.PART:
			if int(on_board[id]) % 2 == 1 and _line_has_undiscovered_target(id):
				var root := _junk_root_for(id)
				if root != &"" and not _recent_recycles.has(root):
					helpful_roots.append(root)
	if helpful_roots.size() > 0:
		return helpful_roots[randi() % helpful_roots.size()]
	# 4. fallback: pick a junk from THIS LEVEL's pool (filtered against blacklist).
	var pool: Array = Items.junks_for_level(GameState.current_level).duplicate()
	var filtered: Array = pool.filter(func(j): return not _recent_recycles.has(j))
	if filtered.size() > 0:
		return filtered[randi() % filtered.size()]
	return pool[randi() % pool.size()]

func _seed_starter_hand() -> void:
	# Delegate to GameState so a fresh-board seed is identical whether it happens
	# on first _ready or on a level-advance (advance_to_level seeds there directly,
	# beating the outgoing board's chute timer during the crossfade).
	GameState.seed_starter_hand()

# Returns true if the upgrade-chain ending at `id` (or `id` itself, if it's
# already a Part) is an ingredient in any undiscovered cross-combine.
func _line_has_undiscovered_target(id: StringName) -> bool:
	# Walk forward through upgrades to the eventual Part.
	var cur := id
	while true:
		var next: StringName = Items.upgrade.get(cur, &"")
		if next == &"": break
		cur = next
	# `cur` is now a Part (or the original id if it was already PART).
	for key in Items.cross:
		var k := String(key)
		var prefix := String(cur) + "|"
		var suffix := "|" + String(cur)
		if k.begins_with(prefix) or k.ends_with(suffix):
			var result: StringName = Items.cross[key]
			if not GameState.is_discovered(result):
				return true
	return false

func _junk_root_for(id: StringName) -> StringName:
	# Walk Items.upgrade backwards to find the tier-0 junk that upgrades into id.
	var cur := id
	while true:
		var prev: StringName = &""
		for src in Items.upgrade:
			if Items.upgrade[src] == cur:
				prev = src
				break
		if prev == &"": break
		cur = prev
	var d: Items.ItemDef = Items.get_def(cur)
	if d and d.tier == Items.Tier.JUNK:
		return cur
	return &""

func _break_soft_lock_if_needed() -> void:
	# When the board is full with zero merges, replace low-tier items with a PART
	# pair that cross-combines into an UNDISCOVERED invention. Never inject parts
	# for an already-discovered result — that just clogs the board with duplicate
	# Fans. Also never replace an INVENTION or higher — the player just made it.
	if _in_break_soft_lock: return
	if GameState.find_empty_cell().x >= 0: return
	if not _mergeable_cells.is_empty(): return
	_in_break_soft_lock = true
	# Collect existing parts on board + find the two lowest-tier items that
	# are safe to replace (junk/component only — never scrap inventions).
	var existing_parts: Array = []
	var part_pos: Dictionary = {}
	var scrap_candidates: Array = []  # [{pos, tier, def}] sorted by tier
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id == &"": continue
			var d: Items.ItemDef = Items.get_def(id)
			if d == null: continue
			if d.tier == Items.Tier.PART and not part_pos.has(id):
				existing_parts.append(id)
				part_pos[id] = Vector2i(x, y)
			if d.tier <= Items.Tier.COMPONENT:
				scrap_candidates.append({"pos": Vector2i(x, y), "tier": d.tier, "def": d})
	scrap_candidates.sort_custom(func(a, b): return a.tier < b.tier)
	# Late-game fallback: board filled entirely with PARTs/INVENTIONs/MASTERWORKs
	# (no junk or components left to replace). Allow replacing DUPLICATE discovered
	# items — excess copies that can't merge with anything are dead weight.
	if scrap_candidates.is_empty():
		var counts: Dictionary = {}
		for y2 in GameState.BOARD_H:
			for x2 in GameState.BOARD_W:
				var cid := GameState.get_cell(x2, y2)
				if cid != &"": counts[cid] = counts.get(cid, 0) + 1
		for y2 in GameState.BOARD_H:
			for x2 in GameState.BOARD_W:
				var cid := GameState.get_cell(x2, y2)
				if cid == &"": continue
				var cd: Items.ItemDef = Items.get_def(cid)
				if cd == null: continue
				if not GameState.is_discovered(cid): continue
				if counts.get(cid, 0) < 2: continue
				scrap_candidates.append({"pos": Vector2i(x2, y2), "tier": cd.tier, "def": cd})
				counts[cid] -= 1  # only add excess copies
		scrap_candidates.sort_custom(func(a2, b2): return a2.tier < b2.tier)
	if scrap_candidates.is_empty():
		_in_break_soft_lock = false
		return
	# Find an injection target. ONLY undiscovered inventions — never inject parts
	# for something the player already has (that's what caused the Fan-spam bug).
	# Also skip items in _recent_recycles — if the player just scrapped Frame,
	# injecting Frame here would land at the same cell they just emptied
	# (lowest-tier slot == the fresh bolt the chute dropped into it).
	var inject: StringName = &""
	var partner: StringName = &""
	var target_name := ""
	# Strategy A: partner with an existing Part on board → undiscovered result.
	for existing in existing_parts:
		if _recent_recycles.has(existing): continue
		for key in Items.cross:
			var ps: PackedStringArray = String(key).split("|")
			var a := StringName(ps[0]); var b := StringName(ps[1])
			var r: StringName = Items.cross[key]
			var rd: Items.ItemDef = Items.get_def(r)
			if rd == null or rd.tier != Items.Tier.INVENTION: continue
			if GameState.is_discovered(r): continue
			if _recent_recycles.has(r): continue
			var candidate: StringName = &""
			if a == existing and not part_pos.has(b): candidate = b
			elif b == existing and not part_pos.has(a): candidate = a
			if candidate == &"" or _recent_recycles.has(candidate): continue
			inject = candidate
			partner = existing
			target_name = rd.name
			break
		if inject != &"": break
	# Strategy B: inject a fresh pair for any undiscovered invention.
	if inject == &"":
		for key in Items.cross:
			var r: StringName = Items.cross[key]
			var rd: Items.ItemDef = Items.get_def(r)
			if rd == null or rd.tier != Items.Tier.INVENTION: continue
			if GameState.is_discovered(r): continue
			if _recent_recycles.has(r): continue
			var ps: PackedStringArray = String(key).split("|")
			var p0 := StringName(ps[0])
			var p1 := StringName(ps[1])
			if _recent_recycles.has(p0) or _recent_recycles.has(p1): continue
			inject = p0
			partner = p1
			target_name = rd.name
			break
	# Strategy C: undiscovered masterwork ingredients (late game).
	# Pick the ingredient NOT already on the board. Old bug: always picked
	# ps[0] (e.g. Camera for Photo Studio) even when Camera was on the board
	# 3 times, causing an endless Camera-injection cycle.
	if inject == &"":
		for key in Items.cross:
			var r: StringName = Items.cross[key]
			var rd: Items.ItemDef = Items.get_def(r)
			if rd == null or rd.tier != Items.Tier.MASTERWORK: continue
			if GameState.is_discovered(r): continue
			var ps: PackedStringArray = String(key).split("|")
			var mw_a := StringName(ps[0])
			var mw_b := StringName(ps[1])
			var have_a := _find_on_board(mw_a).x >= 0
			var have_b := _find_on_board(mw_b).x >= 0
			if have_a and have_b: continue  # both present → already mergeable
			var ing: StringName
			if have_a:
				ing = mw_b  # Camera on board → build Spotlight
			elif have_b:
				ing = mw_a
			else:
				ing = mw_a if not _recent_recycles.has(mw_a) else mw_b
			if _recent_recycles.has(ing): continue
			for ikey in Items.cross:
				if Items.cross[ikey] != ing: continue
				var ips: PackedStringArray = String(ikey).split("|")
				var ip0 := StringName(ips[0])
				var ip1 := StringName(ips[1])
				if _recent_recycles.has(ip0) or _recent_recycles.has(ip1): continue
				inject = ip0
				partner = ip1
				target_name = "%s (for %s)" % [Items.get_def(ing).name, rd.name]
				break
			if inject != &"": break
	# Nothing undiscovered left — don't inject discovered duplicates.
	if inject == &"":
		_in_break_soft_lock = false
		return
	# Place the injected part in the lowest-tier scrap slot. Avoid the cell
	# the player just recycled from — landing the replacement there feels like
	# the recycle "didn't take." Fall back to lowest if that's the only option.
	var primary_pos: Vector2i = scrap_candidates[0].pos
	if _recent_recycle_cell_t > 0.0 and scrap_candidates.size() >= 2:
		for cand in scrap_candidates:
			if cand.pos != _recent_recycle_cell:
				primary_pos = cand.pos
				break
	GameState.set_cell(primary_pos.x, primary_pos.y, inject)
	_flash_cell = primary_pos
	_flash_t = 1.0
	# If partner isn't already on board, inject into next-lowest non-protected slot.
	if not part_pos.has(partner) and scrap_candidates.size() >= 2:
		var second_pos: Vector2i = Vector2i(-1, -1)
		for cand in scrap_candidates:
			if cand.pos == primary_pos: continue
			if _recent_recycle_cell_t > 0.0 and cand.pos == _recent_recycle_cell: continue
			second_pos = cand.pos
			break
		if second_pos.x < 0:
			for cand in scrap_candidates:
				if cand.pos != primary_pos:
					second_pos = cand.pos
					break
		if second_pos.x >= 0:
			GameState.set_cell(second_pos.x, second_pos.y, partner)
	_suggest_cells = [primary_pos]
	if part_pos.has(partner):
		_suggest_cells.append(part_pos[partner])
	Audio.play_sfx("place")
	_show_toast("Combine these to INVENT the %s!" % target_name, 5.0)
	GameState.save_game()
	_in_break_soft_lock = false

func _refresh_quest_ui() -> void:
	# Quest header removed — the hint system guides the player toward the quest
	# target with cell highlights, and the deliver button names the item when
	# it's ready. The goal banner (level progress) stays visible always, but
	# its color + text update to show the active NPC.
	_quest_label.text = ""
	_quest_label.visible = false
	_goal_banner.visible = true
	_refresh_goal_bar()

func _quest_base_junks(invention_id: StringName) -> Array:
	var seeds: Array = []
	for parent in _quest_parents(invention_id):
		for s in _junk_seeds_for(parent):
			if not seeds.has(s): seeds.append(s)
	return seeds

func _quest_unreachable_junks(invention_id: StringName) -> Array:
	# Base-junk ids the quest needs that aren't in the current level's chute pool.
	# Non-empty result means the quest can't be completed at the current level.
	var lvl_idx: int = GameState.current_level
	if lvl_idx < 0 or lvl_idx >= Items.LEVELS.size(): return []
	var pool: Array = Items.LEVELS[lvl_idx].junks
	var missing: Array = []
	for s in _quest_base_junks(invention_id):
		if not pool.has(s): missing.append(s)
	return missing

func _recipe_hint_for(id: StringName) -> String:
	for key in Items.cross:
		if Items.cross[key] == id:
			var parts: PackedStringArray = String(key).split("|")
			var a: Items.ItemDef = Items.get_def(StringName(parts[0]))
			var b: Items.ItemDef = Items.get_def(StringName(parts[1]))
			if a and b:
				return "combine %s + %s" % [a.name, b.name]
	return ""

func _refresh_deliver_button() -> void:
	# NPC quests are now level completions — no single-item delivery needed.
	# Quest auto-completes when all 5 level targets are discovered.
	_deliver_btn.visible = false

func _find_on_board(id: StringName) -> Vector2i:
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			if GameState.get_cell(x, y) == id: return Vector2i(x, y)
	return Vector2i(-1, -1)

func _deliver() -> void:
	if active_quest_npc == &"": return
	var npc := Npcs.by_id(active_quest_npc)
	if npc == null: return
	var cell := _find_on_board(npc.wants)
	if cell.x < 0: return
	GameState.set_cell(cell.x, cell.y, &"")
	GameState.set_quest_status(active_quest_npc, "done")
	GameState.save_game()
	Audio.play_sfx("deliver")
	go_village.emit()
