class_name DebugHud extends CanvasLayer

# Читалка VelocityGate state'а в верхнем левом углу. M1 only — для проверки механики
# глазами, в M2 либо удалить, либо повесить на toggle. Не источник UX feedback'а
# (это feel_spec — FOV/audio/bob), а debug-overlay.

@onready var label: Label = $Panel/Label

var _player: Node = null


func _ready() -> void:
	# Player находим на старте; если ещё не в дереве — найдём в _process.
	_resolve_player()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()

	var dash_cooldown_text := "n/a"
	if _player and _player.has_method("get_dash_cooldown_remaining"):
		dash_cooldown_text = "%.2f" % _player.get_dash_cooldown_remaining()

	label.text = "velocity_cap: %.1f\ncurrent_speed: %.2f\nspeed_ratio:  %.3f\ndrain_timer:  %.2f / %.2f\nis_draining:  %s\nis_alive:     %s\ndash_cd:      %s" % [
		VelocityGate.velocity_cap,
		VelocityGate.current_speed,
		VelocityGate.speed_ratio(),
		VelocityGate.drain_timer,
		VelocityGate.TOLERANCE_BELOW_THRESHOLD,
		str(VelocityGate.is_draining),
		str(VelocityGate.is_alive),
		dash_cooldown_text,
	]


func _resolve_player() -> void:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		_player = nodes[0]
