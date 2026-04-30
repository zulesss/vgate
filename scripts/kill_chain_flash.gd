class_name KillChainFlash extends CanvasLayer

# M7 Kill Chain screen flash overlay (docs/feel/M7_polish_spec.md §Эффект 3,
# revised 2026-04-30). Listens Events.kill_chain_triggered (tier 1/2 only) и
# tween'ит ColorRect.modulate.a от peak (0.12/0.20) → 0 за 80/100 ms ease-out.
#
# Tier 7+ (3) больше НЕ эмитит kill_chain_triggered — переведён на sustained
# semantics, без per-kill flash'ей (warm/orange flash был визуально noisy).
#
# Цвет per tier:
#   tier 1: cyan (low key, just confirms momentum)
#   tier 2: cyan (escalation, brighter)
#
# Layer 30 (set в .tscn): поверх run_hud (10) и vignette (20), под settings_menu (50)
# и pause_menu. ColorRect mouse_filter=IGNORE чтобы клики проходили насквозь.

const TIER_1_OPACITY := 0.12
const TIER_2_OPACITY := 0.20

const TIER_1_DURATION := 0.080
const TIER_2_DURATION := 0.100

# Цвета per tier — cyan-ish для matching feel-spec прецедентов.
const TIER_1_COLOR := Color(0.6, 0.95, 1.0, 1.0)   # light cyan
const TIER_2_COLOR := Color(0.6, 0.95, 1.0, 1.0)   # light cyan (brighter via opacity)

@onready var rect: ColorRect = $Rect

var _active_tween: Tween


func _ready() -> void:
	# Default PAUSABLE — kill_chain_triggered на pause не emit'ится (KillChain Timer
	# pausable), tween не нужен на паузе.
	rect.modulate.a = 0.0
	Events.kill_chain_triggered.connect(_on_chain_triggered)


func _on_chain_triggered(tier: int, _hit_pos: Vector3) -> void:
	var peak: float
	var dur: float
	var col: Color
	match tier:
		1:
			peak = TIER_1_OPACITY
			dur = TIER_1_DURATION
			col = TIER_1_COLOR
		2:
			peak = TIER_2_OPACITY
			dur = TIER_2_DURATION
			col = TIER_2_COLOR
		_:
			return

	# Cancel предыдущий tween чтобы не складывались две вспышки.
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	rect.color = col
	rect.modulate.a = peak
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(rect, "modulate:a", 0.0, dur)
