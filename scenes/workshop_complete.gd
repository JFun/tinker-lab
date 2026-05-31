extends Control
## End-game celebration overlay. Fires once when the player discovers all
## inventions. Dim background, gold-bordered panel, list of discoveries, and
## a "Continue Tinkering" dismiss button. Re-show is gated by
## GameState.workshop_complete_seen so it never pesters after the first view.

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.gui_input.connect(func(_e): pass)  # swallow background clicks
	add_child(dim)

	# Wrap the content vertically (centered) rather than stretching to a fixed
	# tall box — the trophy list is short, so a fixed box left a huge empty void.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.06; panel.anchor_right = 0.94
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.15, 0.08)
	sb.border_color = Color(1.0, 0.78, 0.30)
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 18;  sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	# Star flourish — a celebratory crown above the title.
	var stars := Label.new()
	stars.text = "★ ★ ★ ★ ★"
	stars.add_theme_font_size_override("font_size", 26)
	stars.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stars)

	var title := Label.new()
	title.text = "Workshop Master!"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := Label.new()
	var total: int = Items.all_inventions().size()
	sub.text = "You rebuilt the whole village — all %d inventions discovered!" % total
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)

	# Trophy list of all discoveries, gold-tier highlighted for masterworks.
	# Laid out directly (no expanding scroll) so the panel wraps tight to it.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for id in Items.all_inventions():
		var d: Items.ItemDef = Items.get_def(id)
		if d == null: continue
		var row := Label.new()
		# ★ = masterwork, • = regular invention (font-safe glyphs; emoji tofu on iOS)
		var prefix := "★ " if d.tier == Items.Tier.MASTERWORK else "• "
		row.text = prefix + d.name
		row.add_theme_font_size_override("font_size", 15)
		var col: Color = Color(1.0, 0.78, 0.30) if d.tier == Items.Tier.MASTERWORK \
			else Color(0.95, 0.90, 0.75)
		row.add_theme_color_override("font_color", col)
		grid.add_child(row)

	# Future-release teaser — set apart in a soft cyan so it reads as a promise,
	# not a sign-off. Gives the finale somewhere to point beyond "the end".
	var teaser := Label.new()
	teaser.text = "New districts, NPCs, and contraptions are on the way in a future update. Stay tuned — and thank you for tinkering!"
	teaser.add_theme_font_size_override("font_size", 16)
	teaser.add_theme_color_override("font_color", Color(0.62, 0.90, 0.85))
	teaser.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(teaser)

	var ok := Button.new()
	ok.text = "Continue Tinkering  →"
	ok.add_theme_font_size_override("font_size", 22)
	ok.custom_minimum_size = Vector2(0, 64)
	var ok_sb := StyleBoxFlat.new()
	ok_sb.bg_color = Color(1.0, 0.78, 0.30)
	ok_sb.set_corner_radius_all(10)
	ok_sb.content_margin_top = 10; ok_sb.content_margin_bottom = 10
	ok.add_theme_stylebox_override("normal", ok_sb)
	var ok_hover := ok_sb.duplicate()
	ok_hover.bg_color = Color(1.0, 0.85, 0.45)
	ok.add_theme_stylebox_override("hover", ok_hover)
	ok.add_theme_stylebox_override("pressed", ok_hover)
	ok.add_theme_color_override("font_color", Color(0.20, 0.13, 0.05))
	ok.add_theme_color_override("font_hover_color", Color(0.20, 0.13, 0.05))
	ok.add_theme_color_override("font_pressed_color", Color(0.20, 0.13, 0.05))
	ok.pressed.connect(queue_free)
	v.add_child(ok)
