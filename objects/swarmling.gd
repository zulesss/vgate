class_name EnemySwarmling extends EnemyBase

# M8 Swarmling — fast contact-melee, group-spawn (3-4), small visual.
# Identity: "один-два ничего не значат, рой опасен" (game-designer locked).
# Numbers from docs/systems/M8_swarmling_numbers.md (LOCKED). Visual placeholder
# через scaled melee_robot rig — отдельный rig swap'нем после research'а.
#
# Отличия от Melee:
#   - HP 3 (1-shot центральной пулей убивает)
#   - move_speed 7.7 (≈ player walk при cap=96; всегда чуть быстрее или ровня)
#   - attack_range 1.2 (capsule radius игрока + small margin)
#   - attack_windup 0 (instant contact damage — no telegraph анимации)
#   - attack_cooldown 1.8с (per-enemy, защита от tick-spam при sustained contact)
#   - penalty −5 (рой из 4 в контакте ≈ −20 cap/sec — fast drain only when surrounded)
#   - lunge OFF (default), turn_speed inherited
#
# Telegraph намеренно отсутствует: identity локед — "telegraph = сам факт сближения".


func _ready() -> void:
	max_hp = 3
	move_speed = 7.7
	attack_range = 1.2
	attack_windup = 0.0
	attack_cooldown = 1.8
	attack_penalty = VelocityGate.SWARMLING_PENALTY
	detection_radius = 35.0
	# lunge_speed/lunge_window default 0 — без lunge'а, swarmling и так быстрый.
	super._ready()


func _kill_type() -> String:
	return "swarmling"


# Telegraph отключён: windup=0, играть Charge на 1 кадр визуально шумит.
# Audio cue spawn'а уже есть (Sfx._on_enemy_spawned) — этого достаточно.
func _play_telegraph() -> void:
	pass


func _end_telegraph() -> void:
	pass


# Override: бьём напрямую без Attack one-shot'а (он бы прервался Run loop'ом
# на следующем тике из-за windup=0). Hit-анимация на damage()→_play_oneshot
# у игрока всё равно срабатывает — обратная связь для игрока остаётся.
func _resolve_attack() -> void:
	if not is_dying and _player != null:
		var dist := _distance_to_player()
		if dist <= attack_range:
			VelocityGate.apply_hit(attack_penalty)
	_attack_cooldown_remaining = attack_cooldown
	# Не вызываем super._resolve_attack() — оно только повторно ставит cooldown.
	# _is_winding_up уже flipped в false внутри _physics_process до вызова.


func _anim_for_state(s: int) -> StringName:
	# Placeholder rig (melee_robot) — переиспользуем тот же mapping что у Melee.
	# После asset swap'а на отдельный swarmling rig — обновим override.
	if s == State.CHASE:
		return &"Run"
	return &"Idle"


func _hit_anim_name() -> StringName:
	return &"Hit"


func _death_anim_name() -> StringName:
	return &"TurnOff"
