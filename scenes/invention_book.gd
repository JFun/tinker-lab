extends Control
## Invention Book modal: lists all inventions+masterworks, ??? for undiscovered.
## Set highlight_id before adding to the tree to auto-scroll + pulse one entry.

@export var highlight_id: StringName = &""

var _scroll: ScrollContainer
var _highlighted_box: PanelContainer
var _highlight_t: float = 0.0

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.03; panel.anchor_right = 0.97
	panel.anchor_top = 0.06; panel.anchor_bottom = 0.94
	add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.13, 0.08)
	sb.set_border_width_all(0)  # no outer border — let the dimmed bg define the edge
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	# Header row: title + close X
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.90, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total := Items.all_inventions().size()
	title.text = "Recipes  %d / %d" % [GameState.discovered.size(), total]
	header.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.add_theme_font_size_override("font_size", 32)
	close.add_theme_color_override("font_color", Color(0.85, 0.70, 0.45))
	close.custom_minimum_size = Vector2(64, 64)
	close.pressed.connect(queue_free)
	header.add_child(close)

	# Thin separator line
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.40, 0.30, 0.18, 0.50)
	v.add_child(sep)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)

	var all_inv := Items.all_inventions()
	var i := 0
	while i < all_inv.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		for j in 2:
			if i + j < all_inv.size():
				var id: StringName = all_inv[i + j]
				var box: PanelContainer = _make_entry(id)
				box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(box)
				if id == highlight_id:
					_highlighted_box = box
			else:
				# Empty spacer for odd count
				var spacer := Control.new()
				spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(spacer)
		i += 2

	if _highlighted_box != null:
		# Defer: layout pass needed before .position is meaningful.
		await get_tree().process_frame
		await get_tree().process_frame
		# Scroll so the highlighted entry sits near the top of the viewport.
		var y: float = _highlighted_box.global_position.y - list.global_position.y
		var pad: float = 40.0
		_scroll.scroll_vertical = int(max(0.0, y - pad))
		_highlight_t = 1.0
		set_process(true)

func _process(delta: float) -> void:
	if _highlighted_box == null:
		set_process(false)
		return
	if _highlight_t > 0.0:
		_highlight_t = max(0.0, _highlight_t - delta / 3.0)
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		var boost: float = 1.0 + 0.6 * _highlight_t * pulse
		_highlighted_box.modulate = Color(boost, boost, boost * 0.92, 1.0)
	else:
		_highlighted_box.modulate = Color(1.08, 1.08, 1.0, 1.0)
		set_process(false)

func _make_entry(id: StringName) -> PanelContainer:
	var d: Items.ItemDef = Items.get_def(id)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, 72)
	var bsb := StyleBoxFlat.new()
	var discovered := GameState.is_discovered(id)
	if discovered:
		bsb.bg_color = Color(0.24, 0.18, 0.11)
	else:
		bsb.bg_color = Color(0.15, 0.11, 0.07)
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(10)
	bsb.content_margin_left = 10; bsb.content_margin_right = 10
	bsb.content_margin_top = 8; bsb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", bsb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)

	# Glyph swatch — colored icon on minimal bg
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(52, 52)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ssb := StyleBoxFlat.new()
	ssb.set_corner_radius_all(8)
	ssb.set_border_width_all(0)
	if discovered:
		ssb.bg_color = Color(0.16, 0.12, 0.08)
	else:
		ssb.bg_color = Color(0.12, 0.09, 0.06)
	swatch.add_theme_stylebox_override("panel", ssb)

	var glyph_lbl := Label.new()
	glyph_lbl.text = d.glyph
	glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_lbl.add_theme_font_size_override("font_size", 30)
	var glyph_ink: Color
	if discovered:
		glyph_ink = d.color.lightened(0.35)
		glyph_ink.a = 0.95
	else:
		glyph_ink = Color(0.40, 0.35, 0.25)
	glyph_lbl.add_theme_color_override("font_color", glyph_ink)
	swatch.add_child(glyph_lbl)
	h.add_child(swatch)

	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color",
		Color(0.95, 0.88, 0.60) if discovered else Color(0.55, 0.48, 0.32))
	var is_target := (id == highlight_id)
	var name_str := d.name if (discovered or is_target) else "???"
	var recipe := _recipe_text_for(id)
	var sub_str := recipe if recipe != "" else ""
	lbl.text = "%s\n%s" % [name_str, sub_str] if sub_str != "" else name_str
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(lbl)
	return box

func _recipe_text_for(id: StringName) -> String:
	for key in Items.cross:
		if Items.cross[key] == id:
			var ps: PackedStringArray = String(key).split("|")
			var a: Items.ItemDef = Items.get_def(StringName(ps[0]))
			var b: Items.ItemDef = Items.get_def(StringName(ps[1]))
			if a and b: return "%s + %s" % [a.name, b.name]
	return ""

func _on_dim_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		queue_free()
