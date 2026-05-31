extends SceneTree
## Dev-only: render mockups of two redesigned village bottom-bar variants.
## Run: godot --path . -s scripts/dev/mockup_tabbar.gd
## Outputs: user://mockup_option_a.png, user://mockup_option_b.png

const W := 720
const H := 1558
const OUT_W := 828
const OUT_H := 1792
const BG := Color(0.20, 0.14, 0.09)
const CARD_BG := Color(0.18, 0.14, 0.10)
const CARD_BG_HI := Color(0.26, 0.20, 0.12)
const TEXT := Color(1, 0.92, 0.65)
const DIM := Color(0.55, 0.45, 0.35)
const GOLD := Color(1.0, 0.78, 0.30)

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(OUT_W, OUT_H))
	await process_frame
	await create_timer(0.2).timeout
	for variant in ["a", "b"]:
		var root := _build(variant)
		get_root().add_child(root)
		await process_frame
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://mockup_option_%s.png" % variant)
		print("[mockup] option_%s saved" % variant)
		get_root().remove_child(root)
		root.free()
		await process_frame
		await process_frame
	quit()

func _solid(parent: Node, pos: Vector2, sz: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.position = pos
	r.size = sz
	parent.add_child(r)
	return r

func _label(parent: Node, pos: Vector2, sz: Vector2, text: String, font_size: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _build(variant: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_solid(root, Vector2.ZERO, Vector2(W, H), BG)

	var safe_top := 60.0
	var safe_bot := 34.0

	# === TOP CHROME ===
	# In Option A the right side holds two real icon buttons (book + gear),
	# so the title gets the left half only. In Option B the right side is
	# free for the steam pill.
	var title_right_pad: float = 200.0 if variant == "a" else 220.0
	_label(root, Vector2(24, safe_top), Vector2(W - title_right_pad, 40),
		"Cogsworth Village", 32, TEXT)
	_label(root, Vector2(24, safe_top + 48), Vector2(W - 48, 24),
		"Market Square — 0 / 5 quests  ·  ⚙ 30 / 30" if variant == "a"
		else "Market Square — 0 / 5 quests", 18, DIM)
	if variant == "b":
		_label(root, Vector2(W - 220, safe_top + 6), Vector2(196, 28),
			"⚙ 30 / 30", 22, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		# Option A: two corner icon buttons pinned top-right.
	if variant == "a":
		_corner_icon(root, Vector2(W - 200, safe_top + 4), "📖  Recipes")
		_corner_icon(root, Vector2(W - 200, safe_top + 56), "•••  More")

	# === PROGRESS BAR ===
	_solid(root, Vector2(24, safe_top + 96), Vector2(W - 48, 8), Color(0.10, 0.07, 0.05))

	# === BOTTOM PADDING ===
	var grid_bottom_pad: float
	if variant == "a":
		grid_bottom_pad = safe_bot + 24
	else:
		grid_bottom_pad = safe_bot + 96 + 20  # 96 for tab bar

	# === NPC CARDS ===
	var grid_top := safe_top + 130
	var grid_h := H - grid_top - grid_bottom_pad
	var npc_data := [
		["Baker Burnside", "Bakery", Color(1.0, 0.78, 0.30)],
		["Mayor Gearsworth", "Clock Tower", Color(0.75, 0.55, 1.0)],
		["Lamplighter Lux", "Street Lamps", Color(1.0, 0.95, 0.55)],
		["Postmaster Parcel", "Post Office", Color(0.85, 0.65, 0.40)],
		["Professor Spark", "Observatory", Color(0.50, 0.85, 1.0)],
	]
	var cell_h := (grid_h - 4 * 12) / 5
	for i in 5:
		var d = npc_data[i]
		var is_next := variant == "a" and i == 0
		_npc_card(root, Vector2(24, grid_top + i * (cell_h + 12)),
			Vector2(W - 48, cell_h), d[0], d[1], d[2], is_next)

	# === BOTTOM TAB BAR (Option B only) ===
	if variant == "b":
		var bar_h := 96.0
		var bar_y := H - safe_bot - bar_h
		_solid(root, Vector2(0, bar_y), Vector2(W, bar_h + safe_bot),
			Color(0.10, 0.07, 0.05))
		_solid(root, Vector2(0, bar_y), Vector2(W, 1),
			Color(0.40, 0.30, 0.18))
		var tabs := [
			["🏘", "Village", true],
			["📖", "Recipes", false],
			["•••", "More", false],
		]
		var tab_w := W / 3.0
		for i in tabs.size():
			var t = tabs[i]
			var c: Color = GOLD if t[2] else DIM
			_label(root, Vector2(i * tab_w, bar_y + 14), Vector2(tab_w, 40),
				t[0], 32, c, HORIZONTAL_ALIGNMENT_CENTER)
			_label(root, Vector2(i * tab_w, bar_y + 58), Vector2(tab_w, 20),
				t[1], 14, c, HORIZONTAL_ALIGNMENT_CENTER)

	# Variant stamp at the very bottom of the canvas
	var stamp_y := (H - safe_bot - 22) if variant == "a" else (H - safe_bot + 6)
	_label(root, Vector2(24, stamp_y), Vector2(W - 48, 18),
		("OPTION A — corner icons, NPC cards are the menu" if variant == "a"
		else "OPTION B — bottom nav tab bar, no oversized CTA"),
		13, Color(0.45, 0.36, 0.26))
	return root

func _corner_icon(parent: Node, pos: Vector2, text: String) -> void:
	# Pill-style chip: warm-tone bg, 1px border, single text line.
	var box_size := Vector2(180, 48)
	_solid(parent, pos, box_size, Color(0.30, 0.22, 0.14))
	_solid(parent, pos, Vector2(box_size.x, 1), Color(0.55, 0.42, 0.25))
	_solid(parent, pos + Vector2(0, box_size.y - 1), Vector2(box_size.x, 1), Color(0.55, 0.42, 0.25))
	_solid(parent, pos, Vector2(1, box_size.y), Color(0.55, 0.42, 0.25))
	_solid(parent, pos + Vector2(box_size.x - 1, 0), Vector2(1, box_size.y), Color(0.55, 0.42, 0.25))
	_label(parent, pos, Vector2(box_size.x, box_size.y), text, 20, TEXT,
		HORIZONTAL_ALIGNMENT_CENTER)

func _npc_card(parent: Node, pos: Vector2, sz: Vector2, name_: String,
		building: String, accent: Color, is_next: bool) -> void:
	# Background
	_solid(parent, pos, sz, CARD_BG_HI if is_next else CARD_BG)
	# Subtle 1px border
	var border_c: Color = GOLD if is_next else Color(0.32, 0.24, 0.14)
	_solid(parent, pos, Vector2(sz.x, 1), border_c)
	_solid(parent, pos + Vector2(0, sz.y - 1), Vector2(sz.x, 1), border_c)
	_solid(parent, pos, Vector2(1, sz.y), border_c)
	_solid(parent, pos + Vector2(sz.x - 1, 0), Vector2(1, sz.y), border_c)
	# Left accent stripe in NPC color
	_solid(parent, pos + Vector2(0, 0), Vector2(5, sz.y), accent)
	# Text block
	_label(parent, pos + Vector2(28, 16), Vector2(sz.x - 40, 32),
		name_ + " — " + building, 22, TEXT)
	_label(parent, pos + Vector2(28, 52), Vector2(sz.x - 40, 24),
		("▶  Tap to help" if is_next else "needs help"),
		17, GOLD if is_next else DIM)
