extends Node
## Procedural SFX. Synthesises short tone clips at startup so we don't ship
## placeholder WAVs. Real composed BGM/SFX can replace these post-MVP.

const SAMPLE_RATE := 22050

var _player: AudioStreamPlayer
var _clips: Dictionary = {}  # name -> AudioStreamWAV

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_clips["place"]    = _make_clip([440.0, 660.0], 0.06, "decay")
	_clips["merge"]    = _make_clip([523.25, 783.99], 0.14, "decay")          # C5 → G5 chime
	_clips["discover"] = _make_clip([523.25, 659.25, 783.99, 1046.50], 0.55, "decay")  # C-E-G-C arpeggio
	_clips["deliver"]  = _make_clip([392.0, 523.25, 659.25], 0.40, "decay")   # G-C-E triumph
	_clips["nope"]     = _make_clip([196.0, 165.0], 0.18, "decay")            # low buzz
	# Apply the persisted mute preference. GameState autoloads BEFORE Audio (see
	# project.godot order) and loads the save in its _ready, so GameState.muted is
	# already correct here.
	AudioServer.set_bus_mute(0, GameState.muted)  # bus 0 = Master

func play_sfx(name: String) -> void:
	if GameState.muted: return
	var clip = _clips.get(name)
	if clip == null: return
	_player.stream = clip
	_player.play()

func set_muted(m: bool) -> void:
	GameState.muted = m
	GameState.save_game()
	AudioServer.set_bus_mute(0, m)  # bus 0 = Master

func is_muted() -> bool:
	return GameState.muted

func play_bgm(_track: String) -> void:
	pass  # real composed BGM is post-MVP

func stop_bgm() -> void:
	pass

# --- Synthesizer ---

func _make_clip(notes: Array, total_seconds: float, envelope: String) -> AudioStreamWAV:
	var sample_count := int(SAMPLE_RATE * total_seconds)
	var per_note: int = max(1, sample_count / notes.size())
	var data := PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit mono
	var idx := 0
	for n in notes.size():
		var freq: float = float(notes[n])
		for i in per_note:
			if idx >= sample_count: break
			var t := float(i) / SAMPLE_RATE
			var env := 1.0
			match envelope:
				"decay":
					env = clamp(1.0 - float(i) / per_note, 0.0, 1.0)
				_:
					env = 1.0
			# Slight square-wave bias for a "mechanical" texture.
			var sine := sin(TAU * freq * t)
			var square := 1.0 if sine >= 0.0 else -1.0
			var sample := (0.7 * sine + 0.3 * square) * env * 0.45
			var s16 := int(clamp(sample, -1.0, 1.0) * 32767)
			data.encode_s16(idx * 2, s16)
			idx += 1
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
