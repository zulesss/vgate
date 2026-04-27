class_name EnemyDummy extends CharacterBody3D

# M1 dummy враг — minimum viable: stand still, receive damage from player blaster,
# контактом наносит melee penalty player'у через VelocityGate. Без AI / pathing — это M3.
# 1 HP — концепт "kill = ресурс" работает уже на одном hit'е, balance по HP в M3.

@export var hp: int = 1

@onready var contact_area: Area3D = $ContactArea


func _ready() -> void:
	add_to_group("enemy")
	contact_area.body_entered.connect(_on_contact_body_entered)


# Зовётся player.gd → action_shoot → raycast collider.damage(weapon.damage).
# Имя метода + untyped amount — Starter Kit convention (damage у них float).
func damage(amount) -> void:
	print("[TRACE EnemyDummy.damage] amount=", amount, " hp_before=", hp, " name=", name, " path=", get_path())
	hp -= int(amount)
	if hp <= 0:
		die()


func die() -> void:
	print("[TRACE EnemyDummy.die] global_pos=", global_position)
	VelocityGate.apply_kill_restore(global_position)
	queue_free()


func _on_contact_body_entered(body: Node) -> void:
	print("[TRACE EnemyDummy contact] body=", body, " is_player=", body.is_in_group("player"))
	if not body.is_in_group("player"):
		return
	# i-frames гасятся внутри VelocityGate.apply_hit — здесь просто шлём.
	VelocityGate.apply_hit(VelocityGate.MELEE_PENALTY)
