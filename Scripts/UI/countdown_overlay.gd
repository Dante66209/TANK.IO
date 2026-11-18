# res://Scripts/UI/countdown_overlay.gd
class_name CountdownOverlay extends CanvasLayer

## Pre-match Respawn Gray Screen, Illustrated "Cómo Jugar" Diagram & 15s Countdown Overlay.
## Keeps combatants immobilized during countdown, renders translucent grayscale-styled
## controls & movement guides, and dissolves cleanly once "¡A JUGAR!" triggers.

signal countdown_started()
signal countdown_step(step_text: String)
signal countdown_finished()

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const GrayscaleShader = preload("res://Shaders/grayscale_overlay.gdshader")

@export var countdown_seconds: int = 15
@export var step_duration: float = 1.0
@export var go_hold_duration: float = 0.65

@onready var root: Control = $Root
@onready var gray_rect: ColorRect = $Root/GrayScreen
@onready var controls_card: PanelContainer = $Root/CenterPanel/ControlsCard
@onready var status_label: Label = $Root/CenterPanel/ControlsCard/VBox/TopHeader/TitleVBox/StatusLabel
@onready var countdown_label: Label = $Root/CenterPanel/ControlsCard/VBox/TopHeader/TimerBox/CountdownLabel
@onready var subtitle_label: Label = $Root/CenterPanel/ControlsCard/VBox/TopHeader/TimerBox/SubtitleLabel
@onready var countdown_bar: ProgressBar = $Root/CenterPanel/ControlsCard/VBox/CountdownBar
@onready var controls_diagram: Control = $Root/CenterPanel/ControlsCard/VBox/ControlsDiagram

var is_counting_down: bool = false
var current_step_text: String = ""

var _shader_mat: ShaderMaterial = null
var _sequence_tween: Tween = null
var _fade_tween: Tween = null

func _ready() -> void:
	layer = 102
	visible = false
	_setup_gray_shader()

func _exit_tree() -> void:
	_kill_tweens()

func _kill_tweens() -> void:
	if _sequence_tween != null and _sequence_tween.is_valid():
		_sequence_tween.kill()
	_sequence_tween = null
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

func _setup_gray_shader() -> void:
	if gray_rect == null:
		return
	gray_rect.color = Color(0.20, 0.22, 0.25, 0.68)
	if DisplayServer.get_name() != "headless" and GrayscaleShader != null:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = GrayscaleShader
		_shader_mat.set_shader_parameter("intensity", 1.0)
		_shader_mat.set_shader_parameter("dim_amount", 0.22)
		gray_rect.material = _shader_mat
	else:
		gray_rect.material = null

func start_countdown(custom_step_duration: float = -1.0, custom_seconds: int = -1) -> void:
	_kill_tweens()
	if custom_step_duration > 0.0:
		step_duration = custom_step_duration
		go_hold_duration = minf(go_hold_duration, custom_step_duration)
	var total_steps: int = custom_seconds if custom_seconds > 0 else countdown_seconds
	total_steps = maxi(1, total_steps)

	is_counting_down = true
	visible = true
	if root != null:
		root.modulate = Color(1, 1, 1, 1)
		root.mouse_filter = Control.MOUSE_FILTER_STOP
	if gray_rect != null:
		gray_rect.modulate = Color(1, 1, 1, 1)
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("intensity", 1.0)
	if controls_card != null:
		controls_card.visible = true
		controls_card.modulate = Color(1, 1, 1, 1)
	if controls_diagram != null:
		controls_diagram.queue_redraw()
	if countdown_bar != null:
		countdown_bar.max_value = float(total_steps)
		countdown_bar.value = float(total_steps)
	if status_label != null:
		status_label.text = "DESPLIEGUE EN ARENA • JUGADORES INMÓVILES"
	if subtitle_label != null:
		subtitle_label.text = "INICIANDO EN..."

	countdown_started.emit()
	_show_step(total_steps)

	_sequence_tween = create_tween()
	for remaining in range(total_steps - 1, 0, -1):
		_sequence_tween.tween_interval(step_duration)
		_sequence_tween.tween_callback(_show_step.bind(remaining))
	_sequence_tween.tween_interval(step_duration)
	_sequence_tween.tween_callback(_finish_to_go)

func _get_step_color(step_num: int) -> Color:
	if step_num <= 1:
		return Color(1.0, 0.36, 0.28, 1.0)
	if step_num <= 3:
		return Color(1.0, 0.72, 0.25, 1.0)
	if step_num <= 5:
		return Color(1.0, 0.92, 0.35, 1.0)
	return Color(0.95, 0.97, 1.0, 1.0)

func _show_step(step_num: int) -> void:
	var text_val: String = str(step_num)
	current_step_text = text_val
	if countdown_bar != null:
		countdown_bar.value = float(step_num)
	if countdown_label != null:
		countdown_label.text = text_val
		countdown_label.add_theme_color_override("font_color", _get_step_color(step_num))
		var pop_scale := 1.38 if step_num <= 3 else 1.15
		countdown_label.scale = Vector2(pop_scale, pop_scale)
		var pop := create_tween()
		pop.tween_property(countdown_label, "scale", Vector2.ONE, minf(0.24, step_duration * 0.8)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if SoundManagerScript != null and step_num > 0 and step_num <= 3:
		SoundManagerScript.play_countdown_tick(step_num)
	countdown_step.emit(text_val)

func _finish_to_go() -> void:
	current_step_text = "¡A JUGAR!"
	is_counting_down = false
	if countdown_bar != null:
		countdown_bar.value = 0.0
	if status_label != null:
		status_label.text = "¡COMBATE ACTIVO!"
	if subtitle_label != null:
		subtitle_label.text = "¡ADELANTE, PILOTO!"
	if countdown_label != null:
		countdown_label.text = "¡A JUGAR!"
		countdown_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.55, 1.0))
		countdown_label.scale = Vector2(1.26, 1.26)
		var pop := create_tween()
		pop.tween_property(countdown_label, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if SoundManagerScript != null:
		SoundManagerScript.play_countdown_go()
	if root != null:
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	countdown_step.emit("¡A JUGAR!")
	countdown_finished.emit()

	_fade_tween = create_tween()
	_fade_tween.tween_interval(go_hold_duration)
	_fade_tween.set_parallel(true)
	if root != null:
		_fade_tween.tween_property(root, "modulate:a", 0.0, 0.42)
	if _shader_mat != null:
		_fade_tween.tween_method(func(val: float) -> void:
			if _shader_mat != null:
				_shader_mat.set_shader_parameter("intensity", val)
		, 1.0, 0.0, 0.42)
	_fade_tween.chain().tween_callback(func() -> void:
		visible = false
	)

func skip_countdown() -> void:
	_kill_tweens()
	is_counting_down = false
	current_step_text = "¡A JUGAR!"
	visible = false
	if root != null:
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_finished.emit()
