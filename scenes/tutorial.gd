extends Control
## First-run tutorial overlay. Dim background + a stack of clear steps + a
## single "let me tinker" button that dismisses it. Re-openable any time via
## the "?" Help button on the workbench's bottom tab bar.

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.gui_input.connect(_swallow)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.06; panel.anchor_right = 0.94
	panel.anchor_top = 0.12; panel.anchor_bottom = 0.88
	add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.15, 0.08)
	sb.border_color = Color(0.85, 0.65, 0.30)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 18; sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)

	_add_title(v, "Welcome to the Workshop")

	# No manual line breaks — the body labels auto-wrap (WORD_SMART), so the text
	# reflows cleanly at any font size.
	_add_step(v, "★", "GOAL: discover all 25 inventions (5 are Masterworks). "
		+ "The Recipes tab keeps your tally (\"Recipes 3 / 25\").")
	_add_step(v, "1.", "Drag a SAME-COLOR pair together to upgrade. "
		+ "Junk → Crafted → Part (3 tiers to climb).")
	_add_step(v, "2.", "Once you have two DIFFERENT parts, combine them "
		+ "to INVENT (Fuel Tank + Boiler = Oven).")
	_add_step(v, "3.", "While dragging: GREEN = will merge, CYAN = clear "
		+ "duplicate, BLUE = empty cell, RED = no recipe.")
	_add_step(v, "4.", "Drag any item onto the recycle panel to clear its slot. "
		+ "If you ever fully soft-lock, the chute auto-scraps for you — no dead ends.")
	_add_step(v, "5.", "Tap the Deliver button when your invention is on the board, "
		+ "then watch the village light up.")
	_add_step(v, "?", "STUCK ON A RECIPE? Tap Recipes below — every undiscovered "
		+ "invention shows its recipe (e.g. \"??? = Frame + Lantern\").")

	# Single primary CTA. A first-time player hasn't placed a tile yet, so the
	# natural action is to start playing — the Recipes tab (always in the bottom
	# bar, and called out in step "?") is one tap away whenever they get stuck.
	var ok := Button.new()
	ok.text = "Got it — let me tinker"
	ok.add_theme_font_size_override("font_size", 23)
	ok.custom_minimum_size = Vector2(0, 62)
	var cta := StyleBoxFlat.new()
	cta.bg_color = Color(1.0, 0.78, 0.30)
	cta.border_color = Color(1.0, 0.95, 0.55)
	cta.set_border_width_all(2)
	cta.set_corner_radius_all(10)
	ok.add_theme_stylebox_override("normal", cta)
	ok.add_theme_stylebox_override("hover", cta)
	ok.add_theme_stylebox_override("pressed", cta)
	ok.add_theme_color_override("font_color", Color(0.12, 0.06, 0.02))
	ok.pressed.connect(_dismiss)
	v.add_child(ok)

func _add_title(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)

func _add_step(parent: Node, num: String, body: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var n := Label.new()
	n.text = num
	n.add_theme_font_size_override("font_size", 28)
	n.add_theme_color_override("font_color", Color(1.0, 0.75, 0.30))
	n.custom_minimum_size = Vector2(40, 0)
	h.add_child(n)
	var b := Label.new()
	b.text = body
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)

func _dismiss() -> void:
	GameState.tutorial_seen = true
	GameState.tutorial_completed.emit()
	GameState.save_game()
	queue_free()

func _swallow(_event: InputEvent) -> void:
	pass  # block clicks from reaching scene below
