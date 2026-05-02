class_name JourneyMilestone extends Area3D

# M10 Journey Pkg C — milestone trigger. Тонкая Area3D, перегораживающая
# коридор/проход на входе в room. body_entered с group "player" → emit
# Events.milestone_crossed(milestone_index). Idempotent через _triggered guard
# (одна Area3D = один fire), JourneyPursuer'ом дальше дедуплицируется через
# _milestones_fired dictionary (на случай повторного reload арены без full run
# reset — defensive both sides).
#
# Pattern mirror'ит journey_goal.gd — простая door-trigger логика, никаких
# physics processing'а. monitoring=true явный для надёжности (default true,
# но lock'аем чтобы scene-level override не сломал).

@export var milestone_index: int = 0

var _triggered: bool = false


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	if milestone_index <= 0:
		push_warning("JourneyMilestone: milestone_index не задан или невалиден (%d)" % milestone_index)
		return
	_triggered = true
	Events.milestone_crossed.emit(milestone_index)
