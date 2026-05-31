extends Node
## NPC + quest definitions. Market Square district (5 NPCs) for MVP.

class District:
	var id: StringName
	var name: String
	var icon: String
	var unlocked: bool
	func _init(id_: StringName, name_: String, icon_: String, unlocked_: bool) -> void:
		id = id_; name = name_; icon = icon_; unlocked = unlocked_

var districts: Array[District] = []

class NpcDef:
	var id: StringName
	var name: String
	var color: Color
	var problem: String
	var thanks: String
	var wants: StringName  # required invention id
	var building_label: String
	var level: int  # which level this NPC's area maps to (0-based)
	func _init(id_: StringName, name_: String, color_: Color, problem_: String, thanks_: String, wants_: StringName, building_label_: String, level_: int = -1) -> void:
		id = id_; name = name_; color = color_; problem = problem_; thanks = thanks_
		wants = wants_; building_label = building_label_; level = level_

var npcs: Array[NpcDef] = []

func _ready() -> void:
	# Each NPC owns a themed level — tapping them enters that area with a
	# fresh board and matching junk pool. Like Royal Match decoration areas.
	npcs = [
		NpcDef.new(&"lux", "Lamplighter Lux", Color(1.00, 0.82, 0.35),
			"Every street lamp is dark. Children won't walk home after dusk.",
			"The lane glows again — thank you, Tinker.",
			&"lamp_post", "Street Lamps", 0),       # Level 1: Light & Glass
		NpcDef.new(&"mayor", "Mayor Gearsworth", Color(0.62, 0.42, 0.88),
			"The clock tower hasn't ticked in years. The town needs its rhythm.",
			"It chimes again! The town remembers itself.",
			&"clock", "Clock Tower", 1),             # Level 2: Frame & Motion
		NpcDef.new(&"spark", "Professor Spark", Color(0.38, 0.70, 0.98),
			"My telescope is smashed. I cannot see the stars without it.",
			"The cosmos awaits! Come look anytime, friend.",
			&"telescope", "Observatory", 2),         # Level 3: Optics
		NpcDef.new(&"baker", "Baker Burnside", Color(0.95, 0.48, 0.32),
			"My oven broke! I can't make bread without it.",
			"Bless you, Tinker! The bakery smells like home again.",
			&"oven", "Bakery", 3),                   # Level 4: Heat & Power
		NpcDef.new(&"parcel", "Postmaster Parcel", Color(0.30, 0.74, 0.58),
			"Mail hasn't been delivered in months. Letters pile up unsorted.",
			"The post is moving again! Letters are flying.",
			&"mail_sorter", "Post Office", 4),       # Level 5: Masterworks
	]
	_ready_after_npcs()

func by_id(id: StringName) -> NpcDef:
	for n in npcs:
		if n.id == id: return n
	return null

func by_level(lvl: int) -> NpcDef:
	for n in npcs:
		if n.level == lvl: return n
	return null

func _districts_init() -> void:
	districts = [
		District.new(&"market",      "Market Square",     "🏘", true),
		District.new(&"residential", "Residential Lane",  "🏠", false),
		District.new(&"industrial",  "Industrial Quarter","🏭", false),
		District.new(&"hilltop",     "Hilltop Observatory","🔭", false),
	]

func _ready_after_npcs() -> void:
	_districts_init()
