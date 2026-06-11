extends Control
## First-run INTERACTIVE tutorial — runs on the live Workbench.
##
## Instead of a wall of text, this hand-guides the player through three REAL
## merges that end in their first invention discovery. The trick: it seeds a tiny
## deterministic "rail" board where exactly ONE merge is possible at each step, so
## the player physically cannot go wrong — the board itself is the rail.
##
##   1. bolt + bolt        -> bolt_bundle   (learn the merge gesture)
##   2. bolt_bundle x2     -> frame         (learn: keep climbing the chain)
##   3. frame + lantern    -> lamp_post     (learn: different parts INVENT)  --> discovery card
##
## The old static text overlay (scenes/tutorial.tscn) is kept as the "?" Help
## quick reference; this is what auto-opens on a brand-new install.
##
## While active it flips workbench._tutorial_active so the chute, idle-hint pulse,
## and soft-lock breaker stand down and can't disturb the rail. On completion it
## reseeds a normal full starter board and hands the player off to free play.

# Step machine. The three MERGE_* phases each drive the dim+spotlight+pointer in
# _draw; AWAIT_CARD hides the overlay while the real discovery card is up; FINISH
# shows the congrats card + points at Lux's goal bar; DONE tears everything down.
enum { MERGE_BOLT, MERGE_BUNDLE, MERGE_LAMP, AWAIT_CARD, FINISH, DONE }

var _wb: Control = null
var _phase: int = MERGE_BOLT
var _t: float = 0.0  # animation clock

var _banner: PanelContainer
var _banner_label: Label
var _bottom_blocker: Control   # swallows taps on recycle / discoveries / tab bar
var _finish_root: Control      # full-screen shield + congrats card (FINISH only)

# Tier-name "pop": when a merge creates a new tile, a one-word label (Crafted!,
# Part!) floats up off it and fades — timed to the moment its background ramp
# visibly changes, so the player LEARNS the category ladder without a wall of
# text. Junk gets an intro pop on the starting scrap; Invention is taught by the
# real discovery card ("Invention Discovered!").
const TIER_POP := ["Junk", "Crafted!", "Part!", "Invention!", "Masterwork!"]
var _tier_pop_text: String = ""
var _tier_pop_cell: Vector2i = Vector2i(-1, -1)
var _tier_pop_tier: int = 0   # indexes the workbench's TIER_COLOR rarity ramp
var _tier_pop_t: float = 0.0  # 1 -> 0 lifetime

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	# IGNORE so board drags fall through to the workbench's own _gui_input. Specific
	# STOP children below re-block the parts the player must not touch mid-tutorial.
	mouse_filter = MOUSE_FILTER_IGNORE

	_wb = get_parent() as Control
	# Defensive: if somehow shown without a workbench parent, just no-op-dismiss so
	# we never crash a non-gameplay screen.
	if _wb == null or not _wb.has_method("_cell_origin"):
		queue_free()
		return
	_wb.set("_tutorial_active", true)
	_seed_rail()

	_build_blocker()
	_build_banner()

	GameState.merge_committed.connect(_on_merge)
	resized.connect(_layout_overlay)
	set_process(true)
	_apply_phase()
	call_deferred("_layout_overlay")
	# Intro pop on the raw scrap so the player meets "Junk" before climbing the ladder.
	get_tree().create_timer(0.6).timeout.connect(_pop_junk_intro)

func _seed_rail() -> void:
	# Wipe whatever starter hand the workbench just dealt and lay the rail. Kept in
	# the top two rows so the spotlight always sits high and the instruction banner
	# has clear room below the board.
	GameState.clear_board()
	GameState.set_cell(0, 0, &"bolt")
	GameState.set_cell(1, 0, &"bolt")
	GameState.set_cell(3, 0, &"bolt_bundle")
	GameState.set_cell(0, 1, &"lantern")

# --- UI -------------------------------------------------------------------

func _build_blocker() -> void:
	_bottom_blocker = Control.new()
	_bottom_blocker.mouse_filter = MOUSE_FILTER_STOP
	_bottom_blocker.gui_input.connect(func(_e): pass)  # swallow
	add_child(_bottom_blocker)

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.11, 0.06, 0.97)
	sb.border_color = Color(0.95, 0.78, 0.32)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	_banner.add_theme_stylebox_override("panel", sb)
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 28)
	_banner_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.72))
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_label)
	add_child(_banner)

func _layout_overlay() -> void:
	if _wb == null: return
	var br: Rect2 = _wb._board_rect
	if br.size.y <= 0.0: return  # board not laid out yet — retried each _process
	var W := size.x; var H := size.y
	var by: float = br.end.y + 8.0
	if _bottom_blocker:
		_bottom_blocker.position = Vector2(0, by)
		_bottom_blocker.size = Vector2(W, max(0.0, H - by))
	if _banner:
		_banner.position = Vector2(16, by + 14)
		_banner.size = Vector2(W - 32, 0)  # height auto from content

# --- Step machine ---------------------------------------------------------

func _apply_phase() -> void:
	match _phase:
		MERGE_BOLT:
			_set_banner("Drag a Bolt onto its twin.", true)
		MERGE_BUNDLE:
			_set_banner("Merge the two Bundles.", true)
		MERGE_LAMP:
			_set_banner("Combine two different parts to invent.", true)
		AWAIT_CARD:
			_set_banner("", false)
		FINISH:
			_set_banner("", false)
			# A toast in flight is stale guidance now, and the dim cutout below is
			# sized to the goal banner — a taller toast in the same slot gets
			# sliced by the spotlight edge. Silence it so the banner shows clean.
			if _wb.get("_toast") != null:
				_wb._toast.visible = false
			if _wb.get("_goal_banner") != null:
				_wb._goal_banner.visible = true
			_build_finish()
		DONE:
			pass
	queue_redraw()

func _set_phase(p: int) -> void:
	if _phase == p: return
	_phase = p
	_apply_phase()

func _set_banner(text: String, vis: bool) -> void:
	if _banner == null: return
	_banner.visible = vis
	if vis:
		_banner_label.text = text

func _on_merge(result: StringName) -> void:
	match _phase:
		MERGE_BOLT:
			if result == &"bolt_bundle":
				_pop_result_tier(result)
				_set_phase(MERGE_BUNDLE)
		MERGE_BUNDLE:
			if result == &"frame":
				_pop_result_tier(result)
				_set_phase(MERGE_LAMP)
		MERGE_LAMP:
			if result == &"lamp_post":
				# Invention tier is taught by the real discovery card, not a pop.
				_set_phase(AWAIT_CARD)
				call_deferred("_watch_card")

# --- Tier-name pop --------------------------------------------------------

func _pop_junk_intro() -> void:
	# Only while still on the first step — a Bolt is the canonical Junk tile.
	if _phase == MERGE_BOLT:
		_show_tier_pop(_one_of(&"bolt"), "Junk", Items.Tier.JUNK)

func _pop_result_tier(result: StringName) -> void:
	var d: Items.ItemDef = Items.get_def(result)
	if d == null: return
	var t: String = TIER_POP[d.tier] if d.tier < TIER_POP.size() else ""
	_show_tier_pop(_one_of(result), t, d.tier)

func _show_tier_pop(cell: Vector2i, text: String, tier: int) -> void:
	if cell.x < 0 or text == "": return
	_tier_pop_cell = cell
	_tier_pop_text = text
	_tier_pop_tier = tier
	_tier_pop_t = 1.0
	queue_redraw()

func _watch_card() -> void:
	# The real discovery card is added to the workbench right after the merge. Wait
	# for it to be dismissed, then roll into the FINISH congrats. If no card showed
	# (e.g. lamp_post was somehow already discovered), fall back to a short timer.
	var card: Node = null
	for c in _wb.get_children():
		var scr: Script = c.get_script()
		if scr and String(scr.resource_path).ends_with("discovery_card.gd"):
			card = c
			break
	if card:
		card.tree_exited.connect(func():
			if _phase == AWAIT_CARD: _set_phase(FINISH))
	else:
		get_tree().create_timer(1.2).timeout.connect(func():
			if _phase == AWAIT_CARD: _set_phase(FINISH))

# --- Finish card ----------------------------------------------------------

func _build_finish() -> void:
	if _finish_root != null: return
	_finish_root = Control.new()
	_finish_root.anchor_right = 1.0; _finish_root.anchor_bottom = 1.0
	_finish_root.mouse_filter = MOUSE_FILTER_STOP  # shield: swallow stray taps
	_finish_root.gui_input.connect(func(_e): pass)
	add_child(_finish_root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.08; panel.anchor_right = 0.92
	# Zero-height anchor + grow BOTH: the card hugs its content, CENTERED on
	# 0.52 — low enough that the rail's tiles (always in the top two rows,
	# including the freshly-lit Lamp Post) stay visible, high enough that the
	# card bottom never reaches the recycle panel below the board (growing
	# only downward from 0.52 covered the bin).
	panel.anchor_top = 0.52; panel.anchor_bottom = 0.52
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.12, 0.07)
	sb.border_color = Color(0.95, 0.78, 0.32)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 22; sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	_finish_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)

	var title := Label.new()
	title.text = "You lit Lux's first lamp!"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var body := Label.new()
	body.text = "Build all 5 to finish her Street Lamps."
	body.add_theme_font_size_override("font_size", 25)
	body.add_theme_color_override("font_color", Color(0.94, 0.88, 0.70))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)

	var ok := Button.new()
	ok.text = "Start tinkering!"
	ok.add_theme_font_size_override("font_size", 26)
	ok.custom_minimum_size = Vector2(0, 68)
	var cta := StyleBoxFlat.new()
	cta.bg_color = Color(1.0, 0.78, 0.30)
	cta.set_corner_radius_all(10)
	ok.add_theme_stylebox_override("normal", cta)
	ok.add_theme_stylebox_override("hover", cta)
	ok.add_theme_stylebox_override("pressed", cta)
	ok.add_theme_color_override("font_color", Color(0.12, 0.06, 0.02))
	ok.pressed.connect(_complete)
	v.add_child(ok)

func _complete() -> void:
	_phase = DONE
	if _wb:
		_wb.set("_tutorial_active", false)
		# Hand off to free play on a full, ready-to-merge board.
		GameState.clear_board()
		GameState.seed_starter_hand()
		if _wb.get("_chute_timer"):
			_wb._chute_timer.start()
	GameState.tutorial_seen = true
	GameState.tutorial_completed.emit()
	GameState.save_game()
	queue_free()

# --- Drawing --------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _tier_pop_t > 0.0:
		_tier_pop_t = max(0.0, _tier_pop_t - delta / 1.3)
	_layout_overlay()
	queue_redraw()

func _draw() -> void:
	if _wb == null: return
	match _phase:
		MERGE_BOLT, MERGE_BUNDLE, MERGE_LAMP:
			_draw_merge_step()
		FINISH:
			_draw_finish()
		_:
			pass
	if _tier_pop_t > 0.0:
		_draw_tier_pop()

func _draw_merge_step() -> void:
	var pair := _find_pair()
	if pair.size() < 2: return
	var cs: float = _wb._cell_size
	var ra := Rect2(_wb._cell_origin(pair[0].x, pair[0].y), Vector2(cs, cs))
	var rb := Rect2(_wb._cell_origin(pair[1].x, pair[1].y), Vector2(cs, cs))
	var spot := ra.merge(rb).grow(10.0)
	_dim_around(spot)
	# Spotlight frame + per-cell rings.
	draw_rect(spot, Color(1.0, 0.85, 0.35, 0.95), false, 3.0)
	draw_rect(ra.grow(2.0), Color(1, 1, 1, 0.5), false, 2.0)
	draw_rect(rb.grow(2.0), Color(1, 1, 1, 0.5), false, 2.0)
	# Connecting arrow + sweeping "finger" from A to B.
	var ca := ra.get_center()
	var cb := rb.get_center()
	_draw_arrow(ca, cb, Color(1.0, 0.9, 0.5, 0.9), 4.0)
	var frac: float = fmod(_t * 0.7, 1.0)
	var p := ca.lerp(cb, frac)
	var pulse: float = 1.0 + 0.15 * sin(_t * 6.0)
	draw_circle(p, 26.0 * pulse, Color(1, 1, 1, 0.22))
	draw_circle(p, 14.0, Color(1.0, 0.95, 0.80, 0.88))

func _draw_finish() -> void:
	# Dim everything except Lux's building-project bar at the top, with a bouncing
	# arrow pointing UP at it from below. That bar (Street Lamps 1/5, in Lux's gold)
	# is the concrete next goal — fill it by building the other four inventions —
	# so it's a far stronger payoff hook than the passive Recipes reference tab.
	if _wb.get("_goal_banner") == null: return
	var gb: Control = _wb._goal_banner
	if gb.size.y <= 0.0: return  # not laid out yet — _process retries next frame
	# No extra frame here — the banner already has its own gold border, and a
	# second rectangle around it read as a "double box". The dim cutout + arrow
	# spotlight it plenty.
	var spot := Rect2(gb.position, gb.size).grow(6.0)
	# Keep the freshly-lit Lamp Post visible too — it's the player's trophy,
	# and dimming it out the moment it's made undercuts the payoff.
	var lamp: Vector2i = _one_of(&"lamp_post")
	if lamp.x >= 0 and _wb._cell_size > 0.0:
		var cs: float = _wb._cell_size
		var lr := Rect2(_wb._cell_origin(lamp.x, lamp.y), Vector2(cs, cs)).grow(4.0)
		_dim_around_two(spot, lr)
		draw_rect(lr, Color(1.0, 0.85, 0.35, 0.9), false, 3.0)
	else:
		_dim_around(spot)
	var bounce: float = 6.0 * sin(_t * 4.0)
	var tip := Vector2(spot.get_center().x, spot.end.y + 6.0 - bounce)
	var tail := Vector2(tip.x, tip.y + 46.0)
	_draw_arrow(tail, tip, Color(1.0, 0.9, 0.5, 0.95), 5.0)

func _dim_around_two(a: Rect2, b: Rect2) -> void:
	# Dim everything except two cutouts, where `a` sits fully ABOVE `b` (here:
	# goal banner above a board cell). Falls back to one merged cutout if they
	# ever overlap vertically — never draw dim over a spotlight.
	if a.end.y > b.position.y:
		_dim_around(a.merge(b))
		return
	var W := size.x
	var H := size.y
	var d := Color(0, 0, 0, 0.62)
	draw_rect(Rect2(0, 0, W, a.position.y), d)
	draw_rect(Rect2(0, a.position.y, a.position.x, a.size.y), d)
	draw_rect(Rect2(a.end.x, a.position.y, max(0.0, W - a.end.x), a.size.y), d)
	draw_rect(Rect2(0, a.end.y, W, max(0.0, b.position.y - a.end.y)), d)
	draw_rect(Rect2(0, b.position.y, b.position.x, b.size.y), d)
	draw_rect(Rect2(b.end.x, b.position.y, max(0.0, W - b.end.x), b.size.y), d)
	draw_rect(Rect2(0, b.end.y, W, max(0.0, H - b.end.y)), d)

func _dim_around(spot: Rect2) -> void:
	var W := size.x
	var H := size.y
	var d := Color(0, 0, 0, 0.62)
	draw_rect(Rect2(0, 0, W, spot.position.y), d)
	draw_rect(Rect2(0, spot.end.y, W, max(0.0, H - spot.end.y)), d)
	draw_rect(Rect2(0, spot.position.y, spot.position.x, spot.size.y), d)
	draw_rect(Rect2(spot.end.x, spot.position.y, max(0.0, W - spot.end.x), spot.size.y), d)

func _draw_arrow(from: Vector2, to: Vector2, col: Color, w: float) -> void:
	draw_line(from, to, col, w)
	var dir := (to - from)
	if dir.length() < 0.001: return
	dir = dir.normalized()
	var n := Vector2(-dir.y, dir.x)
	var base := to - dir * 16.0
	draw_colored_polygon(PackedVector2Array([to, base + n * 9.0, base - n * 9.0]), col)

func _draw_tier_pop() -> void:
	# A one-word category label that floats up off the freshly-made tile and fades,
	# landing right as its background ramp changes color — the teach moment.
	if _tier_pop_cell.x < 0 or _wb == null: return
	var cs: float = _wb._cell_size
	if cs <= 0.0: return
	var origin: Vector2 = _wb._cell_origin(_tier_pop_cell.x, _tier_pop_cell.y)
	var cell := Rect2(origin, Vector2(cs, cs))
	var t := _tier_pop_t  # 1 -> 0
	var rise: float = (1.0 - t) * 34.0
	var center := Vector2(cell.get_center().x, cell.position.y - 4.0 - rise)
	var alpha: float = clamp(t * 1.4, 0.0, 1.0)  # bright early, fade out late
	var font := get_theme_default_font()
	var fs := 34
	var ts: Vector2 = font.get_string_size(_tier_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var plate := Rect2(center - ts * 0.5, ts).grow(10.0)
	# Plate + word in the RARITY color — this is what teaches the color code the
	# board's corner ribbons use (green=Crafted, blue=Part, ...).
	var tc: Color = _wb.TIER_COLOR[_tier_pop_tier] \
		if _tier_pop_tier < _wb.TIER_COLOR.size() else Color(1.0, 0.85, 0.35)
	draw_rect(plate, Color(0.12, 0.07, 0.03, 0.88 * alpha))
	var edge := tc
	edge.a = 0.9 * alpha
	draw_rect(plate, edge, false, 2.5)
	var ink := tc.lightened(0.35)
	ink.a = alpha
	var text_pos := Vector2(center.x - ts.x * 0.5, center.y + ts.y * 0.32)
	draw_string(font, text_pos, _tier_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

# --- Board lookups (rail is single-path, so these always resolve) ---------

func _find_pair() -> Array:
	match _phase:
		MERGE_BOLT:
			return _two_of(&"bolt")
		MERGE_BUNDLE:
			return _two_of(&"bolt_bundle")
		MERGE_LAMP:
			var f := _one_of(&"frame")
			var l := _one_of(&"lantern")
			if f.x >= 0 and l.x >= 0:
				return [f, l]
	return []

func _two_of(id: StringName) -> Array:
	var found: Array = []
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			if GameState.get_cell(x, y) == id:
				found.append(Vector2i(x, y))
				if found.size() == 2:
					return found
	return []

func _one_of(id: StringName) -> Vector2i:
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			if GameState.get_cell(x, y) == id:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
