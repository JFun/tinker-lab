extends Control
## First-run tutorial overlay. Dim background + a stack of clear steps + a
## "Got it" dismiss button. Re-openable via the "?" button on the workbench.

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
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	_add_title(v, "Welcome to the Workshop")

	_add_step(v, "★", "GOAL: discover all 25 inventions (5 are Masterworks).\n"
		+ "The counter at the top-left shows your progress toward the end.")
	_add_step(v, "1.", "Drag a SAME-COLOR pair together to upgrade.\n"
		+ "Junk → Component → Part (3 tiers of upgrades).")
	_add_step(v, "2.", "Once you have two DIFFERENT parts, combine them\n"
		+ "to INVENT (Fuel Tank + Boiler = Oven).")
	_add_step(v, "3.", "While dragging: GREEN = will merge, CYAN = clear\n"
		+ "duplicate, BLUE = empty cell, RED = no recipe.")
	_add_step(v, "4.", "Drag any item onto the recycle panel to clear its slot. If\n"
		+ "you ever fully soft-lock, the chute auto-scraps for you — no dead ends.")
	_add_step(v, "5.", "Tap the Deliver button when your invention is on the board,\n"
		+ "then watch the village light up.")
	_add_step(v, "?", "STUCK ON A RECIPE? Tap Recipes below — every undiscovered\n"
		+ "invention shows its recipe (e.g. \"??? = Frame + Lantern\").")

	# Primary CTA: open the Book directly — this is the answer to "how do I
	# invent X?", which is the #1 thing players Google.
	var recipes_btn := Button.new()
	recipes_btn.text = "Open Recipes"
	recipes_btn.add_theme_font_size_override("font_size", 20)
	recipes_btn.custom_minimum_size = Vector2(0, 56)
	var cta := StyleBoxFlat.new()
	cta.bg_color = Color(1.0, 0.78, 0.30)
	cta.border_color = Color(1.0, 0.95, 0.55)
	cta.set_border_width_all(2)
	cta.set_corner_radius_all(10)
	recipes_btn.add_theme_stylebox_override("normal", cta)
	recipes_btn.add_theme_stylebox_override("hover", cta)
	recipes_btn.add_theme_stylebox_override("pressed", cta)
	recipes_btn.add_theme_color_override("font_color", Color(0.12, 0.06, 0.02))
	recipes_btn.pressed.connect(_open_recipes)
	v.add_child(recipes_btn)

	var ok := Button.new()
	ok.text = "Got it — let me tinker"
	ok.add_theme_font_size_override("font_size", 18)
	ok.flat = true
	ok.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	ok.custom_minimum_size = Vector2(0, 44)
	ok.pressed.connect(_dismiss)
	v.add_child(ok)

func _add_title(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.65))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)

func _add_step(parent: Node, num: String, body: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var n := Label.new()
	n.text = num
	n.add_theme_font_size_override("font_size", 24)
	n.add_theme_color_override("font_color", Color(1.0, 0.75, 0.30))
	n.custom_minimum_size = Vector2(36, 0)
	h.add_child(n)
	var b := Label.new()
	b.text = body
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)

func _dismiss() -> void:
	GameState.tutorial_seen = true
	GameState.save_game()
	queue_free()

func _open_recipes() -> void:
	# Hand off to the Book modal. Add it to our parent so it survives our
	# queue_free below (children get freed with us).
	GameState.tutorial_seen = true
	GameState.save_game()
	var parent := get_parent()
	queue_free()
	if parent:
		parent.add_child(preload("res://scenes/invention_book.tscn").instantiate())

func _swallow(_event: InputEvent) -> void:
	pass  # block clicks from reaching scene below
