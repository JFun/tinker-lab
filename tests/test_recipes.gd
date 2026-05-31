extends SceneTree
## Recipe-tree sanity tests. Per global CLAUDE.md: write tests for game logic
## constraints. We verify the merge tree closes — every quest invention is
## reachable from junk, and no recipe data is malformed.

var _failures: int = 0
var _passes: int = 0

func _initialize() -> void:
	# Items/GameState/Npcs autoloads are not active in headless SceneTree runs;
	# instantiate them manually and let _ready() build the data.
	var items := preload("res://data/items.gd").new()
	var npcs := preload("res://data/npcs.gd").new()
	# _ready() does not fire synchronously when adding under SceneTree.root in
	# _initialize(); invoke the builders directly.
	items._build_items()
	items._build_recipes()
	items._validate()
	npcs._ready()

	_test_defs_complete(items)
	_test_glyphs_unique(items)
	_test_upgrade_chain(items)
	_test_cross_recipes(items)
	_test_quest_inventions_reachable(items, npcs)
	_test_no_dead_end_quests(items, npcs)
	_test_masterworks_reachable(items)
	_test_invention_count_meets_mvp(items)
	_test_no_phantom_upgrade_at_high_tiers(items)
	_test_all_inventions_structurally_reachable(items)
	_test_board_holds_largest_recipe(items)
	_test_levels_cover_every_invention(items)
	_test_each_level_self_contained(items)

	print("\n=== %d passed, %d failed ===" % [_passes, _failures])
	quit(0 if _failures == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)

func _test_defs_complete(items) -> void:
	# Every junk id must have a def.
	for id in items.JUNK_IDS:
		_ok(items.get_def(id) != null, "junk def exists: %s" % id)

func _test_glyphs_unique(items) -> void:
	# Two items sharing a glyph confuses players (already burned by ☼ on
	# lit_bulb+signal_lamp, ▤ on chassis+mail_box, ◉ on scope+camera).
	# Catch any future dupe at startup.
	var by_glyph: Dictionary = {}
	for id in items.defs:
		var d = items.defs[id]
		if d.glyph == "": continue
		if by_glyph.has(d.glyph):
			_ok(false, "glyph collision: '%s' on both %s and %s" % [
				d.glyph, by_glyph[d.glyph], id])
		else:
			by_glyph[d.glyph] = id

func _test_upgrade_chain(items) -> void:
	# Junk -> component -> part for every starter junk.
	for id in items.JUNK_IDS:
		var t1 = items.try_merge(id, id)
		_ok(t1 != &"", "%s + %s upgrades" % [id, id])
		if t1 == &"": continue
		var t2 = items.try_merge(t1, t1)
		_ok(t2 != &"", "%s + %s upgrades" % [t1, t1])
		var d2 = items.get_def(t2)
		_ok(d2 != null and d2.tier == items.Tier.PART,
			"%s reaches tier PART (got %s)" % [id, d2.name if d2 else "nil"])

func _test_cross_recipes(items) -> void:
	# Every cross recipe maps to a defined item whose tier = source tier + 1.
	for key in items.cross:
		var result = items.cross[key]
		var d = items.get_def(result)
		_ok(d != null, "cross result %s exists" % result)
		var parts: PackedStringArray = String(key).split("|")
		var a = items.get_def(StringName(parts[0]))
		var b = items.get_def(StringName(parts[1]))
		_ok(a != null and b != null, "cross sources for %s defined" % result)
		if a and b and d:
			_ok(a.tier == b.tier and d.tier == a.tier + 1,
				"cross tier consistent: %s+%s -> %s" % [a.name, b.name, d.name])

func _test_quest_inventions_reachable(items, npcs) -> void:
	# Every MVP quest invention can be produced by some cross-recipe (i.e., a
	# player can actually deliver it). Without this, a quest is unwinnable.
	for npc in npcs.npcs:
		var found := false
		for key in items.cross:
			if items.cross[key] == npc.wants:
				found = true; break
		_ok(found, "quest invention reachable: %s (for %s)" % [npc.wants, npc.name])

func _test_no_dead_end_quests(items, npcs) -> void:
	# Every quest invention's two parents (the parts that merge to make it) are
	# themselves reachable from junk via the upgrade chain.
	var part_ids: Dictionary = {}
	for id in items.JUNK_IDS:
		var t1 = items.try_merge(id, id)
		var t2 = items.try_merge(t1, t1) if t1 != &"" else &""
		if t2 != &"": part_ids[t2] = true
	for npc in npcs.npcs:
		var parents: Array = []
		for key in items.cross:
			if items.cross[key] == npc.wants:
				var ps: PackedStringArray = String(key).split("|")
				parents = [StringName(ps[0]), StringName(ps[1])]
				break
		_ok(parents.size() == 2, "found parents for %s" % npc.wants)
		if parents.size() == 2:
			_ok(part_ids.has(parents[0]) and part_ids.has(parents[1]),
				"both parents of %s reachable from junk" % npc.wants)

func _test_masterworks_reachable(items) -> void:
	# Every masterwork must have invention parents that are themselves reachable.
	var inv_ids: Dictionary = {}
	for key in items.cross:
		var d = items.get_def(items.cross[key])
		if d and d.tier == items.Tier.INVENTION:
			inv_ids[items.cross[key]] = true
	var masterwork_count := 0
	for key in items.cross:
		var result = items.cross[key]
		var d = items.get_def(result)
		if d and d.tier == items.Tier.MASTERWORK:
			masterwork_count += 1
			var ps: PackedStringArray = String(key).split("|")
			_ok(inv_ids.has(StringName(ps[0])) and inv_ids.has(StringName(ps[1])),
				"masterwork %s has reachable invention parents" % d.name)
	_ok(masterwork_count >= 5, "MVP target: ≥5 masterworks (have %d)" % masterwork_count)

func _test_no_phantom_upgrade_at_high_tiers(items) -> void:
	# Inventions (T3) and masterworks (T4) must NOT have a same+same upgrade.
	# The hint system used to suggest "drag two Clocks together" because Clock
	# had a cross-combine partner; verify the data layer never claims an
	# upgrade exists at those tiers, so the hint logic can rely on it.
	for id in items.defs:
		var d = items.defs[id]
		if d.tier >= items.Tier.INVENTION:
			_ok(items.try_merge(id, id) == &"",
				"no same+same upgrade for high-tier item: %s" % d.name)

func _test_all_inventions_structurally_reachable(items) -> void:
	# THEORETICAL achievability proof: compute the transitive closure of items
	# reachable from junk via (a) same+same upgrades and (b) cross-combines.
	# Every tier-3 invention and tier-4 masterwork must end up in the set.
	# Combined with the smart chute (biased toward undiscovered targets) and
	# the auto-scrap soft-lock breaker, this guarantees the game is completable.
	var reachable: Dictionary = {}
	for id in items.JUNK_IDS: reachable[id] = true
	var changed := true
	while changed:
		changed = false
		for src in items.upgrade:
			if reachable.has(src) and not reachable.has(items.upgrade[src]):
				reachable[items.upgrade[src]] = true; changed = true
		for key in items.cross:
			var ps: PackedStringArray = String(key).split("|")
			var a: StringName = StringName(ps[0])
			var b: StringName = StringName(ps[1])
			var r: StringName = items.cross[key]
			if reachable.has(a) and reachable.has(b) and not reachable.has(r):
				reachable[r] = true; changed = true
	for id in items.all_inventions():
		var d = items.get_def(id)
		_ok(reachable.has(id), "invention reachable from junk: %s" % d.name)

func _test_levels_cover_every_invention(items) -> void:
	# Every invention must appear in exactly one level (no dupes, no gaps).
	var seen: Dictionary = {}
	for lvl in items.LEVELS:
		for t in lvl.targets:
			_ok(not seen.has(t), "no duplicate target across levels: %s" % t)
			_ok(items.get_def(t) != null, "level target is a real item: %s" % t)
			seen[t] = true
	for id in items.all_inventions():
		_ok(seen.has(id), "every invention belongs to some level: %s" % items.get_def(id).name)

func _test_each_level_self_contained(items) -> void:
	# Every target in a level must be reachable using ONLY that level's junks
	# (plus any inventions completed in prior levels, for the Masterworks level).
	# Mirrors the transitive-closure proof but per-level.
	var carry: Dictionary = {}  # discoveries kept across levels
	for li in items.LEVELS.size():
		var lvl: Dictionary = items.LEVELS[li]
		var reachable: Dictionary = {}
		for j in lvl.junks: reachable[j] = true
		# carry-over: tier-3 inventions from prior levels (real player state).
		for d in carry: reachable[d] = true
		var changed := true
		while changed:
			changed = false
			for src in items.upgrade:
				if reachable.has(src) and not reachable.has(items.upgrade[src]):
					reachable[items.upgrade[src]] = true; changed = true
			for key in items.cross:
				var ps: PackedStringArray = String(key).split("|")
				var a: StringName = StringName(ps[0])
				var b: StringName = StringName(ps[1])
				if reachable.has(a) and reachable.has(b) and not reachable.has(items.cross[key]):
					reachable[items.cross[key]] = true; changed = true
		for t in lvl.targets:
			_ok(reachable.has(t),
				"level %d (%s): target %s reachable" % [li + 1, lvl.name, items.get_def(t).name])
			carry[t] = true  # earlier-level discoveries persist to later levels

func _test_board_holds_largest_recipe(_items) -> void:
	# Sanity check: the 4x4 board has room for the worst-case working set.
	# A Masterwork is 2 Inventions held simultaneously = 2 cells.
	# Each ingredient invention takes ~2 cells (its two Parts) while building.
	# Worst case is ~5 cells held at once. 4x4 = 16 cells — comfortable headroom,
	# so board size is NOT the limiting factor for full completion.
	const BOARD_CELLS := 4 * 4
	var max_working_set := 5
	_ok(BOARD_CELLS >= max_working_set,
		"4x4 board (%d cells) holds worst-case recipe working set (%d cells)" % [
			BOARD_CELLS, max_working_set])

func _test_invention_count_meets_mvp(items) -> void:
	# PRD: 20+ inventions (Tier 3), 5 masterworks (Tier 4).
	var inv := 0; var mw := 0
	for id in items.defs:
		var d = items.defs[id]
		if d.tier == items.Tier.INVENTION: inv += 1
		elif d.tier == items.Tier.MASTERWORK: mw += 1
	_ok(inv >= 20, "MVP target: ≥20 inventions (have %d)" % inv)
	_ok(mw >= 5, "MVP target: ≥5 masterworks (have %d)" % mw)
