class_name EnemyBoss extends EnemyMelee

# Journey R4 boss — beefier melee, transactional final fight перед GoalTrigger.
# Identity: "this one is the boss" — golden HDR emissive + scale 1.6 + slower
# movement / longer telegraph. Final close-range showdown в narrow boss room.
#
# Отличия от Melee (base):
#   - HP 120 (3× regular melee 40) — ~24 repeater hits @5 dmg → ~4.8s sustained fire
#   - move_speed 4.0 (slower 5.5 → heavy / menacing read)
#   - attack_range 2.5 (longer reach — narrow R4, легче зацепить)
#   - attack_penalty 25 (выше melee 20 — single hit чувствуется)
#   - attack_cooldown 2.5 (slower swings — но telegraph длиннее)
#   - attack_windup 0.5 (longer telegraph 450→500ms)
#   - detection_radius 40 (raised — boss aware дальше regular 35)
#
# Visual differentiation — золотой emissive HDR через override material'а уже
# после super._ready'я (base clone'ит mesh material и держит его в _material).
# Mesh scale 1.6 ставится через visual_root в scene'е (transform на Visual node).
# Collision shape остаётся melee-default (radius 0.5, height 1.7) — boss
# физически такого же радиуса, не толще, иначе застрянет в narrow R4
# 6u-corridor'е.

const BOSS_EMISSION_COLOR := Color(2.0, 0.8, 0.3)  # HDR golden — > 1.0 даёт bloom при tonemap'е
const BOSS_EMISSION_ENERGY := 1.5


func _ready() -> void:
	# Stat overrides ДО super._ready (base скопирует hp = max_hp + начальный
	# stagger cooldown). Lunge оставляем включённым из melee parent'а — boss
	# тоже должен закрывать gap в финальные 300мс windup'а, иначе walk-back
	# escape'ит даже на slower 4.0 (player walk ~6.4 u/s при cap=80).
	max_hp = 120
	move_speed = 4.0
	attack_range = 2.5
	attack_windup = 0.5
	attack_cooldown = 2.5
	attack_penalty = 25
	detection_radius = 40.0
	super._ready()

	# Material override: super._ready клонировал base material из mesh'а (telegraph
	# flash работает на _material из base'а). Перезаписываем emission на golden HDR
	# и обновляем _base_emission_*, чтобы _end_telegraph (в melee.gd) возвращал именно
	# к boss-золоту, а не к стандартному melee-черному base'у.
	if _material != null:
		_material.emission_enabled = true
		_material.emission = BOSS_EMISSION_COLOR
		_material.emission_energy_multiplier = BOSS_EMISSION_ENERGY
		_base_emission_color = BOSS_EMISSION_COLOR
		_base_emission_energy = BOSS_EMISSION_ENERGY


func _kill_type() -> String:
	return "boss"
