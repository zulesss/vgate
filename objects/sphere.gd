class_name ObjectiveSphere extends Node3D

# M9 Hot Zones — sphere objective (parallel-axis к kill economy).
# Lifetime 8с (LIFETIME), capture через Area3D body_entered (player walks through).
# На capture: эмитит Events.sphere_captured + visual flash + queue_free.
# На expire: эмитит Events.sphere_expired + queue_free (без flash).
#
# Visual — CSG SphereMesh (radius 0.6) + StandardMaterial3D с emissive cyan + point light.
# Pulsing animation на scale (0.95↔1.05) + idle bob. Последние 2с (LIFETIME-2 → LIFETIME):
# emissive lerp'ится cyan → red как expire telegraph.
#
# Spawn: SphereDirector instantiate'ит scene, ставит global_position, добавляет в parent
# (main scene либо Spheres-контейнер). Y из spec'а — capture-height 1.0 для Area3D,
# visual mesh центрируется на 1.5 (поднят чуть выше для glow читаемости).

const LIFETIME := 8.0
const EXPIRE_TELEGRAPH := 2.0  # за столько до expire начинаем cyan→red lerp
const PULSE_PERIOD := 1.0
const PULSE_AMPLITUDE := 0.05  # ±5% scale
# Note: visual Y offset (mesh выше Area3D) задан через Visual node transform в sphere.tscn (y=0.5).

const COLOR_NORMAL := Color(0.35, 0.92, 0.95)
const COLOR_EXPIRE := Color(0.95, 0.30, 0.25)
const COLOR_FLASH := Color(1.0, 1.0, 1.0)
const FLASH_DURATION := 0.18

@onready var area: Area3D = $Area
@onready var mesh: MeshInstance3D = $Visual/Mesh
@onready var light: OmniLight3D = $Visual/Light

var _age: float = 0.0
var _captured: bool = false
var _expired: bool = false
var _material: StandardMaterial3D = null


func _ready() -> void:
	# Material: каждой инстансе свой clone, чтобы expire telegraph / flash не
	# мутировал shared resource (scene-level material бы перекрашивал ВСЕ active spheres).
	# .tscn задаёт material_override на shared StandardMaterial3D — clone его в
	# per-instance копию, чтобы expire telegraph / capture flash не мутировали
	# shared resource (иначе перекрашивались бы ВСЕ active spheres).
	if mesh.material_override is StandardMaterial3D:
		_material = (mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		mesh.material_override = _material
		_material.albedo_color = COLOR_NORMAL
		_material.emission = COLOR_NORMAL
	# body_entered ловит CharacterBody3D игрока (player в group "player", layer 2).
	# area_entered не нужен — игрок body, не Area3D.
	area.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _captured or _expired:
		return
	_age += delta

	# Pulse: idle bob через scale modulation. Без tween (per-frame, simple sin).
	var pulse: float = 1.0 + sin(_age * TAU / PULSE_PERIOD) * PULSE_AMPLITUDE
	$Visual.scale = Vector3.ONE * pulse

	# Expire telegraph: за EXPIRE_TELEGRAPH секунд до конца цвет/emission lerp
	# cyan → red. Чистая визуальная подсказка "торопись".
	var time_left: float = LIFETIME - _age
	if _material != null:
		if time_left <= EXPIRE_TELEGRAPH:
			var t: float = clampf(1.0 - time_left / EXPIRE_TELEGRAPH, 0.0, 1.0)
			var c: Color = COLOR_NORMAL.lerp(COLOR_EXPIRE, t)
			_material.albedo_color = c
			_material.emission = c
			if light != null:
				light.light_color = c

	if _age >= LIFETIME:
		_on_lifetime_expired()


func _on_body_entered(body: Node) -> void:
	if _captured or _expired:
		return
	if not body.is_in_group("player"):
		return
	_captured = true
	# Stop new triggers — visual flash ещё играется, area shape disable'им чтобы
	# не дёрнуть signal повторно если physics tick'нет ещё раз внутри tween'а.
	area.set_deferred("monitoring", false)
	Events.sphere_captured.emit(global_position)
	_play_capture_flash()


func _on_lifetime_expired() -> void:
	if _captured or _expired:
		return
	_expired = true
	area.set_deferred("monitoring", false)
	Events.sphere_expired.emit(global_position)
	queue_free()


func _play_capture_flash() -> void:
	# Brief white flash на emission/albedo + scale punch, затем queue_free.
	# Tween_method чтобы и albedo и emission двигались синхронно. После flash
	# — queue_free (sphere больше не нужен).
	if _material == null:
		queue_free()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_material, "albedo_color", COLOR_FLASH, FLASH_DURATION * 0.4)
	tween.tween_property(_material, "emission", COLOR_FLASH, FLASH_DURATION * 0.4)
	tween.tween_property($Visual, "scale", Vector3.ONE * 1.4, FLASH_DURATION * 0.4)
	if light != null:
		tween.tween_property(light, "light_energy", light.light_energy * 3.0, FLASH_DURATION * 0.4)
	tween.chain().tween_callback(queue_free).set_delay(FLASH_DURATION * 0.6)
