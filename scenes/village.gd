extends Control
## Village: main menu. Shows 5 NPCs with buildings, broken or repaired.
## Bottom tab bar (Village · Recipes · More) — no oversized Workshop CTA.

signal go_workbench(npc_id: StringName)

const N_NPCS := 5
const TEXT := Color(1, 0.92, 0.65)
const DIM := Color(0.55, 0.45, 0.35)
const GOLD := Color(1.0, 0.78, 0.30)

# Building icons are CUSTOM-DRAWN (UIIcon, scenes/ui_icon.gd), never font
# glyphs — emoji like ☀⚙✉🏘📖 tofu on iOS even though they render on desktop.
const BUILDING_KINDS := ["lamp", "clock", "star", "loaf", "envelope"]
const UIIcon := preload("res://scenes/ui_icon.gd")

var _bg: ColorRect
var _scroll: ScrollContainer
var _list: VBoxContainer
var _tab_bar_bg: ColorRect
var _tab_bar_hairline: ColorRect
var _village_pedestal: Panel
var _tab_village: Button
var _tab_recipes: Button
var _tab_more: Button

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	_build_ui()
	GameState.quest_completed.connect(func(_id): _refresh())
	Audio.play_bgm("village")
	_refresh()
	resized.connect(_layout)
	_layout()
	await get_tree().process_frame
	_layout()

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.12, 0.09, 0.06)
	_bg.anchor_right = 1.0; _bg.anchor_bottom = 1.0
	add_child(_bg)

	# Scrollable list of NPC cards
	_scroll = ScrollContainer.new()
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	# Tab bar
	_tab_bar_bg = ColorRect.new()
	_tab_bar_bg.color = Color(0.10, 0.07, 0.05)
	add_child(_tab_bar_bg)
	_tab_bar_hairline = ColorRect.new()
	_tab_bar_hairline.color = Color(0.50, 0.38, 0.22)
	add_child(_tab_bar_hairline)
	_village_pedestal = Panel.new()
	var ped_sb := StyleBoxFlat.new()
	ped_sb.bg_color = Color(0.18, 0.13, 0.08)
	ped_sb.border_color = GOLD
	ped_sb.set_border_width_all(3)
	ped_sb.set_corner_radius_all(64)
	ped_sb.shadow_color = Color(0, 0, 0, 0.5)
	ped_sb.shadow_size = 4
	_village_pedestal.add_theme_stylebox_override("panel", ped_sb)
	add_child(_village_pedestal)
	_tab_recipes = _make_tab("book", "Recipes")
	_tab_more = _make_tab("dots", "More")
	_tab_village = _make_tab("house", "Village")
	add_child(_tab_recipes)
	add_child(_tab_more)
	add_child(_tab_village)
	# Village pedestal icon is larger and centered in the gold circle.
	var v_glyph := _tab_village.get_node("GlyphIcon") as UIIcon
	v_glyph.offset_top = 22
	v_glyph.offset_bottom = 96
	v_glyph.offset_left = 30
	v_glyph.offset_right = -30
	var v_text := _tab_village.get_node("TextLabel") as Label
	v_text.add_theme_font_size_override("font_size", 14)
	v_text.offset_top = -28
	v_text.offset_bottom = -8
	_tab_recipes.pressed.connect(_open_book)
	_tab_more.pressed.connect(_open_more)
	_set_tab_active(_tab_village, true)
	_set_tab_active(_tab_recipes, false)
	_set_tab_active(_tab_more, false)

func _make_tab(kind: String, label: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	var glyph_icon := UIIcon.new(kind, DIM)
	glyph_icon.name = "GlyphIcon"
	glyph_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_icon.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glyph_icon.offset_top = 8; glyph_icon.offset_bottom = 40
	glyph_icon.offset_left = 28; glyph_icon.offset_right = -28
	btn.add_child(glyph_icon)
	var text_lbl := Label.new()
	text_lbl.name = "TextLabel"
	text_lbl.text = label
	text_lbl.add_theme_font_size_override("font_size", 12)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	text_lbl.offset_top = -22; text_lbl.offset_bottom = -4
	btn.add_child(text_lbl)
	return btn

func _set_tab_active(btn: Button, active: bool) -> void:
	var c: Color = GOLD if active else DIM
	(btn.get_node("GlyphIcon") as UIIcon).set_color(c)
	(btn.get_node("TextLabel") as Label).add_theme_color_override("font_color", c)

func _layout() -> void:
	var w := size.x; var h := size.y
	var safe_top: float = 50.0
	var safe_bot: float = 16.0
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0:
		safe_top = max(safe_top, float(safe.position.y))
		var inset_bot := float(get_viewport_rect().size.y - (safe.position.y + safe.size.y))
		safe_bot = max(safe_bot, inset_bot)

	# Tab bar
	var tab_h: float = 88.0
	var bar_y := h - safe_bot - tab_h
	_tab_bar_bg.position = Vector2(0, bar_y)
	_tab_bar_bg.size = Vector2(w, tab_h + safe_bot)
	_tab_bar_hairline.position = Vector2(0, bar_y)
	_tab_bar_hairline.size = Vector2(w, 2)
	var tab_w := w / 3.0
	_tab_recipes.position = Vector2(0, bar_y)
	_tab_recipes.size = Vector2(tab_w, tab_h)
	_tab_more.position = Vector2(tab_w * 2, bar_y)
	_tab_more.size = Vector2(tab_w, tab_h)
	var ped_size: float = 124.0
	var ped_lift: float = 28.0
	var ped_x := (w - ped_size) * 0.5
	var ped_y := bar_y - ped_lift
	_village_pedestal.position = Vector2(ped_x, ped_y)
	_village_pedestal.size = Vector2(ped_size, ped_size)
	_tab_village.position = Vector2(ped_x, ped_y)
	_tab_village.size = Vector2(ped_size, ped_size)

	# Scroll area
	var scroll_top := safe_top + 36
	var scroll_bottom := bar_y - ped_lift - 12
	_scroll.position = Vector2(12, scroll_top)
	_scroll.size = Vector2(w - 24, scroll_bottom - scroll_top)

func _refresh() -> void:
	# Clear and rebuild cards
	for c in _list.get_children():
		c.queue_free()

	var done_count := 0
	for i in N_NPCS:
		var npc: Npcs.NpcDef = Npcs.npcs[i]
		var status := GameState.quest_status(npc.id)
		if status == "done":
			done_count += 1
		var card := _make_npc_card(i, npc, status)
		_list.add_child(card)

	var t := float(done_count) / N_NPCS
	_bg.color = Color(0.12, 0.09, 0.06).lerp(Color(0.22, 0.16, 0.10), t)

func _make_npc_card(idx: int, npc: Npcs.NpcDef, status: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var _npc_id := npc.id
	card.gui_input.connect(func(ev: InputEvent):
		var pressed: bool = (ev is InputEventMouseButton and ev.pressed) \
			or (ev is InputEventScreenTouch and ev.pressed)
		if pressed:
			_on_npc_pressed(_npc_id))

	var done := status == "done"

	# Card bg — tinted with NPC's signature color for distinct identity.
	# Same color family as the workbench goal banner when working for this NPC.
	var sb := StyleBoxFlat.new()
	if done:
		sb.bg_color = npc.color.darkened(0.72).lerp(Color(0.22, 0.30, 0.18), 0.25)
	else:
		sb.bg_color = npc.color.darkened(0.58)
	sb.set_corner_radius_all(14)
	# Left accent bar — NPC's bold signature color
	sb.border_width_left = 6
	sb.border_width_top = 0; sb.border_width_right = 0; sb.border_width_bottom = 0
	sb.border_color = npc.color if not done else Color(0.55, 0.80, 0.40)
	sb.content_margin_left = 20; sb.content_margin_right = 16
	sb.content_margin_top = 18; sb.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", sb)

	# Content: HBox [ glyph panel | text column ]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Building glyph — colored square, bigger
	var glyph_panel := PanelContainer.new()
	glyph_panel.custom_minimum_size = Vector2(72, 72)
	glyph_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = npc.color.darkened(0.40)
	gsb.set_corner_radius_all(12)
	gsb.set_border_width_all(0)
	glyph_panel.add_theme_stylebox_override("panel", gsb)
	var icon := UIIcon.new(BUILDING_KINDS[idx], npc.color.lightened(0.45) if not done else Color(0.70, 0.92, 0.60))
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12; icon.offset_top = 12
	icon.offset_right = -12; icon.offset_bottom = -12
	glyph_panel.add_child(icon)
	h.add_child(glyph_panel)

	# Text column — building name is the hero
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	# Building name — hero text, NPC-colored
	var building_lbl := Label.new()
	building_lbl.text = npc.building_label
	building_lbl.add_theme_font_size_override("font_size", 22)
	building_lbl.add_theme_color_override("font_color", npc.color.lightened(0.35))
	building_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(building_lbl)

	# NPC name — secondary
	var name_lbl := Label.new()
	name_lbl.text = npc.name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	# Progress
	var progress_lbl := Label.new()
	progress_lbl.add_theme_font_size_override("font_size", 15)
	progress_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if done:
		progress_lbl.text = "✓ Complete"
		progress_lbl.add_theme_color_override("font_color", Color(0.60, 0.90, 0.50))
	else:
		var got := 0
		if npc.level >= 0 and npc.level < Items.LEVELS.size():
			for t in Items.LEVELS[npc.level].targets:
				if GameState.is_discovered(t): got += 1
		progress_lbl.text = "%d / 5 inventions" % got
		progress_lbl.add_theme_color_override("font_color", DIM)
	v.add_child(progress_lbl)

	return card

func _on_npc_pressed(npc_id: StringName) -> void:
	var npc := Npcs.by_id(npc_id)
	if npc == null: return
	if npc.level >= 0 and npc.level != GameState.current_level:
		GameState.advance_to_level(npc.level)
	var status := GameState.quest_status(npc_id)
	if status != "done":
		GameState.set_quest_status(npc_id, "active")
	GameState.save_game()
	go_workbench.emit(npc_id)

func _open_book() -> void:
	add_child(preload("res://scenes/invention_book.tscn").instantiate())

func _open_more() -> void:
	add_child(_build_more_sheet())

func _build_more_sheet() -> Control:
	var sheet := Control.new()
	sheet.anchor_right = 1.0; sheet.anchor_bottom = 1.0
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.anchor_right = 1.0; backdrop.anchor_bottom = 1.0
	backdrop.gui_input.connect(func(ev):
		var pressed: bool = (ev is InputEventScreenTouch and ev.pressed) \
			or (ev is InputEventMouseButton and ev.pressed)
		if pressed:
			sheet.queue_free())
	sheet.add_child(backdrop)

	var centerer := CenterContainer.new()
	centerer.anchor_right = 1.0; centerer.anchor_bottom = 1.0
	centerer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(centerer)

	var card := PanelContainer.new()
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.18, 0.14, 0.10)
	card_sb.set_border_width_all(0)
	card_sb.set_corner_radius_all(12)
	card_sb.content_margin_left = 24; card_sb.content_margin_right = 24
	card_sb.content_margin_top = 24; card_sb.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", card_sb)
	card.custom_minimum_size = Vector2(380, 0)
	centerer.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	# Sound on/off toggle. Text + color cue rather than 🔊/🔇 (those glyphs are
	# tofu on iOS); flips between a green "On" and a muted-grey "Off".
	var sound_btn := _make_sheet_button("", 18)
	_update_sound_btn(sound_btn)
	vb.add_child(sound_btn)
	sound_btn.pressed.connect(func():
		Audio.set_muted(not GameState.muted)
		Audio.play_sfx("place")  # audible confirm when turning sound back ON
		_update_sound_btn(sound_btn))

	var reset_btn := _make_sheet_button("↺  Reset Game", 18)
	reset_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
	vb.add_child(reset_btn)
	reset_btn.pressed.connect(func(): _confirm_reset(reset_btn, sheet))

	var close_btn := _make_sheet_button("Close", 16)
	vb.add_child(close_btn)
	close_btn.pressed.connect(func(): sheet.queue_free())

	return sheet

func _update_sound_btn(btn: Button) -> void:
	if GameState.muted:
		btn.text = "Sound:  Off"
		btn.add_theme_color_override("font_color", Color(0.70, 0.66, 0.58))
	else:
		btn.text = "Sound:  On"
		btn.add_theme_color_override("font_color", Color(0.55, 0.90, 0.55))

func _make_sheet_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.custom_minimum_size = Vector2(0, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.26, 0.20, 0.12)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.32, 0.24, 0.14)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	return b

func _confirm_reset(btn: Button, sheet: Control) -> void:
	const DEFAULT_TEXT := "↺  Reset Game"
	const ARMED_TEXT := "Tap again to confirm"
	if btn.text == DEFAULT_TEXT:
		btn.text = ARMED_TEXT
		btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 4.0
		t.timeout.connect(func():
			if is_instance_valid(btn) and btn.text == ARMED_TEXT:
				btn.text = DEFAULT_TEXT
				btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
			t.queue_free())
		add_child(t)
		t.start()
		return
	GameState.reset()
	sheet.queue_free()
	_refresh()
