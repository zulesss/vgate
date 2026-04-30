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
		available[0].stream = load(queue.pop_front())
		available[0].play()
		available[0].pitch_scale = randf_range(0.9, 1.1)
		available.pop_front()
