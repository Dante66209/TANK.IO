extends CharacterBody2D

@onready var detection_area: Area2D = $DetectionArea
@onready var label: Label = $Label
@onready var sprite_2d: Sprite2D = $Sprite2D

@export var color: Color
@export var speed: float = 160.0

var cell_count: int = 0
var wander_direction: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0

func _ready() -> void:
	# Randomize color if default or not assigned
	if color == Color(0, 0, 0, 0) or color == Color(1, 0, 0, 1):
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		color = Color.from_hsv(rng.randf(), 0.75, 0.95)
	
	if sprite_2d.material:
		sprite_2d.material = sprite_2d.material.duplicate()
		sprite_2d.material.set_shader_parameter("cols", color)
	sprite_2d.modulate = color
	
	_pick_new_wander_direction()

func _physics_process(delta: float) -> void:
	label.text = str(cell_count)
	
	var move_dir: Vector2 = _decide_direction(delta)
	velocity = move_dir * speed
	move_and_slide()

func _decide_direction(delta: float) -> Vector2:
	var threats: Array[Node2D] = []
	var preys: Array[Node2D] = []
	
	for body in detection_area.get_overlapping_bodies():
		if body == self or not is_instance_valid(body):
			continue
		if body is CharacterBody2D:
			if body.scale.x > scale.x * 1.05:
				threats.append(body)
			elif body.scale.x < scale.x * 0.95:
				preys.append(body)
	
	# Priority 1: FLEE from closest threat
	if not threats.is_empty():
		var threat = _get_closest_node(threats)
		if is_instance_valid(threat):
			return (global_position - threat.global_position).normalized()
	
	# Priority 2: HUNT closest prey
	if not preys.is_empty():
		var prey = _get_closest_node(preys)
		if is_instance_valid(prey):
			return (prey.global_position - global_position).normalized()
	
	# Priority 3: EAT closest food cell
	var areas = detection_area.get_overlapping_areas()
	var food_cells: Array[Node2D] = []
	for a in areas:
		if is_instance_valid(a) and a.is_in_group("food"):
			food_cells.append(a)
	
	if not food_cells.is_empty():
		var food = _get_closest_node(food_cells)
		if is_instance_valid(food):
			return (food.global_position - global_position).normalized()
	
	# Priority 4: WANDER smoothly
	wander_timer -= delta
	if wander_timer <= 0.0:
		_pick_new_wander_direction()
	return wander_direction

func _get_closest_node(nodes: Array[Node2D]) -> Node2D:
	var closest: Node2D = null
	var min_dist: float = INF
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var dist: float = global_position.distance_squared_to(n.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = n
	return closest

func _pick_new_wander_direction() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	wander_direction = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	wander_timer = rng.randf_range(1.5, 3.5)

func change_size(size: float) -> void:
	scale += Vector2(size, size)

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body == self or not is_instance_valid(body):
		return
	if not (body is CharacterBody2D):
		return
	
	# If we are noticeably larger than the other body, eat it
	if scale.x > body.scale.x * 1.05:
		var bonus: int = body.cell_count if "cell_count" in body else 10
		cell_count += bonus + 5
		change_size(body.scale.x * 0.3)
		if body.has_method("die"):
			body.die()
		else:
			body.queue_free()
	# If the other body is noticeably larger than us, we get eaten
	elif body.scale.x > scale.x * 1.05:
		if body.has_method("change_size"):
			body.change_size(scale.x * 0.3)
		if "cell_count" in body:
			body.cell_count += cell_count + 10
		die()

func die() -> void:
	var spawner = get_tree().get_first_node_in_group("spawner")
	if spawner and spawner.has_method("on_enemy_died"):
		spawner.on_enemy_died(global_position)
	queue_free()
