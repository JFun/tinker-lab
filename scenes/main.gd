extends Control
## Entry point. Routes between Village (main menu) and Workbench.

const VILLAGE := preload("res://scenes/village.tscn")
const WORKBENCH := preload("res://scenes/workbench.tscn")

var _current: Node = null

func _ready() -> void:
	# Seed first quest as available so the player has something to do
	for npc in Npcs.npcs:
		if GameState.quest_status(npc.id) == "":
			GameState.set_quest_status(npc.id, "available")
	# UI screenshot mode (dev-only): `godot -- --shoot workbench`
	for a in OS.get_cmdline_user_args():
		if a == "--shoot" or a.begins_with("--shoot="):
			_screenshot_then_quit()
			return
		if a == "--test-hints":
			_test_hints_then_quit()
			return
		if a == "--capture-transition":
			_capture_transition_then_quit()
			return
	show_village()

func _capture_transition_then_quit() -> void:
	# Dev-only: capture the level-completion → "Back to Village" crossfade as a
	# PNG sequence (assembled into a GIF by scripts/dev/transition_gif.sh). Runs
	# inside main.gd so project autoloads are available (a `-s` SceneTree script
	# doesn't get them). Real Metal renderer required — a window briefly appears.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute("user://save.json")
	GameState.tutorial_seen = true
	DisplayServer.window_set_size(Vector2i(720, 1280))

	# Boot to the village (first-load fade-in), then over to the finished board.
	show_village()
	await get_tree().create_timer(0.6).timeout
	show_workbench(&"baker")
	await get_tree().create_timer(0.6).timeout

	# Drop the congrats modal on the workbench, exactly as the real post-discovery
	# flow does once the discovery card is dismissed.
	var lc := preload("res://scenes/level_complete.tscn").instantiate()
	lc.level_idx = 0
	lc.building_label = "Bakery"
	lc.thanks = "Fresh bread for the whole village again — thank you!"
	_current.add_child(lc)
	await get_tree().create_timer(0.5).timeout

	var idx := 0
	for i in 10:  # open on the congrats modal for a beat
		await _grab_frame(idx); idx += 1
	show_village()  # "Back to Village" → _swap crossfade (fire & forget)
	for i in 46:    # capture through the full ~0.32s crossfade
		await _grab_frame(idx); idx += 1
	for i in 8:     # hold on the village
		await _grab_frame(idx); idx += 1
	print("[trans] captured %d frames" % idx)
	get_tree().quit()

func _grab_frame(i: int) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://trans_%03d.png" % i)

func _screenshot_then_quit() -> void:
	# Reset save so layout is deterministic
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute("user://save.json")
	GameState.tutorial_seen = true
	# Filter to a specific scene if `--shoot=name` was passed; else do all.
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shoot="):
			only = a.substr(8)
	var shots := ["village", "settings", "workbench", "workbench_drag", "workbench_hint", "workbench_hint_full", "workbench_recycle", "book", "book_partial", "book_targeted", "tutorial", "glyph_audit", "level_complete", "workshop_complete"]
	if only != "":
		shots = [only]
	for which in shots:
		print("[shot] starting ", which)
		if _current:
			_current.queue_free()
			_current = null
			await get_tree().process_frame
		var scene: Node
		if which == "glyph_audit":
			scene = _build_glyph_audit_scene()
		elif which == "village" or which == "settings" or which.begins_with("book") or which == "tutorial" or which == "workshop_complete":
			scene = VILLAGE.instantiate()
		elif which == "level_complete":
			scene = WORKBENCH.instantiate()
			scene.active_quest_npc = &"baker"
		else:
			scene = WORKBENCH.instantiate()
			scene.active_quest_npc = &"baker"
		# "book_partial" = mid-progress book: pretend ~6 inventions discovered
		# so we can verify the discovered/undiscovered styling side by side.
		if which == "book_partial":
			for id in ["fan", "display_case", "lamp_post", "clock", "winch", "factory"]:
				GameState.discover(StringName(id))
		_current = scene
		add_child(scene)
		for i in 5: await get_tree().process_frame
		# Suppress tutorial overlay so we screenshot the actual screen
		for c in scene.get_children():
			if c.scene_file_path != "" and c.scene_file_path.ends_with("tutorial.tscn"):
				c.queue_free()
		await get_tree().process_frame
		if which == "workbench_drag" and scene.has_method("_debug_force_drag"):
			scene._debug_force_drag(Vector2i(0, 0), Vector2(360, 130))
			await get_tree().process_frame
		# workbench_hint: reproduce the "Oven quest + level-2 board" scenario so
		# the toast renders. Pre-fixes, this said "Missing: Clock". Now it should
		# name the quest (Oven) or fall to a generic wait-for-chute hint.
		if which == "workbench_hint":
			# Reproduce the bug screenshot: Lvl 2, Oven quest, board mid-game
			# with no same+same pairs (player has been merging). The hint must
			# walk back from the missing intermediate, e.g. Gearbox: highlight
			# the Cog precursor, say "wait for another Cog then keep merging".
			GameState.current_level = 1  # Lvl 2: Frame & Motion
			for id in ["workbench_tool", "winch"]:
				GameState.discover(StringName(id))
			for y in GameState.BOARD_H:
				for x in GameState.BOARD_W:
					GameState.set_cell(x, y, &"")
			# Mirror the user's bug screenshot: 1 of each, no same+same pairs.
			GameState.set_cell(0, 0, &"gear")
			GameState.set_cell(2, 0, &"cog")
			GameState.set_cell(3, 0, &"coil")
			GameState.set_cell(0, 1, &"wire")
			GameState.set_cell(1, 1, &"lit_bulb")
			GameState.set_cell(2, 1, &"harness")
			GameState.set_cell(3, 1, &"glass_panel")
			GameState.set_cell(1, 2, &"wire_spool")
			GameState.set_cell(3, 2, &"scrap")
			GameState.set_cell(1, 3, &"plate")
			GameState.set_cell(3, 3, &"frame")
			await get_tree().process_frame
			if scene.has_method("_suggest_next_action"):
				scene._suggest_next_action()
			for i in 3: await get_tree().process_frame
		if which == "workbench_hint_full":
			GameState.current_level = 1
			for id in ["workbench_tool", "winch"]:
				GameState.discover(StringName(id))
			for y in GameState.BOARD_H:
				for x in GameState.BOARD_W:
					GameState.set_cell(x, y, &"")
			# Board full. Frame+Harness cross-combine to the ALREADY-discovered
			# Workbench Tool, so step 3 skips it. One cog (precursor for
			# gearbox→clock chain) but no same+same pairs. Steps 3 & 4
			# fall through → step 4.5 → _hint_for_missing → board-full.
			for id in ["fan", "display_case", "lamp_post"]:
				GameState.discover(StringName(id))
			GameState.set_cell(0, 0, &"gear")
			GameState.set_cell(1, 0, &"cog")
			GameState.set_cell(2, 0, &"coil")
			GameState.set_cell(3, 0, &"frame")
			GameState.set_cell(0, 1, &"lit_bulb")
			GameState.set_cell(1, 1, &"glass_panel")
			GameState.set_cell(2, 1, &"bolt_bundle")
			GameState.set_cell(3, 1, &"harness")
			GameState.set_cell(0, 2, &"wire_spool")
			GameState.set_cell(1, 2, &"scrap")
			GameState.set_cell(2, 2, &"plate")
			GameState.set_cell(3, 2, &"spring")
			GameState.set_cell(0, 3, &"bolt")
			GameState.set_cell(1, 3, &"glass")
			GameState.set_cell(2, 3, &"copper_tube")
			GameState.set_cell(3, 3, &"bulb")
			await get_tree().process_frame
			if scene.has_method("_suggest_next_action"):
				scene._suggest_next_action()
			for i in 3: await get_tree().process_frame
		if which == "workbench_recycle":
			# Board full, NO mergeable pairs → triggers recycle arrow hint.
			# Guard the soft-lock breaker so it doesn't modify the board.
			GameState.current_level = 1
			for id in ["workbench_tool", "winch"]:
				GameState.discover(StringName(id))
			scene._in_break_soft_lock = true
			for y in GameState.BOARD_H:
				for x in GameState.BOARD_W:
					GameState.set_cell(x, y, &"")
			# 10 unique junk + 6 unique components = 16 cells, no merges possible.
			GameState.set_cell(0, 0, &"bolt")
			GameState.set_cell(1, 0, &"spring")
			GameState.set_cell(2, 0, &"wire")
			GameState.set_cell(3, 0, &"cog")
			GameState.set_cell(0, 1, &"glass")
			GameState.set_cell(1, 1, &"pipe")
			GameState.set_cell(2, 1, &"bulb")
			GameState.set_cell(3, 1, &"scrap")
			GameState.set_cell(0, 2, &"oil")
			GameState.set_cell(1, 2, &"lens")
			GameState.set_cell(2, 2, &"bolt_bundle")
			GameState.set_cell(3, 2, &"coil")
			GameState.set_cell(0, 3, &"wire_spool")
			GameState.set_cell(1, 3, &"gear")
			GameState.set_cell(2, 3, &"glass_panel")
			GameState.set_cell(3, 3, &"copper_tube")
			await get_tree().process_frame
			if scene.has_method("_suggest_next_action"):
				scene._suggest_next_action()
			for i in 3: await get_tree().process_frame
			scene._in_break_soft_lock = false
		# Open the Invention Book modal over the village.
		if which.begins_with("book"):
			var book := preload("res://scenes/invention_book.tscn").instantiate()
			if which == "book_targeted":
				book.highlight_id = &"spotlight"
			scene.add_child(book)
			for i in 6: await get_tree().process_frame
		if which == "settings":
			# Open the More/Settings sheet so we can verify the Sound toggle.
			if scene.has_method("_open_more"):
				scene._open_more()
			for i in 4: await get_tree().process_frame
		if which == "tutorial":
			var tut := preload("res://scenes/tutorial.tscn").instantiate()
			scene.add_child(tut)
			for i in 3: await get_tree().process_frame
		if which == "level_complete":
			var lc := preload("res://scenes/level_complete.tscn").instantiate()
			lc.level_idx = 0
			lc.building_label = "Bakery"
			lc.thanks = "Fresh bread for the whole village again — thank you!"
			scene.add_child(lc)
			for i in 5: await get_tree().process_frame
		if which == "workshop_complete":
			var wc := preload("res://scenes/workshop_complete.tscn").instantiate()
			scene.add_child(wc)
			for i in 5: await get_tree().process_frame
		# Force a redraw + wait a couple of frames so Metal commits before capture
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://ui_%s.png" % which)
		print("[shot] %s saved" % which)
		var filled := 0
		for y in GameState.BOARD_H:
			for x in GameState.BOARD_W:
				if GameState.get_cell(x, y) != &"": filled += 1
		print("[shot] %s saved (%dx%d) board_filled=%d" %
			[which, img.get_width(), img.get_height(), filled])
	get_tree().quit(0)

func _build_glyph_audit_scene() -> Control:
	# Dev-only: render every item's glyph + name + Unicode codepoint in a tight
	# grid so we can visually scan for tofu / missing-glyph rendering issues.
	var root := Control.new()
	root.anchor_right = 1.0; root.anchor_bottom = 1.0
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.10, 0.05)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	var tier_names := ["JUNK", "COMP", "PART", "INV", "MSTR"]
	for id in Items.defs:
		var d: Items.ItemDef = Items.defs[id]
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(230, 56)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.16, 0.08)
		sb.border_color = d.color
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 6; sb.content_margin_right = 6
		sb.content_margin_top = 4; sb.content_margin_bottom = 4
		box.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		box.add_child(h)
		var glyph := Label.new()
		glyph.text = d.glyph
		glyph.add_theme_font_size_override("font_size", 28)
		glyph.add_theme_color_override("font_color", Color(1.0, 0.95, 0.70))
		glyph.custom_minimum_size = Vector2(32, 0)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(glyph)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var name_lbl := Label.new()
		name_lbl.text = "%s [%s]" % [d.name, tier_names[d.tier]]
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
		info.add_child(name_lbl)
		var cp := Label.new()
		var codepoint: int = d.glyph.unicode_at(0) if d.glyph.length() > 0 else 0
		cp.text = "U+%04X" % codepoint
		cp.add_theme_font_size_override("font_size", 9)
		cp.add_theme_color_override("font_color", Color(0.70, 0.60, 0.40))
		info.add_child(cp)
		grid.add_child(box)
	return root

func show_village() -> void:
	_swap(VILLAGE.instantiate())

func show_workbench(active_quest_npc: StringName = &"") -> void:
	var wb := WORKBENCH.instantiate()
	wb.active_quest_npc = active_quest_npc
	_swap(wb)

func _swap(scene: Node) -> void:
	# Crossfade through the game's dark bg color so village<->workbench (and the
	# level-complete return) feels deliberate instead of a hard cut. Input is
	# blocked by the cover while the transition runs (~0.32s total).
	var fade := ColorRect.new()
	fade.color = Color(0.18, 0.13, 0.09, 0.0)  # = project bg; start transparent
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fade)
	if _current:
		var tw := create_tween()
		tw.tween_property(fade, "color:a", 1.0, 0.16)
		await tw.finished
		_current.queue_free()
	else:
		fade.color.a = 1.0  # first load: start from solid, only fade in
	_current = scene
	add_child(scene)
	move_child(fade, get_child_count() - 1)  # keep the cover above the new scene
	if scene.has_signal("go_village"):
		scene.go_village.connect(show_village)
	if scene.has_signal("go_workbench"):
		scene.go_workbench.connect(show_workbench)
	await get_tree().process_frame  # let the new scene lay out before revealing
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.16)
	await tw2.finished
	fade.queue_free()

# -------------------------------------------------------------------------
# Dev test: `godot -- --test-hints`
# Exercises the hint/chute logic across all 5 levels with various board states.
# -------------------------------------------------------------------------
var _test_pass: int = 0
var _test_fail: int = 0

func _tok(cond: bool, msg: String) -> void:
	if cond:
		_test_pass += 1
	else:
		_test_fail += 1
		printerr("FAIL: ", msg)

func _test_hints_then_quit() -> void:
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute("user://save.json")
	GameState.tutorial_seen = true
	# Instantiate a workbench so we can call its logic methods.
	var wb := WORKBENCH.instantiate()
	wb.active_quest_npc = &"baker"
	add_child(wb)
	await get_tree().process_frame
	await get_tree().process_frame

	print("[test-hints] starting...")
	_th_recycle_never_junk(wb)
	_th_recycle_prefers_duplicates(wb)
	_th_closest_undiscovered_per_level(wb)
	_th_both_missing_diversity(wb)
	_th_chute_diversity(wb)
	_th_chute_only_junk(wb)
	_th_walkback_seeds_in_pool(wb)
	_th_board_full_recycle_reward(wb)
	_th_quest_merge_hint(wb)
	_th_step3_quest_target_not_skipped(wb)
	_th_chute_no_flood_when_assemblable(wb)
	_th_softlock_strategy_c_picks_missing(wb)
	_th_quest_switching(wb)
	_th_analytics_payload()

	print("\n=== HINT TESTS: %d passed, %d failed ===" % [_test_pass, _test_fail])
	wb.queue_free()
	get_tree().quit(0 if _test_fail == 0 else 1)

func _th_analytics_payload() -> void:
	# Analytics is disabled off-device (the native Firebase bridge only exists in
	# the iOS app), but build_record() is pure and must produce the JSONL record
	# shape the Swift file-watcher (AnalyticsBridge.swift) expects regardless.
	Analytics._user_id = "testuid12345678"
	Analytics._session_id = "999"
	var rec := Analytics.build_record("invention_discovered", {"invention_id": "fan", "total_discovered": 3})
	_tok(rec.get("name", "") == "invention_discovered", "analytics: event name")
	_tok(rec.has("params"), "analytics: params present")
	var p: Dictionary = rec.get("params", {})
	_tok(p.get("invention_id", "") == "fan", "analytics: custom param kept")
	_tok(p.get("user_id", "") == "testuid12345678", "analytics: user_id injected")
	_tok(p.get("session_id", "") == "999", "analytics: session_id injected")
	_tok(p.has("t"), "analytics: timestamp injected")
	# Must serialize to one valid JSON line (the bridge parses line-by-line).
	var s := JSON.stringify(rec)
	_tok(s.length() > 0 and not s.contains("\n") and JSON.parse_string(s) != null, "analytics: JSON line round-trips")
	# Signal-driven handler must produce a building_complete record carrying the
	# NPC's building label + 1-based level.
	var qrec := Analytics.build_record("building_complete", {"npc_id": "lux", "building": "Street Lamps", "level": 1})
	_tok(qrec["params"].get("building", "") == "Street Lamps", "analytics: building param")

func _clear_test_board() -> void:
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			GameState.set_cell(x, y, &"")
	GameState.discovered.clear()

# 1. Recycle never targets junk (reward=0)
func _th_recycle_never_junk(wb) -> void:
	for li in Items.LEVELS.size():
		GameState.current_level = li
		_clear_test_board()
		var junks: Array = Items.junks_for_level(li)
		var idx := 0
		for j in junks:
			if idx >= 16: break
			GameState.set_cell(idx % 4, idx / 4, j)
			idx += 1
			var comp: StringName = Items.upgrade.get(j, &"")
			if comp != &"" and idx < 16:
				GameState.set_cell(idx % 4, idx / 4, comp)
				idx += 1
		while idx < 16:
			GameState.set_cell(idx % 4, idx / 4, junks[0])
			idx += 1
		var cell: Vector2i = wb._find_best_recycle_cell()
		if cell.x >= 0:
			var cid := GameState.get_cell(cell.x, cell.y)
			var d: Items.ItemDef = Items.get_def(cid)
			_tok(d != null and d.tier > 0,
				"L%d recycle never junk: got %s tier=%d" % [li + 1, cid, d.tier if d else -1])

# 2. Recycle prefers most-duplicated item
func _th_recycle_prefers_duplicates(wb) -> void:
	GameState.current_level = 0
	_clear_test_board()
	for i in 12:
		GameState.set_cell(i % 4, i / 4, &"fan")
	GameState.set_cell(0, 3, &"gear")
	GameState.set_cell(1, 3, &"gear")
	GameState.set_cell(2, 3, &"bolt")
	GameState.set_cell(3, 3, &"bolt")
	var cell: Vector2i = wb._find_best_recycle_cell()
	var cid := GameState.get_cell(cell.x, cell.y)
	_tok(cid == &"fan", "recycle prefers duplicates: got %s (want fan)" % cid)

# 3. _closest_undiscovered returns valid targets per level
func _th_closest_undiscovered_per_level(wb) -> void:
	for li in Items.LEVELS.size():
		GameState.current_level = li
		_clear_test_board()
		GameState.discovered.clear()
		var targets: Array = Items.LEVELS[li].targets
		var nudge: Array = wb._closest_undiscovered()
		if targets.size() > 0:
			_tok(nudge.size() == 2,
				"L%d undiscovered returns pair" % [li + 1])
			if nudge.size() == 2:
				_tok(targets.has(nudge[0]),
					"L%d target %s in level list" % [li + 1, nudge[0]])
		for t in targets:
			GameState.discovered[t] = true
		nudge = wb._closest_undiscovered()
		_tok(nudge.size() == 0, "L%d all discovered -> empty" % [li + 1])

# 4. When both ingredients missing, chute seeds BOTH over time
func _th_both_missing_diversity(wb) -> void:
	GameState.current_level = 3  # Heat & Power
	_clear_test_board()
	GameState.discovered.clear()
	for t in Items.LEVELS[3].targets:
		if t != &"oven":
			GameState.discovered[t] = true
	var saw := {}
	for _i in 40:
		var nudge: Array = wb._closest_undiscovered()
		if nudge.size() == 2:
			saw[nudge[1]] = saw.get(nudge[1], 0) + 1
	_tok(saw.size() >= 2,
		"both-missing diversity: %d distinct (%s)" % [saw.size(), str(saw.keys())])
	for k in saw:
		var pct: float = float(saw[k]) / 40.0
		_tok(pct < 0.90, "ingredient %s not >90%%: %.0f%%" % [k, pct * 100])

# 5. Chute drops diverse junk (no single item >80%)
func _th_chute_diversity(wb) -> void:
	for li in Items.LEVELS.size():
		GameState.current_level = li
		_clear_test_board()
		GameState.discovered.clear()
		wb._recent_recycles.clear()
		var counts := {}
		for _i in 30:
			var id: StringName = wb._pick_helpful_junk()
			counts[id] = counts.get(id, 0) + 1
		var max_pct := 0.0
		var max_id := &""
		for id in counts:
			var pct: float = float(counts[id]) / 30.0
			if pct > max_pct:
				max_pct = pct
				max_id = id
		_tok(max_pct <= 0.80,
			"L%d chute diversity: %s at %.0f%% (want <=80%%)" % [li + 1, max_id, max_pct * 100])

# 6. Chute always returns tier-0 junk
func _th_chute_only_junk(wb) -> void:
	for li in Items.LEVELS.size():
		GameState.current_level = li
		_clear_test_board()
		GameState.discovered.clear()
		wb._recent_recycles.clear()
		for _i in 20:
			var id: StringName = wb._pick_helpful_junk()
			var d: Items.ItemDef = Items.get_def(id)
			_tok(d != null and d.tier == Items.Tier.JUNK,
				"L%d chute junk: %s tier=%d" % [li + 1, id, d.tier if d else -1])

# 7. Walk-back: every target's seeds are in the level's junk pool
func _th_walkback_seeds_in_pool(wb) -> void:
	for li in Items.LEVELS.size():
		GameState.current_level = li
		var pool: Array = Items.LEVELS[li].junks
		for target in Items.LEVELS[li].targets:
			var seeds: Array = wb._junk_seeds_for(target)
			_tok(seeds.size() > 0, "L%d %s has seeds" % [li + 1, target])
			for s in seeds:
				_tok(pool.has(s), "L%d %s seed %s in pool" % [li + 1, target, s])

# 8. Board full -> best recycle cell is never junk
func _th_board_full_recycle_reward(wb) -> void:
	for li in Items.LEVELS.size():
		GameState.current_level = li
		_clear_test_board()
		GameState.discovered.clear()
		var junks: Array = Items.junks_for_level(li)
		var fill: Array = []
		for j in junks:
			fill.append(j)
			var comp: StringName = Items.upgrade.get(j, &"")
			if comp != &"": fill.append(comp)
		var unique: Array = []
		for f in fill:
			if not unique.has(f): unique.append(f)
		var idx := 0
		for y in GameState.BOARD_H:
			for x in GameState.BOARD_W:
				GameState.set_cell(x, y, unique[idx % unique.size()])
				idx += 1
		var cell: Vector2i = wb._find_best_recycle_cell()
		if cell.x >= 0:
			var cid := GameState.get_cell(cell.x, cell.y)
			var d: Items.ItemDef = Items.get_def(cid)
			_tok(d != null and d.tier > Items.Tier.JUNK,
				"L%d full-board recycle never junk: %s tier=%d" % [li + 1, cid, d.tier if d else -1])

# 9. Cross-combine merge hint: when both parents of an undiscovered invention
# are on the board, hint should suggest merging them (step 1 cross-combine).
func _th_quest_merge_hint(wb) -> void:
	_clear_test_board()
	GameState.current_level = 3  # Level 4 (Heat & Power) has oven
	wb.active_quest_npc = &"baker"  # baker = level 3 NPC
	# Place boiler and fuel_tank (both parents of oven) on the board
	# Oven is NOT discovered → step 1 should find the cross-combine
	GameState.set_cell(0, 0, &"boiler")
	GameState.set_cell(1, 0, &"fuel_tank")
	# Fill a few more cells to simulate a busy board
	GameState.set_cell(2, 0, &"boiler")
	GameState.set_cell(3, 0, &"fuel_tank")
	wb._suggest_next_action()
	# The hint should highlight a boiler + fuel_tank pair, not suggest recycling
	_tok(wb._suggest_cells.size() == 2,
		"cross-combine hint: _suggest_cells has 2 cells (got %d)" % wb._suggest_cells.size())
	_tok(not wb._suggest_recycle,
		"cross-combine hint: does NOT suggest recycle")
	# Verify the highlighted cells contain boiler and fuel_tank
	if wb._suggest_cells.size() == 2:
		var id_a := GameState.get_cell(wb._suggest_cells[0].x, wb._suggest_cells[0].y)
		var id_b := GameState.get_cell(wb._suggest_cells[1].x, wb._suggest_cells[1].y)
		var ids := [id_a, id_b]
		ids.sort()
		_tok(ids.has(&"boiler") and ids.has(&"fuel_tank"),
			"cross-combine hint: cells are boiler+fuel_tank (got %s+%s)" % [id_a, id_b])

# 10. Discovered inventions are skipped: if boiler+fuel_tank are on board but
# oven is already discovered, step 1 should NOT suggest re-making it.
# Instead the hint should fall through to other undiscovered targets.
func _th_step3_quest_target_not_skipped(wb) -> void:
	_clear_test_board()
	GameState.current_level = 3
	# Discover oven so step 1 skips the boiler+fuel_tank cross-combine
	GameState.discovered[&"oven"] = true
	wb.active_quest_npc = &"baker"
	GameState.set_cell(0, 0, &"boiler")
	GameState.set_cell(1, 0, &"fuel_tank")
	wb._suggest_next_action()
	# Should NOT highlight boiler+fuel_tank (oven is already discovered)
	# Instead should guide toward another undiscovered target in level 3
	_tok(not wb._suggest_recycle,
		"discovered skip: no recycle suggestion")

# 11. Chute doesn't flood when missing ingredient is assemblable from board parts
func _th_chute_no_flood_when_assemblable(wb) -> void:
	_clear_test_board()
	GameState.current_level = 4  # Level 5 (Masterworks) has factory = generator + oven
	GameState.discovered.clear()
	# Discover everything except factory (so factory is the undiscovered target)
	for li in Items.LEVELS.size():
		for t in Items.LEVELS[li].targets:
			if t != &"factory":
				GameState.discovered[t] = true
	# Place boiler + fuel_tank on board (parts of oven, which is a factory ingredient)
	GameState.set_cell(0, 0, &"boiler")
	GameState.set_cell(1, 0, &"fuel_tank")
	# Also place a generator (the other factory ingredient)
	GameState.set_cell(2, 0, &"generator")
	# The chute should NOT keep dropping pipe/oil (seeds for oven) because
	# oven can be assembled from boiler + fuel_tank already on board.
	var pipe_oil_count := 0
	for _i in 30:
		var junk = wb._pick_helpful_junk()
		if junk == &"pipe" or junk == &"oil":
			pipe_oil_count += 1
	_tok(pipe_oil_count < 15,
		"chute no flood: pipe/oil < 50%% of 30 drops (got %d)" % pipe_oil_count)

# 12. Soft-lock breaker Strategy C picks the MISSING masterwork ingredient,
# not one already on the board. Old bug: always picked ps[0] (Camera for
# Photo Studio), causing endless Camera injection when Camera was already present.
func _th_softlock_strategy_c_picks_missing(wb) -> void:
	_clear_test_board()
	GameState.current_level = 4  # Level 5 (Masterworks)
	GameState.discovered.clear()
	# Discover all 20 inventions + 3 masterworks — leave Photo Studio + Observatory
	for li in Items.LEVELS.size():
		for t in Items.LEVELS[li].targets:
			if t != &"photo_studio" and t != &"observatory":
				GameState.discovered[t] = true
	wb.active_quest_npc = &""
	# Fill board with Camera×3, Lamp Post×3, Fan×3, Frame×3, Boiler×2, + 2 junk
	GameState.set_cell(0, 0, &"camera")
	GameState.set_cell(1, 0, &"camera")
	GameState.set_cell(2, 0, &"camera")
	GameState.set_cell(3, 0, &"lamp_post")
	GameState.set_cell(0, 1, &"lamp_post")
	GameState.set_cell(1, 1, &"lamp_post")
	GameState.set_cell(2, 1, &"fan")
	GameState.set_cell(3, 1, &"fan")
	GameState.set_cell(0, 2, &"fan")
	GameState.set_cell(1, 2, &"frame")
	GameState.set_cell(2, 2, &"frame")
	GameState.set_cell(3, 2, &"frame")
	GameState.set_cell(0, 3, &"boiler")
	GameState.set_cell(1, 3, &"boiler")
	# Two junk items so scrap_candidates isn't empty (standard path)
	GameState.set_cell(2, 3, &"bolt")
	GameState.set_cell(3, 3, &"spring")
	# Force the soft-lock breaker to fire
	wb._break_soft_lock_if_needed()
	# The injected items should NOT be frame+scope (→ Camera, already on board).
	# They should be for Spotlight (Lantern + Motor) since Camera is already present.
	var found_scope := false
	var found_lantern := false
	var found_motor := false
	for y in GameState.BOARD_H:
		for x in GameState.BOARD_W:
			var id := GameState.get_cell(x, y)
			if id == &"scope": found_scope = true
			if id == &"lantern": found_lantern = true
			if id == &"motor": found_motor = true
	_tok(not found_scope,
		"strategy C: no Scope injected (Camera already on board)")
	_tok(found_lantern or found_motor,
		"strategy C: injected Lantern and/or Motor for Spotlight")

# 13. NPC switching: changing active_quest_npc updates UI correctly.
# In the NPC=level model, each NPC owns a themed level. Switching NPCs
# changes the goal bar color/label and hints target that level's items.
func _th_quest_switching(wb) -> void:
	_clear_test_board()
	GameState.current_level = 3  # Level 4 (Heat & Power)
	# Discover many items but leave level 3 targets undiscovered
	for id in [&"fan", &"display_case", &"lamp_post", &"clock", &"winch",
			   &"workbench_tool", &"camera", &"projector", &"signal_lamp",
			   &"telescope", &"mail_box", &"spotlight", &"cart", &"carriage",
			   &"lantern_window"]:
		GameState.discovered[id] = true
	# Place Boiler + Fuel Tank on board (Oven ingredients — undiscovered L3 target)
	GameState.set_cell(0, 0, &"boiler")
	GameState.set_cell(1, 0, &"fuel_tank")

	# Test A: Baker quest (level 3) → UI correct, hints find cross-combine
	wb.active_quest_npc = &"baker"
	wb._refresh_quest_ui()
	_tok(not wb._quest_label.visible,
		"npc switch: baker → quest label hidden")
	_tok(wb._goal_banner.visible,
		"npc switch: baker → goal banner visible")
	wb._suggest_next_action()
	# boiler+fuel_tank → oven (undiscovered) should be highlighted
	_tok(wb._suggest_cells.size() == 2,
		"npc switch: baker hints highlight 2 cells (got %d)" % wb._suggest_cells.size())

	# Test B: No quest → same UI state (label hidden, goal banner visible)
	wb.active_quest_npc = &""
	wb._refresh_quest_ui()
	_tok(not wb._quest_label.visible,
		"npc switch: no quest → label hidden")
	_tok(wb._goal_banner.visible,
		"npc switch: no quest → goal banner visible")
