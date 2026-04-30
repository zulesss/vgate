class_name FovController extends Node

# FOV pipeline: final_fov = base_fov + sustained_offset + sum(active kicks).
# - base_fov ставит player.gd каждый кадр через set_base() из cap_to_fov()
#   single-axis mapping (см. docs/feel/feel_spec.md §1, revised 2026-04-27).
# - sustained_offset — long-held offset для Kill Chain Tier 7+ streak (sustained
#   higher FOV пока streak активен). Tween'ится к target за ramp_time через
#   set_sustained_offset(); clear_sustained_offset() возвращает к 0.
# - kicks — transient offsets (kill-burst §2 punch, dash §3 stretch). Каждый
#   kick декаит к 0 по своей easing-curve и удаляется когда отжил.
#
# Аддитивность: при отсутствии kicks и sustained=0 final_fov == base_fov ровно
# (без drift'а). Когда kick кончился (elapsed >= duration) — удаляется в том же кадре.

@export var camera_path: NodePath
@export var base_fov: float = 90.0
@export var min_fov: float = 58.0  # spec §1: ниже не идти, motion sickness

var _camera: Camera3D
var _kicks: Array[Dictionary] = []  # [{magnitude, duration, elapsed, easing}]
var _target_base: float = 90.0
var _base_smooth_seconds: float = 0.0  # 0 = snap, >0 = exponential tracking

# Sustained offset (Kill Chain Tier 7+ streak). Linear tween от _sustained_offset_current
# к _sustained_offset_target за _sustained_ramp_remaining (sec). Когда remaining→0 —
# current snap'ится к target. Per-frame в _process суммируется к final_fov.
var _sustained_offset_current: float = 0.0
var _sustained_offset_target: float = 0.0
var _sustained_offset_start: float = 0.0  # snapshot текущего на момент set/clear, для линейного lerp
var _sustained_ramp_total: float = 0.0
var _sustained_ramp_elapsed: float = 0.0


func _ready() -> void:
	if camera_path != NodePath(""):
		_camera = get_node_or_null(camera_path) as Camera3D
	_target_base = base_fov


func set_camera(cam: Camera3D) -> void:
	_camera = cam


# Player.gd зовёт каждый кадр с base FOV из cap_to_fov(velocity_cap). smooth_seconds
# задаёт время сглаживания (~63% к target за указанное время через экспоненциальное
# приближение). 0.0 = snap. Spec §1 (revised): single-axis cap mapping, 100ms
# смягчает дёрганье на дискретных событиях (hit −15 cap, kill +25 cap).
func set_base(target_fov: float, smooth_seconds: float = 0.0) -> void:
	_target_base = target_fov
	_base_smooth_seconds = smooth_seconds
	if smooth_seconds <= 0.0:
		base_fov = target_fov


# Transient kick. easing один из: "ease_out_cubic", "ease_out_quart", "ease_out".
# duration_ms — продолжительность декаа от magnitude к 0.
func kick(magnitude: float, duration_ms: int, easing: String = "ease_out_cubic") -> void:
	_kicks.append({
		"magnitude": magnitude,
		"duration": float(duration_ms) / 1000.0,
		"elapsed": 0.0,
		"easing": easing,
	})


# Sustained offset (Kill Chain Tier 7+). Tween от current к offset_deg за ramp_time.
# Нулевой ramp_time = snap. Используется в паре с clear_sustained_offset для
# entry/exit.
func set_sustained_offset(offset_deg: float, ramp_time: float) -> void:
	_sustained_offset_start = _sustained_offset_current
	_sustained_offset_target = offset_deg
	_sustained_ramp_total = maxf(0.0, ramp_time)
	_sustained_ramp_elapsed = 0.0
	if _sustained_ramp_total <= 0.0:
		_sustained_offset_current = offset_deg


# Sustained offset cleanup: tween к 0 за ramp_time. Симметрично set_sustained_offset.
func clear_sustained_offset(ramp_time: float) -> void:
	set_sustained_offset(0.0, ramp_time)


func _process(delta: float) -> void:
	if _camera == null:
		return

	# Smooth-track base toward target. Exponential approach: каждый кадр сокращаем
	# разрыв на (delta / smooth_seconds), capped к 1.0. На дискретных hit/kill
	# событиях даёт ~100ms ramp вместо мгновенного скачка.
	if _base_smooth_seconds > 0.0 and base_fov != _target_base:
		var step: float = clampf(delta / _base_smooth_seconds, 0.0, 1.0)
		base_fov = lerpf(base_fov, _target_base, step)

	# Sustained offset linear ramp. Когда remaining→0, snap'имся на target и больше
	# не лерпим. Линейный лерп достаточен для 0.3-0.4с ramp'а (пользователь не
	# различит nuance ease curve на таком окне).
	if _sustained_ramp_total > 0.0 and _sustained_offset_current != _sustained_offset_target:
		_sustained_ramp_elapsed = minf(_sustained_ramp_total, _sustained_ramp_elapsed + delta)
		var sr_t: float = _sustained_ramp_elapsed / _sustained_ramp_total
		_sustained_offset_current = lerpf(_sustained_offset_start, _sustained_offset_target, sr_t)
		if sr_t >= 1.0:
			_sustained_offset_current = _sustained_offset_target

	var kick_sum: float = 0.0
	# Iterate backwards чтобы удалять отжившие inplace.
	for i in range(_kicks.size() - 1, -1, -1):
		var k: Dictionary = _kicks[i]
		k["elapsed"] = (k["elapsed"] as float) + delta
		var elapsed: float = k["elapsed"]
		var dur: float = k["duration"]
		if elapsed >= dur:
			_kicks.remove_at(i)
			continue
		var t: float = elapsed / dur  # 0..1 progress
		var remaining: float = _ease_remaining(t, k["easing"] as String)
		kick_sum += (k["magnitude"] as float) * remaining

	var final_fov: float = base_fov + _sustained_offset_current + kick_sum
	if final_fov < min_fov:
		final_fov = min_fov
	_camera.fov = final_fov


# Возвращает оставшуюся долю (1.0 в начале → 0.0 в конце) для kick decay.
# t — нормализованный progress 0..1.
static func _ease_remaining(t: float, easing: String) -> float:
	match easing:
		"ease_out_cubic":
			# y = 1 - (1-t)^3 — стандартный ease-out-cubic для decay'а:
			# в начале быстро, в конце плавно к нулю.
			var inv: float = 1.0 - t
			return inv * inv * inv
		"ease_out_quart":
			var inv2: float = 1.0 - t
			return inv2 * inv2 * inv2 * inv2
		"ease_out":
			# Simple quadratic ease-out for decay.
			var inv3: float = 1.0 - t
			return inv3 * inv3
		_:
			return 1.0 - t  # linear fallback
