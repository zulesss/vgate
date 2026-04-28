extends ColorRect
class_name VignetteFlash

# Peripheral vignette flash on Events.enemy_killed (M2 Iter 2 swap).
# Заменяет Velocity Exhale particles (commit 3afcffa) — юзер протестил, "не то".
# Эффект: на kill периферия экрана коротко подсвечивается light-cyan,
# центр без изменений. Layered поверх Iter 1 (FOV punch + audio crack);
# параллельный subscriber на Events.enemy_killed.

# Spec из брифа M2 Iter 2 swap:
#   Stage 1: 0 → 0.4 за 50ms (rise, ease-out-quad)
#   Stage 2: 0.4 → 0 за 100ms (decay, ease-in-quad)
# Total 150ms — subtle coda, не drama.
const FLASH_PEAK := 0.4
const RISE_MS := 50
const DECAY_MS := 100

# Material — ShaderMaterial из main.tscn sub-resource. Кастуем один раз в _ready,
# дальше работаем с типизированной ссылкой (без runtime is-checks per call).
var _shader_mat: ShaderMaterial
var _tween: Tween

func _ready() -> void:
	_shader_mat = material as ShaderMaterial
	# Стартовое состояние: невидим.
	_shader_mat.set_shader_parameter("flash_intensity", 0.0)
	if not Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.connect(_on_enemy_killed)

func _on_enemy_killed(_restore: int, _pos: Vector3, _type: String) -> void:
	# Graceful skip if player dead — иначе vignette может зависнуть на peak alpha
	# до restart (DeathScreen + RunLoop, 3.3с минимум). Hit-stop autoload не
	# трогаем — оба слоя независимы.
	if not VelocityGate.is_alive:
		return
	# Перезапускаем tween — каждый kill сбрасывает любую текущую анимацию,
	# даже если предыдущая ещё не завершилась (kill chain не накапливает яркость).
	# is_valid() уже учитывает null/killed, отдельная проверка != null лишняя.
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_intensity, 0.0, FLASH_PEAK, float(RISE_MS) / 1000.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_intensity, FLASH_PEAK, 0.0, float(DECAY_MS) / 1000.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _set_intensity(v: float) -> void:
	_shader_mat.set_shader_parameter("flash_intensity", v)
