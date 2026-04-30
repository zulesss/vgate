extends Node

# Code adapted from KidsCanCode

var num_players = 12
var bus: StringName = &"SFX"

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

func _ready():
	for i in num_players:
		var p = AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = -10
		add_child(p)
		p.finished.connect(_on_stream_finished.bind(p))
		available.append(p)

func _on_stream_finished(stream):
	available.append(stream)

func play(sound_path):  # Path (or multiple, separated by commas)
	var sounds = sound_path.split(",")
	queue.append("res://" + sounds[randi() % sounds.size()].strip_edges())

func _process(_delta):
	if not queue.is_empty() and not available.is_empty():
		var path: String = queue.pop_front()
		available[0].stream = load(path)
		var p: AudioStreamPlayer = available[0]
		var bus_name: StringName = p.bus
		var bus_idx: int = AudioServer.get_bus_index(bus_name)
		var bus_db: float = AudioServer.get_bus_volume_db(bus_idx) if bus_idx >= 0 else -999.0
		print("[AUDIO] audio.gd | pool_play | %s | bus=%s idx=%d bus_db=%.1f player_db=%.1f" % [
			path, str(bus_name), bus_idx, bus_db, p.volume_db,
		])
		p.play()
		p.pitch_scale = randf_range(0.9, 1.1)
		available.pop_front()
