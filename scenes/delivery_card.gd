extends Control
## Daily-delivery card — a blocking modal shown when a returning player arrives at
## the workbench with a pending streak crate. Toast + board-glow proved too easy to
## miss while tapping between workshops, so the reward now announces itself with a
## centered, tap-to-dismiss card (same unmissable pattern as discovery_card.gd).
## The crate tiles are already placed + spotlighted on the board underneath; this
## card just makes sure the player NOTICES, then reveals the glow on dismiss.

@export var streak: int = 1
@export var item_ids: Array = []  # of StringName, the delivered crate contents

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	# Dim backdrop. Dismiss handled in _input (the card panel sits on top and eats
	# taps with its default MOUSE_FILTER_STOP — same gotcha discovery_card documents).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)

	# Eat input for one frame so the tap that entered the workshop can't instantly
	# dismiss the freshly-shown card.
	set_process_input(false)
	get_tree().create_timer(0.05).timeout.connect(func(): set_process_input(true))

	var panel := PanelContainer.new()
	panel.anchor_left = 0.08; panel.anchor_right = 0.92
	panel.anchor_top = 0.22; panel.anchor_bottom = 0.66
	add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.08)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 24; sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	# Title — "Welcome back!" on day 1 (no streak yet), "Day N Streak!" thereafter.
	var title := Label.new()
	title.text = "Welcome back!" if streak <= 1 else "Day %d Streak!" % streak
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = "Here's your delivery crate:"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.90, 0.82, 0.58))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# Item tile(s) — centered row.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	for id in item_ids:
		var d: Items.ItemDef = Items.get_def(id)
		if d != null:
			row.add_child(_make_tile(d))

	# Item name line (single item) — friendly reinforcement.
	if item_ids.size() == 1:
		var d: Items.ItemDef = Items.get_def(item_ids[0])
		if d != null:
			var nm := Label.new()
			nm.text = "Free %s" % d.name
			nm.add_theme_font_size_override("font_size", 22)
			nm.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50))
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(nm)

	# Hint: it's already on the board, glowing.
	var glow_hint := Label.new()
	glow_hint.text = "Added to your bench — look for the glow."
	glow_hint.add_theme_font_size_override("font_size", 18)
	glow_hint.add_theme_color_override("font_color", Color(0.65, 0.58, 0.40))
	glow_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(glow_hint)

	var dismiss := Label.new()
	dismiss.text = "Tap anywhere to continue"
	dismiss.add_theme_font_size_override("font_size", 18)
	dismiss.add_theme_color_override("font_color", Color(0.50, 0.45, 0.35))
	dismiss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dismiss)

func _make_tile(d: Items.ItemDef) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(110, 110)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = d.color
	tsb.set_corner_radius_all(14)
	tsb.set_border_width_all(3)
	tsb.border_color = Color(1, 1, 1, 0.55)
	tsb.shadow_color = Color(1.0, 0.85, 0.30, 0.30)
	tsb.shadow_size = 16
	tile.add_theme_stylebox_override("panel", tsb)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(vb)
	var glyph := Label.new()
	glyph.text = d.glyph
	glyph.add_theme_font_size_override("font_size", 44)
	glyph.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(glyph)
	var nm := Label.new()
	nm.text = d.name
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.90))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	return tile

func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		queue_free()
