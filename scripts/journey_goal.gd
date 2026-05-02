class_name JourneyGoal extends Area3D

# M10 Journey (Arena C "Дорога") — win-trigger Area3D в финале уровня.
# body_entered с проверкой group "player" → emit Events.journey_complete.
# RunLoop._on_journey_complete ловит signal, фризит is_alive, эмитит run_won.
#
# Idempotency: _triggered guard защищает от double-fire (player может
# выйти/войти в Area3D пока RunLoop процессит win — теоретически на
# единственном кадре между body_entered и is_alive=false. Lazy gate всё
# равно нужен).

var _triggered: bool = false


func _ready() -> void:
	# Defensive: явно включаем monitoring (default true, но scene-level override
	# мог бы отрубить — пинаем явно чтобы investigation 2026-05-02 win-trigger
	# silent fail однозначно исключил эту гипотезу).
	monitoring = true
	body_entered.connect(_on_body_entered)
	# DEBUG-GOAL-TRIGGER (2026-05-02): юзер playtest — body_entered не фаерится.
	# Ловим body_shape_entered тоже — диагностика. Удалить после следующего
	# плейтеста с подтверждённым win-trigger'ом.
	print("[GoalTrigger] _ready: monitoring=", monitoring,
		" collision_mask=", collision_mask,
		" global_pos=", global_position)


func _on_body_entered(body: Node) -> void:
	# DEBUG-GOAL-TRIGGER: лог любого тела на входе. Убрать вместе с _ready print'ом.
	print("[GoalTrigger] body_entered: body=", body,
		" name=", body.name,
		" in_player_group=", body.is_in_group("player"))
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	_triggered = true
	Events.journey_complete.emit()
