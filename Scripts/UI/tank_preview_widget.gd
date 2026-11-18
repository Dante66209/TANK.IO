# res://Scripts/UI/tank_preview_widget.gd
class_name TankPreviewWidget extends Control

## Live miniature Tank Preview with Monster "Yaris Bouncing" animation (visual only, no music).
## Displays the selected tank color and name in real time on the Main Menu.

const MONSTER_BOUNCE_BPM: float = 136.0
const MONSTER_BOUNCE_BPS: float = MONSTER_BOUNCE_BPM / 60.0
const MONSTER_BOUNCE_HEIGHT: float = 18.0

var tank_name: String = "Player":
	set(val):
		tank_name = val.strip_edges() if not val.strip_edges().is_empty() else "Player"
		if _name_label != null:
			_name_label.text = tank_name
		queue_redraw()

var tank_color: Color = Color(0.20, 0.45, 0.75, 1.0):
	set(val):
		tank_color = Color(val.r, val.g, val.b, 1.0)
		queue_redraw()

var bounce_enabled: bool = true
var current_hop_offset_y: float = 0.0
var current_squash_scale: Vector2 = Vector2.ONE

var _bounce_time: float = 0.0
var _rock_angle: float = 0.0
var _name_label: Label = null

func _ready() -> void:
	clip_contents = true
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(340, 175)
	_ensure_name_label()
	queue_redraw()

func _ensure_name_label() -> void:
	_name_label = get_node_or_null("PreviewNameLabel") as Label
	if _name_label == null:
		_name_label = Label.new()
		_name_label.name = "PreviewNameLabel"
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88, 1.0))
		_name_label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 1.0))
		_name_label.add_theme_constant_override("outline_size", 4)
		_name_label.add_theme_font_size_override("font_size", 14)
		add_child(_name_label)
	_name_label.text = tank_name

func _process(delta: float) -> void:
	step_animation(delta)

func step_animation(delta: float) -> void:
	if not bounce_enabled:
		current_hop_offset_y = 0.0
		current_squash_scale = Vector2.ONE
		_rock_angle = 0.0
	else:
		_bounce_time += delta
		var beat_pos: float = _bounce_time * MONSTER_BOUNCE_BPS
		var phase: float = fmod(beat_pos, 1.0)
		var hop_y: float = 0.0
		var squash_x: float = 1.0
		var squash_y: float = 1.0

		if phase < 0.17:
			var c_t: float = phase / 0.17
			var comp: float = sin(c_t * PI)
			hop_y = -2.5 * comp
			squash_x = 1.0 + 0.25 * comp
			squash_y = 1.0 - 0.23 * comp
		else:
			var air_t: float = (phase - 0.17) / 0.83
			var arc: float = sin(air_t * PI)
			hop_y = arc * MONSTER_BOUNCE_HEIGHT
			var stretch: float = arc * 0.16
			squash_x = 1.0 - stretch * 0.85
			squash_y = 1.0 + stretch * 1.12

		_rock_angle = sin(beat_pos * PI) * deg_to_rad(4.5)
		current_hop_offset_y = -hop_y
		current_squash_scale = Vector2(squash_x, squash_y)

	_position_name_label()
	queue_redraw()

func _position_name_label() -> void:
	if _name_label == null:
		return
	var center := size * 0.5
	var hop_lift: float = maxf(0.0, -current_hop_offset_y) * 0.55
	_name_label.size = Vector2(maxf(160.0, size.x - 16.0), 24.0)
	_name_label.position = Vector2(
		(size.x - _name_label.size.x) * 0.5,
		center.y + 12.0 - 62.0 - hop_lift
	)

func _draw() -> void:
	var w := maxf(120.0, size.x)
	var h := maxf(100.0, size.y)
	var bg_rect := Rect2(Vector2.ZERO, Vector2(w, h))

	# Tactical mini-arena grid background
	draw_rect(bg_rect, Color(0.07, 0.09, 0.12, 1.0), true)
	var grid_col := Color(0.13, 0.17, 0.22, 0.75)
	for gx in range(28, int(w), 32):
		draw_line(Vector2(gx, 0.0), Vector2(gx, h), grid_col, 1.0)
	for gy in range(24, int(h), 32):
		draw_line(Vector2(0.0, gy), Vector2(w, gy), grid_col, 1.0)
	draw_rect(bg_rect, Color(0.24, 0.48, 0.68, 0.75), false, 1.5)

	var base_pos := Vector2(w * 0.5, h * 0.5 + 14.0)
	var preview_scale: float = 1.15

	# Dynamic ground shadow & impact beat pulse ring
	var hop_ratio: float = clampf(-current_hop_offset_y / MONSTER_BOUNCE_HEIGHT, 0.0, 1.0)
	var shadow_sx: float = lerpf(1.16, 0.68, hop_ratio) * preview_scale
	var shadow_sy: float = lerpf(0.62, 0.38, hop_ratio) * preview_scale
	var shadow_alpha: float = lerpf(0.48, 0.20, hop_ratio)

	draw_set_transform(base_pos + Vector2(0.0, 12.0 * preview_scale), 0.0, Vector2(shadow_sx, shadow_sy))
	draw_circle(Vector2.ZERO, 25.0, Color(0.02, 0.03, 0.05, shadow_alpha))

	var phase: float = fmod(_bounce_time * MONSTER_BOUNCE_BPS, 1.0)
	if bounce_enabled and phase < 0.26:
		var ring_t: float = phase / 0.26
		var ring_r: float = lerpf(22.0, 38.0, ring_t)
		var ring_a: float = (1.0 - ring_t) * 0.50
		draw_set_transform(base_pos + Vector2(0.0, 8.0), 0.0, Vector2(preview_scale, preview_scale * 0.65))
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 28, Color(tank_color.r, tank_color.g, tank_color.b, ring_a).lightened(0.35), 2.5)

	# Bouncy Chassis + Turret transform (same squash & rock feel as Monster Yaris bounce)
	var chassis_angle: float = deg_to_rad(-16.0) + _rock_angle
	var turret_angle: float = deg_to_rad(-16.0) + sin(_bounce_time * 1.4) * 0.22 + _rock_angle * 0.5
	var bounce_pos := base_pos + Vector2(0.0, current_hop_offset_y)
	var bounce_scale := current_squash_scale * preview_scale

	draw_set_transform(bounce_pos, 0.0, bounce_scale)
	# Draw chassis rotated
	var c_rot := Transform2D(chassis_angle, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D(0.0, bounce_pos) * Transform2D(Vector2(bounce_scale.x, 0.0), Vector2(0.0, bounce_scale.y), Vector2.ZERO) * c_rot)

	var track_col := Color(0.12, 0.14, 0.16, 1.0)
	var outline_col := Color(0.08, 0.10, 0.12, 1.0)
	var tread_col := Color(0.20, 0.22, 0.25, 0.85)

	# Left & right tracks
	draw_rect(Rect2(-24.0, -22.0, 48.0, 10.0), track_col, true)
	draw_rect(Rect2(-24.0, -22.0, 48.0, 10.0), outline_col, false, 1.5)
	draw_rect(Rect2(-24.0, 12.0, 48.0, 10.0), track_col, true)
	draw_rect(Rect2(-24.0, 12.0, 48.0, 10.0), outline_col, false, 1.5)
	for tx in range(-20, 24, 8):
		draw_line(Vector2(tx, -22.0), Vector2(tx, -12.0), tread_col, 1.0)
		draw_line(Vector2(tx, 12.0), Vector2(tx, 22.0), tread_col, 1.0)

	# Hull in selected tank_color
	var hull_rect := Rect2(-20.0, -15.0, 40.0, 30.0)
	draw_rect(hull_rect, tank_color, true)
	draw_rect(hull_rect, outline_col, false, 2.0)
	draw_polyline(PackedVector2Array([Vector2(14.0, -10.0), Vector2(20.0, 0.0), Vector2(14.0, 10.0)]), Color(1.0, 1.0, 1.0, 0.45), 2.0)

	# Turret rotated independently
	var t_rot := Transform2D(turret_angle, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D(0.0, bounce_pos) * Transform2D(Vector2(bounce_scale.x, 0.0), Vector2(0.0, bounce_scale.y), Vector2.ZERO) * t_rot)

	var barrel_col := Color(0.20, 0.22, 0.25, 1.0)
	var turret_col := tank_color.darkened(0.18)
	draw_rect(Rect2(0.0, -4.0, 38.0, 8.0), barrel_col, true)
	draw_rect(Rect2(0.0, -4.0, 38.0, 8.0), outline_col, false, 1.5)
	draw_rect(Rect2(32.0, -6.0, 6.0, 12.0), Color(0.12, 0.14, 0.16, 1.0), true)
	draw_rect(Rect2(32.0, -6.0, 6.0, 12.0), outline_col, false, 1.0)

	draw_circle(Vector2.ZERO, 15.0, turret_col)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, outline_col, 2.0)
	draw_circle(Vector2(-3.0, 0.0), 6.0, turret_col.darkened(0.25))
	draw_arc(Vector2(-3.0, 0.0), 6.0, 0.0, TAU, 16, outline_col, 1.0)

	draw_set_transform_matrix(Transform2D.IDENTITY)
