extends Control
## Per-level completion celebration. Shown (chained AFTER the per-item discovery
## card) once all 5 targets of a level are discovered. The single CTA "Next Level
## →" jumps straight into the following level (the workbench crossfades to a fresh
## board) — no village detour. The village hub stays reachable via the bottom tab.
## The grand all-inventions finale is handled separately by workshop_complete.tscn.

signal return_to_village
signal advance_to_next  # primary CTA: jump straight into the next level

@export var level_idx: int = 0
var building_label: String = ""  # e.g. "Bakery" — from the completed NPC quest
var thanks: String = ""          # the NPC's thank-you line

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.gui_input.connect(func(_e): pass)  # swallow clicks
	add_child(dim)

	# Fixed width, but let the panel WRAP its content vertically (centered on
	# screen) instead of stretching to a tall fixed box — otherwise the CTA
	# floats in a vast empty modal and reads as tiny.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.08; panel.anchor_right = 0.92
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.15, 0.08)
	sb.border_color = Color(1.0, 0.78, 0.30)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 18;  sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var lvl: Dictionary = Items.LEVELS[level_idx]
	var title := Label.new()
	title.text = ("%s Complete!" % building_label) if building_label != "" \
		else ("Level %d Complete!" % (level_idx + 1))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := Label.new()
	sub.text = thanks if thanks != "" \
		else "You mastered \"%s\" — all 5 inventions discovered." % lvl.name
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)

	# Discovered list with glyphs.
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	for t in lvl.targets:
		var d: Items.ItemDef = Items.get_def(t)
		var col := VBoxContainer.new()
		grid.add_child(col)
		var swatch := Label.new()
		swatch.text = d.glyph
		swatch.add_theme_font_size_override("font_size", 26)
		swatch.add_theme_color_override("font_color", d.color)
		swatch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(swatch)
		var name_lbl := Label.new()
		name_lbl.text = d.name
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lbl)

	# Single clear CTA: continue straight into the next level (the workbench
	# crossfades to a fresh board). The village hub remains reachable any time via
	# the bottom tab, so we don't clutter this celebration with a second button.
	if level_idx + 1 < Items.LEVELS.size():
		var next_lvl: Dictionary = Items.LEVELS[level_idx + 1]
		var preview := Label.new()
		preview.text = "Next  →  Level %d: %s" % [level_idx + 2, next_lvl.name]
		preview.add_theme_font_size_override("font_size", 18)
		preview.add_theme_color_override("font_color", Color(0.80, 1.0, 0.65))
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(preview)

		var go_next := Button.new()
		go_next.text = "Next Level  →"
		go_next.add_theme_font_size_override("font_size", 22)
		go_next.custom_minimum_size = Vector2(0, 80)
		go_next.pressed.connect(func():
			advance_to_next.emit()
			queue_free())
		v.add_child(go_next)
	else:
		# Defensive — the all-inventions finale normally pre-empts this modal, so
		# this branch shouldn't show in practice. Fall back to the village hub.
		var back := Button.new()
		back.text = "Back to Village  →"
		back.add_theme_font_size_override("font_size", 20)
		back.custom_minimum_size = Vector2(0, 56)
		back.pressed.connect(func():
			return_to_village.emit()
			queue_free())
		v.add_child(back)
