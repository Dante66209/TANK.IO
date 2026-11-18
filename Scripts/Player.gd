extends CharacterBody2D

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var camera_2d: Camera2D = $Camera2D
@onready var label: Label = $Label
@onready var texture_progress_bar: TextureProgressBar = $TextureProgressBar

@export var color: Color = Color(1.0, 0.47, 0.0, 1.0)
@export var speed: float = 220.0
@export var sprint_speed: float = 380.0

var cell_count: int = 0
var target_zoom: Vector2 = Vector2.ONE
var is_dead: bool = false
var game_over_label: Label = null

func _ready() -> void:
	if sprite_2d.material:
		sprite_2d.material = sprite_2d.material.duplicate()
		sprite_2d.material.set_shader_parameter("cols", color)
	self_modulate = color
	target_zoom = camera_2d.zoom
	_setup_game_over_ui()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var dist: float = global_position.distance_to(mouse_pos)
	
	if dist > 15.0:
		var direction: Vector2 = (mouse_pos - global_position).normalized()
		var current_speed: float = speed
		
		if Input.is_action_pressed("MOUSE_BUTTON") and texture_progress_bar.value > 0.0:
			current_speed = sprint_speed
			texture_progress_bar.value = max(0.0, texture_progress_bar.value - 60.0 * delta)
		else:
			texture_progress_bar.value = min(100.0, texture_progress_bar.value + 25.0 * delta)
		
		velocity = direction * current_speed
	else:
		velocity = Vector2.ZERO
		texture_progress_bar.value = min(100.0, texture_progress_bar.value + 25.0 * delta)

	move_and_slide()

	label.text = str(cell_count)
	camera_2d.zoom = camera_2d.zoom.lerp(target_zoom, 4.0 * delta)

func change_size(amount: float) -> void:
	scale += Vector2(amount, amount)
	var zoom_factor = clampf(1.0 / (1.0 + (scale.x - 1.0) * 0.2), 0.2, 1.0)
	target_zoom = Vector2(zoom_factor, zoom_factor)

func _on_area_2d_body_entered(body: Node2D) -> void:
	if is_dead or body == self or not is_instance_valid(body):
		return
	if not (body is CharacterBody2D):
		return
	
	# If player is noticeably bigger, eat the enemy
	if scale.x > body.scale.x * 1.05:
		var bonus: int = body.cell_count if "cell_count" in body else 10
		cell_count += bonus + 5
		change_size(body.scale.x * 0.3)
		if body.has_method("die"):
			body.die()
		else:
			body.queue_free()
	# If the other body is noticeably bigger, player is eaten
	elif body.scale.x > scale.x * 1.05:
		if body.has_method("change_size"):
			body.change_size(scale.x * 0.3)
		if "cell_count" in body:
			body.cell_count += cell_count + 10
		die()

func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	sprite_2d.visible = false
	collision_shape_2d.set_deferred("disabled", true)
	if texture_progress_bar:
		texture_progress_bar.visible = false
	if label:
		label.visible = false
	if game_over_label:
		game_over_label.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()

func _setup_game_over_ui() -> void:
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	game_over_label = Label.new()
	game_over_label.text = "¡HAS SIDO DEVORADO!\nPresiona [R] para reiniciar"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.anchors_preset = Control.PRESET_FULL_RECT
	game_over_label.add_theme_font_size_override("font_size", 36)
	game_over_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	game_over_label.add_theme_color_override("font_outline_color", Color.BLACK)
	game_over_label.add_theme_constant_override("outline_size", 8)
	game_over_label.visible = false
	canvas_layer.add_child(game_over_label)
