class_name KillChainFlash extends CanvasLayer

# M7 Kill Chain screen flash overlay (docs/feel/M7_polish_spec.md §Эффект 3).
# Listens Events.kill_chain_triggered и tween'ит ColorRect.modulate.a от tier-specific
# peak (0.12/0.20/0.28) → 0 за 80/100/120 ms ease-out.
#
# Цвет per tier:
#   tier 1: cyan (low key, just confirms momentum)
#   tier 2: cyan (escalation, brighter)
#   tier 3: warm/orange-cyan mix (climax — отличается от lower tiers)
#
# Layer 30 (set в .tscn): поверх run_hud (10) и vignette (20), под settings_menu (50)
# и pause_menu. ColorRect mouse_filter=IGNORE чтобы клики проходили насквозь.

const TIER_1_OPACITY := 0.12
const TIER_2_OPACITY := 0.20
const TIER_3_OPACITY := 0.28

const TIER_1_DURATION := 0.080
const TIER_2_DURATION := 0.100
const TIER_3_DURATION := 0.120

# Цвета per tier — cyan-ish для 1/2 (matching feel-spec прецеденты), warm для tier 3.
const TIER_1_COLOR := Color(0.6, 0.95, 1.0, 1.0)   # light cyan
const TIER_2_COLOR := Color(0.6, 0.95, 1.0, 1.0)   # light cyan (brighter via opacity)
const TIER_3_COLOR := Color(1.0, 0.78, 0.5, 1.0)   # warm orange — climax

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
		3:
			peak = TIER_3_OPACITY
			dur = TIER_3_DURATION
			col = TIER_3_COLOR
		_:
			return

	# Cancel предыдущий tween чтобы не складывались две вспышки (особенно tier 3
	# может стрелять каждый kill).
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	rect.color = col
	rect.modulate.a = peak
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(rect, "modulate:a", 0.0, dur)
