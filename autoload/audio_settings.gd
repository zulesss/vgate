class_name AudioSettingsNode extends Node

# M6 Audio settings autoload. Хранит per-bus volume в linear 0..1, persist'ит в
# user://vgate_settings.cfg секция [audio]. Apply через AudioServer.set_bus_volume_db().
#
# Defaults: на first launch читаются из текущего bus_layout (designer-tuned mix —
# Music=-3dB ≈ 0.708, Ambient=-12dB ≈ 0.251, Master/SFX=0dB → 1.0). Это сохраняет
# тщательно выставленный mix как стартовую точку, а не плоский 1.0/100%.
#
# Subsequent launches — load из cfg.
#
# Apply order: autoload запускается ВЫШЕ Sfx в project.godot, чтобы sfx.gd мог
# читать AudioSettings.get_volume() в _ready'е без race'а.
#
# Mute floor: при value <= MUTE_THRESHOLD bus отправляется в -80 dB вместо
# linear_to_db(0) = -inf — иначе AudioServer ругается warning'ом.

const SAVE_PATH := "user://vgate_settings.cfg"
const SECTION := "audio"
const BUS_NAMES := ["Master", "Music", "SFX", "Ambient"]
const MUTE_THRESHOLD := 0.001
const MUTE_DB := -80.0
# Throttle save: один write per N сек после последнего изменения. Avoids spam при
# slider drag'е (value_changed firing 60Hz).
const SAVE_DEBOUNCE_SEC := 0.3

# Signal — emit'ится после каждого set_volume. sfx.gd слушает чтобы инвалидировать
# свой duck base_db кеш.
signal volumes_changed(bus_name: String, new_linear: float)

var _volumes: Dictionary = {}  # bus_name -> linear float
var _bus_indices: Dictionary = {}  # bus_name -> int (cached AudioServer idx)
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	for bus_name: String in BUS_NAMES:
		_bus_indices[bus_name] = AudioServer.get_bus_index(bus_name)

	print("[AUDIO] audio_settings.gd | bus_layout state | total=%d | indices: Master=%d Music=%d SFX=%d Ambient=%d" % [
		AudioServer.bus_count,
		_bus_indices.get("Master", -1),
		_bus_indices.get("Music", -1),
		_bus_indices.get("SFX", -1),
		_bus_indices.get("Ambient", -1),
	])

	# Load existing cfg, либо seed defaults из текущего bus_layout.
	var cf := ConfigFile.new()
	var load_err := cf.load(SAVE_PATH)
	for bus_name: String in BUS_NAMES:
		var stored: Variant = null
		if load_err == OK:
			stored = cf.get_value(SECTION, bus_name.to_lower(), null)
		if stored == null:
			# First launch — read designer baseline из AudioServer.
			var idx: int = _bus_indices[bus_name]
			var base_db: float = 0.0
			if idx >= 0:
				base_db = AudioServer.get_bus_volume_db(idx)
			_volumes[bus_name] = clampf(db_to_linear(base_db), 0.0, 1.0)
		else:
			_volumes[bus_name] = clampf(float(stored), 0.0, 1.0)

	_apply_all()
	print("[AUDIO-DIAG] state after _apply_all | volumes=%s | bus_db=[Master=%.1f Music=%.1f SFX=%.1f Ambient=%.1f]" % [
		str(_volumes),
		AudioServer.get_bus_volume_db(_bus_indices.get("Master", -1)) if _bus_indices.get("Master", -1) >= 0 else 0.0,
		AudioServer.get_bus_volume_db(_bus_indices.get("Music", -1)) if _bus_indices.get("Music", -1) >= 0 else 0.0,
		AudioServer.get_bus_volume_db(_bus_indices.get("SFX", -1)) if _bus_indices.get("SFX", -1) >= 0 else 0.0,
		AudioServer.get_bus_volume_db(_bus_indices.get("Ambient", -1)) if _bus_indices.get("Ambient", -1) >= 0 else 0.0,
	])
	# Save back только если файла не было — фиксируем seeded defaults.
	if load_err != OK:
		_save_to_disk()

	# Debounced save timer: 0.3с одиночный shot после последнего set_volume.
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SEC
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(_save_to_disk)
	add_child(_save_timer)


func get_volume(bus_name: String) -> float:
	return _volumes.get(bus_name, 1.0)


func get_volume_db(bus_name: String) -> float:
	# Helper для listener'ов которым нужно немедленное dB-значение (sfx.gd duck base).
	# Возвращает MUTE_DB если bus muted, иначе linear_to_db(value).
	var v: float = get_volume(bus_name)
	if v <= MUTE_THRESHOLD:
		return MUTE_DB
	return linear_to_db(v)


func set_volume(bus_name: String, linear: float) -> void:
	if not _volumes.has(bus_name):
		return
	var clamped := clampf(linear, 0.0, 1.0)
	_volumes[bus_name] = clamped
	_apply_one(bus_name, clamped)
	volumes_changed.emit(bus_name, clamped)
	# Restart debounce timer вместо немедленного save.
	if _save_timer != null:
		_save_timer.start()


func _apply_all() -> void:
	for bus_name: String in BUS_NAMES:
		_apply_one(bus_name, _volumes[bus_name])


func _apply_one(bus_name: String, linear: float) -> void:
	var idx: int = _bus_indices.get(bus_name, -1)
	if idx < 0:
		return
	var muted: bool = linear <= MUTE_THRESHOLD
	var db: float = MUTE_DB if muted else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)
	# Explicit set_bus_mute — -80 dB на volume_db в Godot 4.6 не всегда полностью
	# глушит, особенно если параллельные системы (sfx.gd) тоже manipulate'ят bus mute.
	# Mute-флаг гарантирует абсолютную тишину на bus'е.
	AudioServer.set_bus_mute(idx, muted)
	print("[AUDIO-DIAG] _apply_one | bus=%s idx=%d linear=%.3f db=%.1f | now bus_db=%.1f bus_muted=%s" % [
		bus_name, idx, linear, db,
		AudioServer.get_bus_volume_db(idx),
		AudioServer.is_bus_mute(idx),
	])


func _save_to_disk() -> void:
	var cf := ConfigFile.new()
	# Re-load to preserve other potential sections (controller bindings later).
	cf.load(SAVE_PATH)
	for bus_name: String in BUS_NAMES:
		cf.set_value(SECTION, bus_name.to_lower(), _volumes[bus_name])
	cf.save(SAVE_PATH)
