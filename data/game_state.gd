extends Node
## Persistent game state. Save/load to user://save.json.

signal steam_changed(value: int)
signal invention_discovered(id: StringName)
signal quest_completed(npc_id: StringName)
signal board_changed

const SAVE_PATH := "user://save.json"
const STEAM_MAX := 30
const STEAM_REGEN_SECONDS := 120  # 1 per 2 min
const BOARD_W := 4
const BOARD_H := 4

var steam: int = STEAM_MAX
var last_regen_unix: int = 0

# Board: BOARD_H rows of BOARD_W cells; each cell is StringName ("") or item id
var board: Array = []

# Discovered invention ids (StringNames)
var discovered: Dictionary = {}  # id -> true

# NPC quest state: npc_id -> "available" | "active" | "done"
var quests: Dictionary = {}

# Pending chute queue
var chute_queue: Array = []  # of StringName
const CHUTE_MAX := 3

var tutorial_seen: bool = false
var workshop_complete_seen: bool = false  # gates the one-time "all inventions" celebration
var levels_seen: Dictionary = {}  # level index -> true, gates per-level completion toasts
var current_level: int = 0  # the level the player is actively working on

func _ready() -> void:
	_init_board()
	load_game()
	_regen_tick()
	# Periodically regen steam
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_regen_tick)
	add_child(t)

func _init_board() -> void:
	board.clear()
	for y in BOARD_H:
		var row: Array = []
		for x in BOARD_W:
			row.append(&"")
		board.append(row)

func get_cell(x: int, y: int) -> StringName:
	if x < 0 or x >= BOARD_W or y < 0 or y >= BOARD_H: return &""
	return board[y][x]

func set_cell(x: int, y: int, id: StringName) -> void:
	board[y][x] = id
	board_changed.emit()

func find_empty_cell() -> Vector2i:
	# Top-down, left-right
	for y in BOARD_H:
		for x in BOARD_W:
			if board[y][x] == &"": return Vector2i(x, y)
	return Vector2i(-1, -1)

func try_place_from_chute() -> bool:
	if chute_queue.is_empty(): return false
	var cell := find_empty_cell()
	if cell.x < 0: return false
	set_cell(cell.x, cell.y, chute_queue.pop_front())
	return true

func push_chute(id: StringName) -> bool:
	if chute_queue.size() >= CHUTE_MAX: return false
	chute_queue.append(id)
	return true

func spend_steam(amount: int = 1) -> bool:
	if steam < amount: return false
	steam -= amount
	steam_changed.emit(steam)
	return true

func add_steam(amount: int) -> void:
	steam = min(STEAM_MAX, steam + amount) if amount > 0 else steam
	# Energy purchases via IAP can exceed max — that's post-MVP. Cap at max for now.
	steam_changed.emit(steam)

func _regen_tick() -> void:
	var now := int(Time.get_unix_time_from_system())
	if last_regen_unix == 0:
		last_regen_unix = now; return
	if steam >= STEAM_MAX:
		last_regen_unix = now; return
	var elapsed := now - last_regen_unix
	var gained := elapsed / STEAM_REGEN_SECONDS
	if gained <= 0: return
	steam = min(STEAM_MAX, steam + gained)
	last_regen_unix += gained * STEAM_REGEN_SECONDS
	steam_changed.emit(steam)

func discover(id: StringName) -> bool:
	if discovered.has(id): return false
	discovered[id] = true
	invention_discovered.emit(id)
	return true

func is_discovered(id: StringName) -> bool:
	return discovered.has(id)

func quest_status(npc_id: StringName) -> String:
	return quests.get(npc_id, "available")

func set_quest_status(npc_id: StringName, status: String) -> void:
	quests[npc_id] = status
	if status == "done":
		quest_completed.emit(npc_id)

# --- Save / Load ---

func save_game() -> void:
	var data := {
		"steam": steam,
		"last_regen": last_regen_unix,
		"board": _board_to_strings(),
		"discovered": discovered.keys().map(func(k): return String(k)),
		"quests": _quests_to_strings(),
		"chute": chute_queue.map(func(k): return String(k)),
		"tutorial_seen": tutorial_seen,
		"workshop_complete_seen": workshop_complete_seen,
		"levels_seen": levels_seen.keys().map(func(k): return int(k)),
		"current_level": current_level,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(data))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return
	steam = int(parsed.get("steam", STEAM_MAX))
	last_regen_unix = int(parsed.get("last_regen", 0))
	var b = parsed.get("board", null)
	if b is Array and b.size() == BOARD_H:
		for y in BOARD_H:
			var row = b[y]
			if row is Array and row.size() == BOARD_W:
				for x in BOARD_W:
					board[y][x] = StringName(str(row[x]))
	discovered.clear()
	for s in parsed.get("discovered", []):
		discovered[StringName(str(s))] = true
	quests.clear()
	for k in parsed.get("quests", {}):
		quests[StringName(str(k))] = str(parsed["quests"][k])
	chute_queue.clear()
	for s in parsed.get("chute", []):
		chute_queue.append(StringName(str(s)))
	tutorial_seen = bool(parsed.get("tutorial_seen", false))
	workshop_complete_seen = bool(parsed.get("workshop_complete_seen", false))
	levels_seen.clear()
	for k in parsed.get("levels_seen", []):
		levels_seen[int(k)] = true
	current_level = int(parsed.get("current_level", 0))

func _board_to_strings() -> Array:
	var out: Array = []
	for y in BOARD_H:
		var row: Array = []
		for x in BOARD_W: row.append(String(board[y][x]))
		out.append(row)
	return out

func _quests_to_strings() -> Dictionary:
	var out := {}
	for k in quests: out[String(k)] = quests[k]
	return out

func clear_board() -> void:
	# Wipe the board (used between levels). Chute queue cleared too.
	_init_board()  # also emits board_changed
	chute_queue.clear()

func advance_to_level(idx: int) -> void:
	current_level = idx
	clear_board()
	save_game()

func reset() -> void:
	steam = STEAM_MAX
	last_regen_unix = int(Time.get_unix_time_from_system())
	_init_board()
	discovered.clear()
	quests.clear()
	chute_queue.clear()
	levels_seen.clear()
	current_level = 0
	workshop_complete_seen = false
	# tutorial_seen left alone — replaying the tutorial is annoying.
	save_game()
	board_changed.emit()
	steam_changed.emit(steam)
