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
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	_triggered = true
	Events.journey_complete.emit()
