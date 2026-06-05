extends Node
## First-party engagement analytics via the native Firebase Analytics SDK.
##
## GDScript can't call the Firebase iOS SDK directly, so this autoload writes
## one JSON event per line to `user://analytics_events.jsonl` and a native
## Swift file-watcher (AnalyticsBridge.swift, compiled into the iOS target)
## polls it once a second, forwards each line to FirebaseAnalytics.logEvent,
## and deletes the file. See FirebaseBootstrap.m for the launch-time wiring.
##
## Why this and NOT GA4 Measurement Protocol: Qi already runs the native
## Firebase SDK in other apps (gravity-flip) and wants the same pipeline —
## DebugView, auto first_open/session_start/screen_view, audiences. The build
## restructure that makes this survive Godot's per-deploy Xcode regeneration
## is documented in scripts/dev/deploy_ios.sh (commit the Xcode project at the
## repo root, deploy refreshes ONLY the .pck via --export-pack).
##
## Privacy: the native SDK collects IDFV + a Firebase Installation ID, so this
## is back to the standard casual-game profile (Usage Data → Product
## Interaction; Identifiers → Device ID; not linked, not tracking). No ads, no
## Google Signals, no data broker → still NOT "tracking" per Apple, no ATT.
##
## Off iOS (editor / desktop / test harness) this is a no-op — _should_enable()
## gates it so dev runs never litter user:// with an unconsumed buffer file.

const EVENT_FILE := "user://analytics_events.jsonl"
const USER_ID_FILE := "user://analytics_user_id.txt"
## Cap the buffer at 1 MB. If the native bridge falls behind (or there is no
## bridge — desktop), stop appending rather than fill the device.
const APPEND_LIMIT_BYTES := 1024 * 1024

var _user_id: String = ""
var _session_id: String = ""
var _enabled: bool = false
var _disabled: bool = false  # tripped if the buffer file blows past the cap
var _merged_this_session: bool = false  # gates the once-per-session first_merge

func _ready() -> void:
	_enabled = _should_enable()
	if not _enabled:
		return
	_user_id = _load_or_create_user_id()
	_session_id = _generate_id()

	# Wire to existing GameState signals so we never touch game logic. These
	# fire the engagement funnel: discoveries, building (quest) completions,
	# and the all-inventions campaign finale.
	GameState.invention_discovered.connect(_on_invention_discovered)
	GameState.quest_completed.connect(_on_quest_completed)
	# Activation-funnel signals: level_start (reached a board), first_merge
	# (engaged), tutorial_complete, plus recycle/soft-lock usage. These pinpoint
	# where new players drop off (50% of early real users bounced before merging).
	GameState.level_started.connect(_on_level_started)
	GameState.merge_committed.connect(_on_merge_committed)
	GameState.recycle_committed.connect(_on_recycle_committed)
	GameState.soft_lock_broken.connect(_on_soft_lock_broken)
	GameState.tutorial_completed.connect(_on_tutorial_completed)
	# Daily-return hook (1.0.1): fires once per calendar day the player returns.
	# This is the retention signal — pair it with game_open to read D1/D7.
	GameState.daily_delivery_granted.connect(_on_daily_delivery_granted)

	log_event("game_open", {
		"app_version": ProjectSettings.get_setting("application/config/version", "dev"),
	})

# --- Public API ---

## Appends one event to the JSONL buffer. Drops silently if anything fails —
## analytics must never break the game. Event names: lowercase + underscores,
## <=40 chars, avoiding GA4 reserved names. Param values: String/int/float/bool.
func log_event(event_name: String, params: Dictionary = {}) -> void:
	if not _enabled or _disabled:
		return
	_append(build_record(event_name, params))

## Sets a sticky Firebase user property (slices every later event). Low
## cardinality only (build_variant, etc.), never per-event data.
func set_user_property(name: String, value: String) -> void:
	if not _enabled or _disabled:
		return
	_append({"user_property": name, "value": value})

## Pure (no I/O) so it's unit-testable. Builds the JSONL record the bridge
## expects: {"name": ..., "params": {... + user_id, session_id, t}}.
func build_record(event_name: String, params: Dictionary) -> Dictionary:
	var enriched: Dictionary = params.duplicate()
	enriched["user_id"] = _user_id
	enriched["session_id"] = _session_id
	enriched["t"] = Time.get_unix_time_from_system()
	return {"name": event_name, "params": enriched}

# --- Signal handlers ---

func _on_invention_discovered(id: StringName) -> void:
	log_event("invention_discovered", {
		"invention_id": String(id),
		"total_discovered": GameState.discovered.size(),
	})
	# Campaign finale: all inventions discovered. Items.all_inventions() is the
	# canonical full list (same one the trophy grid iterates).
	var total: int = Items.all_inventions().size() if Items.has_method("all_inventions") else 0
	if total > 0 and GameState.discovered.size() >= total:
		log_event("campaign_complete", {"total": total})

func _on_quest_completed(npc_id: StringName) -> void:
	var npc = Npcs.by_id(npc_id)
	var params := {"npc_id": String(npc_id)}
	if npc != null:
		params["building"] = npc.building_label
		params["level"] = npc.level + 1  # 1-based for readability in reports
	log_event("building_complete", params)

# --- Activation funnel handlers ---

func _on_level_started(level_idx: int, npc_id: StringName) -> void:
	log_event("level_start", {
		"level": level_idx + 1,  # 1-based to match building_complete
		"npc_id": String(npc_id),
	})

func _on_merge_committed(result_id: StringName) -> void:
	# Only the FIRST merge per session — the activation milestone. Per-merge
	# events would be high-volume noise; discovery depth is already captured by
	# invention_discovered.total_discovered.
	if _merged_this_session:
		return
	_merged_this_session = true
	log_event("first_merge", {
		"result_id": String(result_id),
		"level": GameState.current_level + 1,
	})

func _on_recycle_committed(item_id: StringName) -> void:
	log_event("recycle_used", {"item_id": String(item_id)})

func _on_soft_lock_broken(offered: String) -> void:
	log_event("soft_lock_break", {"offered": offered})

func _on_tutorial_completed() -> void:
	log_event("tutorial_complete", {})

func _on_daily_delivery_granted(streak: int) -> void:
	log_event("daily_return", {"streak": streak})

# --- Internals ---

func _should_enable() -> bool:
	# Never write the buffer from editor plays, headless tools, or the dev
	# render/test harnesses (--test-hints, --shoot, --capture-transition,
	# --export...). The native bridge only exists in the iOS app anyway.
	if OS.has_feature("editor"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--test-hints") or a.begins_with("--shoot") \
			or a.begins_with("--capture-transition") or a.begins_with("--export"):
			return false
	return true

func _append(record: Dictionary) -> void:
	var line := JSON.stringify(record) + "\n"
	var f: FileAccess
	if FileAccess.file_exists(EVENT_FILE):
		# Stop appending if the buffer is huge (bridge missing / offline).
		var size := FileAccess.get_file_as_bytes(EVENT_FILE).size()
		if size > APPEND_LIMIT_BYTES:
			_disabled = true
			push_warning("Analytics: buffer exceeded %d bytes, disabling" % APPEND_LIMIT_BYTES)
			return
		# Append mode so concurrent calls don't clobber each other.
		f = FileAccess.open(EVENT_FILE, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(EVENT_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(line)
	f.close()

func _load_or_create_user_id() -> String:
	if FileAccess.file_exists(USER_ID_FILE):
		var f := FileAccess.open(USER_ID_FILE, FileAccess.READ)
		if f != null:
			var s := f.get_as_text().strip_edges()
			f.close()
			if s.length() >= 8:
				return s
	var fresh := _generate_id()
	var w := FileAccess.open(USER_ID_FILE, FileAccess.WRITE)
	if w != null:
		w.store_string(fresh)
		w.close()
	return fresh

func _generate_id() -> String:
	# 16 hex chars. Not a real UUID but plenty unique for the MVP audience.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hex := "0123456789abcdef"
	var s := ""
	for i in 16:
		s += hex[rng.randi_range(0, 15)]
	return s
