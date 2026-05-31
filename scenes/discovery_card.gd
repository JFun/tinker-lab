extends Control
## Invention discovery card — shows WHAT was invented, WHY (ingredient roles),
## and HOW (one-line story). Appears as a brief modal overlay on merge.

@export var invention_id: StringName = &""

func _ready() -> void:
	var def: Items.ItemDef = Items.get_def(invention_id)
	if def == null:
		queue_free()
		return
	var parents: Array = Items.get_parents(invention_id)
	var story: String = Items.get_story(invention_id)

	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	# Dim backdrop. Dismiss is handled in _input (see below) rather than via the
	# dim's gui_input, because the card panel sits on top of the dim and (like all
	# Controls) defaults to MOUSE_FILTER_STOP — it swallows taps that land inside
	# the card, so the dim only ever saw taps in the margins. Root _input catches
	# a press anywhere over any child.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)

	# Ignore input for one frame so the merge's own touch-release can't instantly
	# dismiss the freshly-shown card.
	set_process_input(false)
	get_tree().create_timer(0.05).timeout.connect(func(): set_process_input(true))

	# Card panel — centered, vertically centered, content-sized.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.05; panel.anchor_right = 0.95
	panel.anchor_top = 0.15; panel.anchor_bottom = 0.75
	add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.08)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 24; sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	# Title: "Invention Discovered!"
	var title := Label.new()
	title.text = "Invention Discovered!"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	# Merge row: [Parent A] + [Parent B]
	if parents.size() == 2:
		var merge_row := HBoxContainer.new()
		merge_row.alignment = BoxContainer.ALIGNMENT_CENTER
		merge_row.add_theme_constant_override("separation", 14)
		v.add_child(merge_row)

		var pa: Items.ItemDef = parents[0]
		var pb: Items.ItemDef = parents[1]
		merge_row.add_child(_make_ingredient_tile(pa))

		var plus := Label.new()
		plus.text = "+"
		plus.add_theme_font_size_override("font_size", 36)
		plus.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		merge_row.add_child(plus)

		merge_row.add_child(_make_ingredient_tile(pb))

	# Arrow down
	var arrow := Label.new()
	arrow.text = "▼"
	arrow.add_theme_font_size_override("font_size", 32)
	arrow.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(arrow)

	# Result tile — big, centered
	var result_row := HBoxContainer.new()
	result_row.alignment = BoxContainer.ALIGNMENT_CENTER
	result_row.add_theme_constant_override("separation", 16)
	v.add_child(result_row)
	result_row.add_child(_make_result_tile(def))

	var result_name := Label.new()
	result_name.text = def.name
	result_name.add_theme_font_size_override("font_size", 30)
	result_name.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50))
	result_row.add_child(result_name)

	# Story sentence
	if story != "":
		var story_lbl := Label.new()
		story_lbl.text = "\"%s\"" % story
		story_lbl.add_theme_font_size_override("font_size", 22)
		story_lbl.add_theme_color_override("font_color", Color(0.90, 0.82, 0.58))
		story_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		story_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(story_lbl)

	# Ingredient roles line
	if parents.size() == 2:
		var roles := Label.new()
		var pa: Items.ItemDef = parents[0]
		var pb: Items.ItemDef = parents[1]
		roles.text = "%s + %s = %s" % [pa.name, pb.name, def.name]
		roles.add_theme_font_size_override("font_size", 18)
		roles.add_theme_color_override("font_color", Color(0.65, 0.58, 0.40))
		roles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(roles)

	# Tap to dismiss label
	var dismiss := Label.new()
	dismiss.text = "Tap anywhere to continue"
	dismiss.add_theme_font_size_override("font_size", 18)
	dismiss.add_theme_color_override("font_color", Color(0.50, 0.45, 0.35))
	dismiss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dismiss)

	# Auto-dismiss after 8 seconds
	var timer := Timer.new()
	timer.wait_time = 8.0
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()

func _make_ingredient_tile(d: Items.ItemDef) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(100, 100)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = d.color
	tsb.set_corner_radius_all(12)
	tsb.set_border_width_all(2)
	tsb.border_color = Color(1, 1, 1, 0.35)
	tile.add_theme_stylebox_override("panel", tsb)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(vb)
	var glyph := Label.new()
	glyph.text = d.glyph
	glyph.add_theme_font_size_override("font_size", 38)
	glyph.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(glyph)
	var nm := Label.new()
	nm.text = d.name
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	return tile

func _make_result_tile(d: Items.ItemDef) -> PanelContainer:
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
	nm.add_theme_font_size_override("font_size", 18)
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
