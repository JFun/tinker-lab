extends Node
## Persistent game state. Save/load to user://save.json.

signal invention_discovered(id: StringName)
signal quest_completed(npc_id: StringName)
signal board_changed

const SAVE_PATH := "user://save.json"
const BOARD_W := 4
const BOARD_H := 4

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
	# Seed the starting hand HERE (not only in workbench._ready) so a level switch
	# lands on a full, ready-to-merge board. The workbench re-instantiates behind a
	# crossfade, and the outgoing board's chute timer could otherwise dirty the
	# freshly-cleared board before the new _ready runs — making it skip seeding and
	# leaving the player waiting on the chute drip.
	seed_starter_hand()
	save_game()

func seed_starter_hand() -> void:
	# Fill the WHOLE board with mergeable pairs drawn from the current level's junk
	# pool, so a fresh level lands on a full, ready-to-merge board (8 pairs across
	# the 16 cells) rather than a half-empty one. Every placed junk gets its twin,
	# so there's always a merge available — a packed board can't soft-lock.
	# (On 4–8-junk levels every type appears; on the 10-junk levels only 8 fit, so
	# we shuffle to vary which two are held back for the chute to introduce later.)
	var junks: Array = Items.junks_for_level(current_level).duplicate()
	if junks.is_empty(): return
	junks.shuffle()
	var ji: int = 0
	while true:
		var a := find_empty_cell()
		if a.x < 0: break
		set_cell(a.x, a.y, junks[ji % junks.size()])
		var b := find_empty_cell()
		if b.x < 0: break  # odd cell left over (won't happen on a 16-cell board)
		set_cell(b.x, b.y, junks[ji % junks.size()])
		ji += 1

func reset() -> void:
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
