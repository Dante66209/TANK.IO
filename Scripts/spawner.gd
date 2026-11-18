extends Node

@export var cell: PackedScene
@export var enemy_scene: PackedScene
@export var count: int = 150
@export var max_enemies: int = 4
@export var arena_size: Vector2 = Vector2(2500, 2500)

var check_timer: float = 0.0

func _ready() -> void:
	add_to_group("spawner")
	spawn_initial_cells()

func _process(delta: float) -> void:
	check_timer += delta
	if check_timer >= 1.0:
		check_timer = 0.0
		_maintain_cells()
		_maintain_enemies()

func spawn_initial_cells() -> void:
	if not cell:
		return
	for i in count:
		_spawn_single_cell()

func _spawn_single_cell() -> void:
	var c = cell.instantiate()
	var size = randf_range(0.4, 0.7)
	c.scale = Vector2(size, size)
	c.position = Vector2(randf_range(50, arena_size.x - 50), randf_range(50, arena_size.y - 50))
	add_child(c)

func _maintain_cells() -> void:
	var current_cells = get_child_count()
	var needed = count - current_cells
	if needed > 0:
		for i in min(needed, 10):
			_spawn_single_cell()

func _maintain_enemies() -> void:
	if not enemy_scene:
		return
	var enemies = get_tree().get_nodes_in_group("enemies")
	var valid_count: int = 0
	for e in enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			valid_count += 1
			
	if valid_count < max_enemies:
		var e = enemy_scene.instantiate()
		e.position = Vector2(randf_range(200, arena_size.x - 200), randf_range(200, arena_size.y - 200))
		get_parent().call_deferred("add_child", e)

func on_enemy_died(pos: Vector2) -> void:
	if not cell:
		return
	for i in 6:
		var c = cell.instantiate()
		c.scale = Vector2(0.5, 0.5)
		c.position = pos + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		call_deferred("add_child", c)
