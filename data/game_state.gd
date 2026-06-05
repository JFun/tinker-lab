extends Node
## Persistent game state. Save/load to user://save.json.

signal invention_discovered(id: StringName)
signal quest_completed(npc_id: StringName)
signal board_changed

# --- Funnel analytics signals (consumed only by systems/analytics.gd) ---
# Added to diagnose the first-session activation funnel (where do new players
# drop off: village -> workbench -> first merge -> building). Emitted from the
# gameplay code; never alter game behavior. Off-device the listener no-ops.
signal level_started(level_idx: int, npc_id: StringName)
signal merge_committed(result_id: StringName)
signal recycle_committed(item_id: StringName)
signal soft_lock_broken(offered: String)
signal tutorial_completed
# Daily-return hook: emitted once per calendar day when the streak advances and a
# delivery crate becomes pending. Consumed by analytics + (next launch) workbench.
signal daily_delivery_granted(streak: int)

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
var muted: bool = false  # global audio mute (Settings toggle); silences SFX via Master bus
var workshop_complete_seen: bool = false  # gates the one-time "all inventions" celebration
var levels_seen: Dictionary = {}  # level index -> true, gates per-level completion toasts
var current_level: int = 0  # the level the player is actively working on
# Lifetime merges across all sessions. Drives the adaptive idle-hint delay: a
# player who has never merged gets a faster first nudge (activation funnel — ~half
# of early players bounced before their first merge), ramping back to the calm 8s
# once they've made a few. Persisted so the help fades across sessions, not just
# within one. Incremented at the merge commit site in workbench.gd.
var lifetime_merges: int = 0

# --- Daily-return hook (1.0.1) ---
# Streak = consecutive calendar days the player opened the app. `last_open_date`
# is a local "YYYY-MM-DD" string. When a new day is detected, a delivery crate is
# queued (daily_delivery_pending) and claimed at the workbench on first arrival.
var last_open_date: String = ""
var streak: int = 0
var daily_delivery_pending: bool = false

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
		"muted": muted,
		"workshop_complete_seen": workshop_complete_seen,
		"levels_seen": levels_seen.keys().map(func(k): return int(k)),
		"current_level": current_level,
		"lifetime_merges": lifetime_merges,
		"last_open_date": last_open_date,
		"streak": streak,
		"daily_delivery_pending": daily_delivery_pending,
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
	muted = bool(parsed.get("muted", false))
	workshop_complete_seen = bool(parsed.get("workshop_complete_seen", false))
	levels_seen.clear()
	for k in parsed.get("levels_seen", []):
		levels_seen[int(k)] = true
	current_level = int(parsed.get("current_level", 0))
	lifetime_merges = int(parsed.get("lifetime_merges", 0))
	last_open_date = str(parsed.get("last_open_date", ""))
	streak = int(parsed.get("streak", 0))
	daily_delivery_pending = bool(parsed.get("daily_delivery_pending", false))

# --- Daily-return hook ---

## Called once at launch (real game only — main.gd gates out the dev harnesses).
## Advances the streak and queues a delivery crate when a new calendar day starts.
## Returns true if a delivery was armed for this launch.
func check_daily() -> bool:
	var today := _today_string()
	if last_open_date == today:
		return false  # already counted today
	# A brand-new install (no prior open date) starts the streak at 1 but gets NO
	# delivery — a "Welcome back!" crate makes no sense for someone who never left.
	# Deliveries begin on the first genuine return (the next consecutive day, or any
	# later calendar day after a gap). We still stamp today's date + streak so the
	# streak counts from the install day and tomorrow's return is a real day-2.
	var first_ever := last_open_date == ""
	var gap := _day_gap(last_open_date, today)
	if gap == 1:
		streak += 1  # consecutive day → extend streak
	else:
		streak = 1  # first ever, or a missed day → reset to 1
	last_open_date = today
	if first_ever:
		save_game()
		return false
	daily_delivery_pending = true
	save_game()
	daily_delivery_granted.emit(streak)
	return true

func _today_string() -> String:
	# Local-time "YYYY-MM-DD". get_date_string_from_system uses local time.
	return Time.get_date_string_from_system()

## Whole-day gap between two "YYYY-MM-DD" strings (b - a). Returns a large number
## if `a` is empty/unparseable so the caller treats it as a streak reset.
func _day_gap(a: String, b: String) -> int:
	if a == "":
		return 9999
	var ua := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var ub := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	if ua <= 0 or ub <= 0:
		return 9999
	return int(round((ub - ua) / 86400.0))

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
