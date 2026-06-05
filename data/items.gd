extends Node
## Item & recipe database. Autoload singleton.
##
## Tier 0 junk → Tier 1 components → Tier 2 parts (same-item upgrade chain).
## Tier 2 + Tier 2 (different) → Tier 3 inventions (cross-combine, branching).
## Tier 3 + Tier 3 (different) → Tier 4 masterworks.

enum Tier { JUNK = 0, COMPONENT = 1, PART = 2, INVENTION = 3, MASTERWORK = 4 }

class ItemDef:
	var id: StringName
	var name: String
	var tier: int
	var color: Color
	var glyph: String  # single-char visual placeholder until real art lands
	func _init(p_id: StringName, p_name: String, p_tier: int, p_color: Color, p_glyph: String) -> void:
		id = p_id; name = p_name; tier = p_tier; color = p_color; glyph = p_glyph

var defs: Dictionary = {}  # StringName -> ItemDef
var upgrade: Dictionary = {}  # StringName -> StringName (same+same)
var cross: Dictionary = {}  # frozenset-like key "a|b" (sorted) -> StringName

# Invention stories: one-line "how" description shown on the discovery card.
# Each entry maps invention_id -> [role_a, role_b, story_sentence].
# role_a/b match the cross-combine order (alphabetical by id).
var stories: Dictionary = {}

# --- Tier 0 junk (10) ---
const JUNK_IDS: Array[StringName] = [
	&"bolt", &"spring", &"wire", &"cog", &"glass",
	&"pipe", &"bulb", &"scrap", &"oil", &"lens",
]

# --- LEVELS: 25 inventions split into 5 stages of increasing complexity. ---
# Each level is 5 targets. Player completes one level before the game shifts
# focus to the next (chute bias + goal display). Locking is NOT enforced;
# discoveries from "later" levels still count if the player stumbles onto them.
# Level 5 masterworks require inventions from earlier levels, so completing
# the campaign in order makes the dependency natural.
const LEVELS: Array = [
	{"name": "Light & Glass",
	 "junks": [&"bolt", &"spring", &"bulb", &"glass"],
	 "targets": [&"fan", &"display_case", &"lamp_post", &"spotlight", &"lantern_window"]},
	{"name": "Frame & Motion",
	 "junks": [&"bolt", &"spring", &"bulb", &"glass", &"wire", &"cog", &"scrap"],
	 "targets": [&"workbench_tool", &"clock", &"winch", &"cart", &"carriage"]},
	{"name": "Optics",
	 "junks": [&"bolt", &"spring", &"bulb", &"glass", &"wire", &"cog", &"scrap", &"lens"],
	 "targets": [&"camera", &"projector", &"signal_lamp", &"telescope", &"mail_box"]},
	{"name": "Heat & Power",
	 "junks": [&"bolt", &"spring", &"bulb", &"glass", &"wire", &"cog", &"scrap", &"lens", &"pipe", &"oil"],
	 "targets": [&"steam_engine", &"generator", &"oven", &"mail_sorter", &"steam_scope"]},
	{"name": "Masterworks",
	 "junks": [&"bolt", &"spring", &"bulb", &"glass", &"wire", &"cog", &"scrap", &"lens", &"pipe", &"oil"],
	 "targets": [&"cinema_machine", &"clock_tower", &"factory", &"photo_studio", &"observatory"]},
]

func junks_for_level(idx: int) -> Array:
	if idx < 0 or idx >= LEVELS.size(): return JUNK_IDS
	return LEVELS[idx].junks

func random_junk_for_level(idx: int) -> StringName:
	var pool: Array = junks_for_level(idx)
	return pool[randi() % pool.size()]

## Daily-delivery helper: a ready-made item of `target_tier` (COMPONENT or PART)
## drawn from level `idx`'s junk pool, by walking the same+same upgrade chain.
## Returns &"" if no junk in the pool reaches that tier (shouldn't happen — every
## junk has a full junk→component→part chain).
func delivery_item_for_level(idx: int, target_tier: int) -> StringName:
	var pool: Array = junks_for_level(idx).duplicate()
	pool.shuffle()
	for junk in pool:
		var cur: StringName = junk
		var d: ItemDef = get_def(cur)
		while d != null and d.tier < target_tier:
			var nxt: StringName = upgrade.get(cur, &"")
			if nxt == &"": break
			cur = nxt
			d = get_def(cur)
		if d != null and d.tier == target_tier:
			return cur
	return &""

func level_of(invention_id: StringName) -> int:
	for i in LEVELS.size():
		var lvl: Dictionary = LEVELS[i]
		if (lvl.targets as Array).has(invention_id):
			return i
	return -1

func current_level_index(discovered: Dictionary) -> int:
	# Smallest level index that still has an undiscovered target.
	for i in LEVELS.size():
		var lvl: Dictionary = LEVELS[i]
		for t in lvl.targets:
			if not discovered.has(t):
				return i
	return LEVELS.size()  # all done

func _ready() -> void:
	_build_items()
	_build_recipes()
	_build_stories()
	_validate()

func _build_items() -> void:
	# Junk — each gets a distinct symbol. Picked from common Unicode blocks
	# (geometric shapes, math operators) that render in Noto fallback.
	# COLOR SYSTEM: 10 distinct hue families, each carried through junk→comp→part.
	# Junk = muted, Component = brighter, Part = vivid. Inventions get unique
	# vibrant colors. This makes the board colorful at a glance (Royal Match style).
	_add(&"bolt",   "Bolt",         Tier.JUNK, Color(0.62, 0.40, 0.22), "●")     # brown/sienna
	_add(&"spring", "Spring",       Tier.JUNK, Color(0.25, 0.58, 0.55), "∿")     # teal
	_add(&"wire",   "Wire",         Tier.JUNK, Color(0.82, 0.48, 0.18), "∽")     # orange
	_add(&"cog",    "Cog",          Tier.JUNK, Color(0.35, 0.50, 0.70), "✱")     # steel blue
	_add(&"glass",  "Glass Shard",  Tier.JUNK, Color(0.42, 0.70, 0.85), "◆")     # sky blue
	_add(&"pipe",   "Copper Pipe",  Tier.JUNK, Color(0.75, 0.35, 0.30), "▮")     # crimson
	_add(&"bulb",   "Old Bulb",     Tier.JUNK, Color(0.82, 0.72, 0.25), "○")     # gold
	_add(&"scrap",  "Metal Scrap",  Tier.JUNK, Color(0.48, 0.48, 0.52), "◢")     # gray
	_add(&"oil",    "Oil Flask",    Tier.JUNK, Color(0.25, 0.52, 0.30), "▼")     # forest green
	_add(&"lens",   "Lens",         Tier.JUNK, Color(0.58, 0.38, 0.72), "⊚")     # purple

	# Tier 1 components — same hue families, slightly brighter
	_add(&"bolt_bundle",  "Bolt Bundle",   Tier.COMPONENT, Color(0.68, 0.45, 0.25), "⁂")   # brown
	_add(&"coil",         "Coil",          Tier.COMPONENT, Color(0.28, 0.65, 0.62), "◎")   # teal
	_add(&"wire_spool",   "Wire Spool",    Tier.COMPONENT, Color(0.88, 0.52, 0.20), "⊙")   # orange
	_add(&"gear",         "Gear",          Tier.COMPONENT, Color(0.40, 0.56, 0.76), "✶")   # steel blue
	_add(&"glass_panel",  "Glass Panel",   Tier.COMPONENT, Color(0.48, 0.76, 0.88), "◇")   # sky blue
	_add(&"copper_tube",  "Copper Tube",   Tier.COMPONENT, Color(0.82, 0.40, 0.34), "‖")   # crimson
	_add(&"lit_bulb",     "Lit Bulb",      Tier.COMPONENT, Color(0.88, 0.78, 0.28), "☼")   # gold
	_add(&"plate",        "Iron Plate",    Tier.COMPONENT, Color(0.55, 0.55, 0.58), "▣")   # gray
	_add(&"oil_canister", "Oil Canister",  Tier.COMPONENT, Color(0.28, 0.58, 0.34), "⊓")   # forest green
	_add(&"magnifier",    "Magnifier",     Tier.COMPONENT, Color(0.64, 0.44, 0.78), "⊖")   # purple

	# Tier 2 parts — vivid, saturated
	_add(&"frame",       "Frame",          Tier.PART, Color(0.75, 0.50, 0.28), "▦")     # sienna
	_add(&"motor",       "Motor",          Tier.PART, Color(0.32, 0.72, 0.68), "⊛")     # teal
	_add(&"harness",     "Wire Harness",   Tier.PART, Color(0.92, 0.58, 0.22), "≋")     # orange
	_add(&"gearbox",     "Gearbox",        Tier.PART, Color(0.45, 0.62, 0.82), "⊝")     # steel blue
	_add(&"window",      "Window",         Tier.PART, Color(0.52, 0.82, 0.92), "⊞")     # sky blue
	_add(&"boiler",      "Boiler",         Tier.PART, Color(0.88, 0.45, 0.38), "⊕")     # crimson
	_add(&"lantern",     "Lantern",        Tier.PART, Color(0.92, 0.82, 0.30), "✺")     # gold
	_add(&"chassis",     "Chassis",        Tier.PART, Color(0.62, 0.62, 0.66), "▤")     # silver
	_add(&"fuel_tank",   "Fuel Tank",      Tier.PART, Color(0.32, 0.65, 0.38), "▢")     # forest green
	_add(&"scope",       "Scope",          Tier.PART, Color(0.70, 0.50, 0.88), "⊜")     # purple

	# Tier 3 inventions — each gets a unique vibrant color
	_add(&"fan",            "Fan",             Tier.INVENTION, Color(0.88, 0.50, 0.42), "❀")     # coral
	_add(&"projector",      "Projector",       Tier.INVENTION, Color(0.48, 0.38, 0.78), "►")     # indigo
	_add(&"spotlight",      "Spotlight",       Tier.INVENTION, Color(0.95, 0.78, 0.22), "✦")     # bright amber
	_add(&"display_case",   "Display Case",    Tier.INVENTION, Color(0.38, 0.62, 0.85), "◫")     # ocean blue
	_add(&"lamp_post",      "Lamp Post",       Tier.INVENTION, Color(0.90, 0.68, 0.25), "✸")     # warm amber
	_add(&"steam_engine",   "Steam Engine",    Tier.INVENTION, Color(0.82, 0.38, 0.32), "Ξ")     # brick red
	_add(&"clock",          "Clock",           Tier.INVENTION, Color(0.42, 0.55, 0.78), "Θ")     # slate blue
	_add(&"winch",          "Winch",           Tier.INVENTION, Color(0.72, 0.52, 0.32), "↻")     # bronze
	_add(&"telescope",      "Telescope",       Tier.INVENTION, Color(0.35, 0.48, 0.82), "☉")     # royal blue
	_add(&"oven",           "Oven",            Tier.INVENTION, Color(0.82, 0.48, 0.30), "Ω")     # terracotta
	_add(&"generator",      "Generator",       Tier.INVENTION, Color(0.32, 0.72, 0.42), "Ζ")     # emerald
	_add(&"mail_sorter",    "Power Loom",      Tier.INVENTION, Color(0.68, 0.65, 0.30), "⊠")     # olive gold
	_add(&"cart",           "Cable Car",       Tier.INVENTION, Color(0.78, 0.52, 0.28), "▭")     # rust
	_add(&"carriage",       "Carriage",        Tier.INVENTION, Color(0.62, 0.40, 0.65), "▰")     # plum
	_add(&"steam_scope",    "Periscope",       Tier.INVENTION, Color(0.75, 0.40, 0.58), "Ψ")     # rose
	_add(&"lantern_window", "Lantern Window",  Tier.INVENTION, Color(0.45, 0.78, 0.60), "▥")     # mint
	_add(&"signal_lamp",    "Signal Lamp",     Tier.INVENTION, Color(0.88, 0.55, 0.38), "❂")     # warm orange
	_add(&"mail_box",       "Signal Relay",    Tier.INVENTION, Color(0.38, 0.65, 0.60), "⊟")     # teal green
	_add(&"camera",         "Camera",          Tier.INVENTION, Color(0.40, 0.42, 0.65), "◉")     # navy
	_add(&"workbench_tool", "Wiring Rig",      Tier.INVENTION, Color(0.72, 0.50, 0.35), "Τ")     # copper

	# Tier 4 masterworks — premium feel
	_add(&"cinema_machine", "Cinema Machine",  Tier.MASTERWORK, Color(0.92, 0.72, 0.28), "✪")   # rich gold
	_add(&"clock_tower",    "Clock Tower",     Tier.MASTERWORK, Color(0.58, 0.40, 0.78), "♛")   # royal purple
	_add(&"factory",        "Factory",         Tier.MASTERWORK, Color(0.80, 0.38, 0.32), "▩")   # deep red
	_add(&"photo_studio",   "Photo Studio",    Tier.MASTERWORK, Color(0.50, 0.55, 0.78), "◐")   # periwinkle
	_add(&"observatory",    "Observatory",     Tier.MASTERWORK, Color(0.32, 0.52, 0.85), "✧")   # deep blue

func _add(id: StringName, name: String, tier: int, color: Color, glyph: String) -> void:
	defs[id] = ItemDef.new(id, name, tier, color, glyph)

func _build_recipes() -> void:
	# Same+same upgrade chain (junk -> component -> part)
	var t0_to_t1 := {
		&"bolt": &"bolt_bundle", &"spring": &"coil", &"wire": &"wire_spool",
		&"cog": &"gear", &"glass": &"glass_panel", &"pipe": &"copper_tube",
		&"bulb": &"lit_bulb", &"scrap": &"plate", &"oil": &"oil_canister",
		&"lens": &"magnifier",
	}
	var t1_to_t2 := {
		&"bolt_bundle": &"frame", &"coil": &"motor", &"wire_spool": &"harness",
		&"gear": &"gearbox", &"glass_panel": &"window", &"copper_tube": &"boiler",
		&"lit_bulb": &"lantern", &"plate": &"chassis", &"oil_canister": &"fuel_tank",
		&"magnifier": &"scope",
	}
	for src in t0_to_t1: upgrade[src] = t0_to_t1[src]
	for src in t1_to_t2: upgrade[src] = t1_to_t2[src]

	# Cross-combines: Tier 2 + Tier 2 (different) -> Tier 3 invention
	_cross(&"motor",   &"frame",     &"fan")
	_cross(&"motor",   &"scope",     &"projector")
	_cross(&"motor",   &"lantern",   &"spotlight")
	_cross(&"frame",   &"window",    &"display_case")
	_cross(&"frame",   &"lantern",   &"lamp_post")
	_cross(&"boiler",  &"chassis",   &"steam_engine")
	_cross(&"gearbox", &"frame",     &"clock")
	_cross(&"gearbox", &"harness",   &"winch")
	_cross(&"gearbox", &"scope",     &"telescope")
	_cross(&"fuel_tank", &"boiler",  &"oven")
	_cross(&"fuel_tank", &"motor",   &"generator")
	_cross(&"fuel_tank", &"harness", &"mail_sorter")
	_cross(&"chassis", &"harness",   &"cart")
	_cross(&"chassis", &"window",    &"carriage")
	_cross(&"boiler",  &"scope",     &"steam_scope")
	_cross(&"lantern", &"window",    &"lantern_window")
	_cross(&"lantern", &"scope",     &"signal_lamp")
	_cross(&"harness", &"scope",     &"mail_box")
	_cross(&"frame",   &"scope",     &"camera")
	_cross(&"frame",   &"harness",   &"workbench_tool")

	# Masterworks: Tier 3 + Tier 3 (different) -> Tier 4
	_cross(&"fan",        &"projector",     &"cinema_machine")
	_cross(&"clock",      &"lamp_post",     &"clock_tower")
	_cross(&"oven",       &"generator",     &"factory")
	_cross(&"camera",     &"spotlight",     &"photo_studio")
	_cross(&"telescope",  &"signal_lamp",   &"observatory")

func _cross(a: StringName, b: StringName, result: StringName) -> void:
	cross[_key(a, b)] = result

func _key(a: StringName, b: StringName) -> String:
	var sa := String(a); var sb := String(b)
	return sa + "|" + sb if sa < sb else sb + "|" + sa

func _build_stories() -> void:
	# Each entry: result_id -> story sentence.
	# Shown on the invention discovery card so the player learns WHY.
	stories = {
		# Level 1: Light & Glass
		&"fan":            "Mount a spinning motor on a sturdy frame — the blades whirl to life!",
		&"projector":      "A motor drives the reel while a scope focuses the beam — moving pictures!",
		&"spotlight":      "Attach a bright lantern to a motorized swivel — aim light anywhere!",
		&"display_case":   "Set glass windows into a frame — a see-through showcase!",
		&"lamp_post":      "Raise a glowing lantern on a tall frame — the street lights up!",
		# Level 2: Frame & Motion
		&"clock":          "Fit precision gears inside a frame — tick, tock, it tells time!",
		&"winch":          "Connect gears to wire cables — now you can lift heavy loads!",
		&"workbench_tool": "Stretch wires across a sturdy frame — an electrical assembly station!",
		&"cart":           "Wire cables pull the rolling chassis along — all aboard the cable car!",
		&"carriage":       "Add glass windows to a rolling chassis — passengers ride in style!",
		# Level 3: Optics
		&"telescope":      "Precision gears focus a magnifying scope — see the stars up close!",
		&"camera":         "Mount a focusing scope in a box frame — it captures images!",
		&"signal_lamp":    "Shine a lantern through a focusing scope — signals travel far!",
		&"mail_box":       "Run wires through a focusing lens — signals relay across distances!",
		&"steam_scope":    "Steam pressure raises a viewing scope — peer around corners!",
		# Level 4: Heat & Power
		&"steam_engine":   "Mount a steam boiler on a wheeled chassis — full steam ahead!",
		&"oven":           "Feed fuel into the boiler's heat chamber — now you're cooking!",
		&"generator":      "Burn fuel to spin a motor — it generates electricity!",
		&"mail_sorter":    "Fuel powers the wire-threading mechanism — it weaves on its own!",
		&"lantern_window": "Set a glowing lantern behind glass — the window shines warmly!",
		# Masterworks
		&"cinema_machine": "A fan cools the projector as it runs — grand cinema for all!",
		&"clock_tower":    "A giant clock crowns a lit lamp post — the town's proud landmark!",
		&"factory":        "An oven and generator together — mass production begins!",
		&"photo_studio":   "A camera paired with a spotlight — capture the perfect portrait!",
		&"observatory":    "A telescope aimed through a signal lamp — chart the heavens!",
	}

func get_story(id: StringName) -> String:
	return stories.get(id, "")

# Returns [parent_a_def, parent_b_def] for a cross-combine result, or [].
func get_parents(id: StringName) -> Array:
	for key in cross:
		if cross[key] == id:
			var ps: PackedStringArray = String(key).split("|")
			var a: ItemDef = get_def(StringName(ps[0]))
			var b: ItemDef = get_def(StringName(ps[1]))
			if a and b: return [a, b]
	return []

# --- Public API ---

func get_def(id: StringName) -> ItemDef:
	return defs.get(id, null)

func try_merge(a: StringName, b: StringName) -> StringName:
	if a == b:
		return upgrade.get(a, &"")
	return cross.get(_key(a, b), &"")

func random_junk() -> StringName:
	return JUNK_IDS[randi() % JUNK_IDS.size()]

func all_inventions() -> Array:
	var out: Array = []
	for id in defs:
		var d: ItemDef = defs[id]
		if d.tier >= Tier.INVENTION:
			out.append(id)
	return out

# --- Validation: catches bad recipe data at startup (per global CLAUDE.md test rule) ---
func _validate() -> void:
	for id in upgrade:
		assert(defs.has(id), "upgrade source missing def: %s" % id)
		assert(defs.has(upgrade[id]), "upgrade result missing def: %s" % upgrade[id])
		var src: ItemDef = defs[id]
		var dst: ItemDef = defs[upgrade[id]]
		assert(dst.tier == src.tier + 1, "upgrade tier mismatch: %s(t%d)->%s(t%d)" % [id, src.tier, upgrade[id], dst.tier])
	for k in cross:
		var result: StringName = cross[k]
		assert(defs.has(result), "cross result missing def: %s" % result)
		var parts: PackedStringArray = String(k).split("|")
		var a: StringName = StringName(parts[0])
		var b: StringName = StringName(parts[1])
		assert(defs.has(a) and defs.has(b), "cross sources missing: %s" % k)
		assert(a != b, "cross recipe with identical sides: %s" % k)
		var da: ItemDef = defs[a]; var dr: ItemDef = defs[result]
		assert(dr.tier == da.tier + 1, "cross tier mismatch: %s + %s -> %s" % [a, b, result])
