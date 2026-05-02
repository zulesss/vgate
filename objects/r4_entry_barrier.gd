extends CSGBox3D

# Phased journey progression barrier (Arena C). Стоит на C34→R4 boundary
# (z=147, narrow 4u corridor exit) и блокирует игрока от skip'а в boss-room
# до того как clear'нуты все non-R4 враги.
#
# Phase 1: барьер активен, player чистит R1/R2/R3/коридоры/rear pursuers.
# Phase 2: non-R4 count == 0 → барьер открывается (visible=false + collision off).
#          Pre-placed R4 враги (boss + R4_Melee1 + R4_Shooter1/2) тегнуты в группе
#          "r4_phase" → они НЕ counted в non-R4. Win path остаётся прежний:
#          run_loop._all_enemies_dead() polls "enemy" группу — R4 враги в обеих
#          группах ("enemy" + "r4_phase") и тоже должны умереть для win'а.
#
# Idempotent: открывшись, остаётся открытым до run_started reset (который
# восстанавливает barrier перед следующим run'ом).

const R4_PHASE_GROUP := &"r4_phase"
const ENEMY_GROUP := &"enemy"

var _opened: bool = false


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	_reset()


func _process(_delta: float) -> void:
	if _opened:
		return
	# non-R4 count = total enemies - R4-phase enemies. Когда non-R4 → 0
	# (кроме pre-placed R4) — открыть барьер. Pre-placed R4 враги остаются
	# alive в момент открытия; player зайдёт и обязан их убить для win'а
	# (run_loop polls "enemy" группу).
	var tree: SceneTree = get_tree()
	var total: int = tree.get_nodes_in_group(ENEMY_GROUP).size()
	var r4_count: int = tree.get_nodes_in_group(R4_PHASE_GROUP).size()
	if total - r4_count <= 0:
		_open()


func _open() -> void:
	_opened = true
	visible = false
	use_collision = false


func _on_run_started() -> void:
	_reset()


func _reset() -> void:
	_opened = false
	visible = true
	use_collision = true
