# res://Scripts/Core/spawn_manager.gd
class_name SpawnManager extends Node2D

## Spawn coordinator for safe tank respawning and periodic power-up replenishment.
## Caps active arena power-ups at max_powerups (5), spawning every 10-12s on empty markers.

@export var max_powerups: int = 38
@export var spawn_interval_min: float = 0.85
@export var spawn_interval_max: float = 1.45
@export var powerup_scene: PackedScene = preload("res://Scenes/powerup.tscn")

var is_network_puppet: bool = false
var _next_net_id: int = 1
var _spawn_timer: float = 0.6
var _powerup_spawn_positions: Array[Vector2] = []
var _powerup_deck: Array[int] = []

func _is_online_client_context() -> bool:
	var gs := get_node_or_null("/root/GameSettings")
	var nm := get_node_or_null("/root/NetworkManager")
	if gs != null and gs.get("lobby_mode") == "server" and nm != null and nm.get("role") == "client":
		return true
	return false

func _ready() -> void:
	_init_spawn_positions()
	if _is_online_client_context():
		is_network_puppet = true
		return
	for i in range(min(24, max_powerups)):
		spawn_powerup()
	_spawn_timer = randf_range(spawn_interval_min, spawn_interval_max)

func enter_network_puppet_mode() -> void:
	is_network_puppet = true
	if get_tree() != null:
		for pu in get_tree().get_nodes_in_group("powerups"):
			if is_instance_valid(pu):
				pu.queue_free()

func spawn_network_powerup(p_net_id: int, p_type: int, p_pos: Vector2) -> Node2D:
	if powerup_scene == null:
		return null
	var pu_instance: Node2D = powerup_scene.instantiate() as Node2D
	if pu_instance == null:
		return null
	pu_instance.global_position = p_pos
	if "net_id" in pu_instance:
		pu_instance.set("net_id", p_net_id)
	if "is_network_puppet" in pu_instance:
		pu_instance.set("is_network_puppet", true)
	if pu_instance.has_method("setup"):
		pu_instance.setup(p_type)
	elif "powerup_type" in pu_instance:
		pu_instance.set("powerup_type", p_type)
	var container := _get_powerup_container()
	container.add_child(pu_instance)
	return pu_instance

func collect_network_powerup(p_net_id: int, collector: Node2D) -> void:
	if get_tree() == null:
		return
	for pu in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(pu) and "net_id" in pu and int(pu.get("net_id")) == p_net_id:
			if pu.has_method("apply_network_collect_fx"):
				pu.apply_network_collect_fx(collector)
			else:
				pu.queue_free()
			return

func _init_spawn_positions() -> void:
	var map_node := get_tree().get_first_node_in_group("world_map")
	if map_node != null and map_node.has_method("get_powerup_spawn_positions"):
		_powerup_spawn_positions = map_node.get_powerup_spawn_positions()
	else:
		_powerup_spawn_positions = [
			Vector2(0, 0), Vector2(0, -500), Vector2(0, 500),
			Vector2(-450, -350), Vector2(450, -350),
			Vector2(-850, -850), Vector2(850, -850),
			Vector2(-850, 850), Vector2(850, 850),
			Vector2(0, -1100), Vector2(0, 1100),
			Vector2(-1100, 0), Vector2(1100, 0),
			Vector2(-700, 600), Vector2(700, 600),
			Vector2(0, -350)
		]

func _process(delta: float) -> void:
	if is_network_puppet:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = randf_range(spawn_interval_min, spawn_interval_max)
		spawn_powerup()
		if get_active_powerup_count() < int(max_powerups * 0.6):
			spawn_powerup()

func get_active_powerup_count() -> int:
	var count := 0
	for pu in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(pu) and not pu.is_queued_for_deletion():
			count += 1
	return count

## Verifies whether a prospective spawn position is clear of all perimeter and modular cover walls.
func is_position_safe_from_walls(pos: Vector2, min_clearance: float = 35.0) -> bool:
	# 1. Direct physics space query against boundary walls (mask 1) and obstacles (mask 2)
	var world2d := get_world_2d()
	if world2d != null:
		var space_state := world2d.direct_space_state
		if space_state != null:
			var query := PhysicsShapeQueryParameters2D.new()
			var circle := CircleShape2D.new()
			circle.radius = min_clearance
			query.shape = circle
			query.transform = Transform2D(0.0, pos)
			query.collision_mask = 1 | 2
			query.collide_with_bodies = true
			query.collide_with_areas = false
			var hits := space_state.intersect_shape(query, 1)
			if not hits.is_empty():
				return false
				
	# 2. Geometric fallback against map CollisionShape2D bodies
	var map_node := get_tree().get_first_node_in_group("world_map")
	if map_node == null:
		var root := get_tree().root if get_tree() != null else null
		if root != null:
			map_node = root.find_child("WorldMap", true, false)
			if map_node == null:
				map_node = root.find_child("Map", true, false)
				
	if map_node != null:
		for body_name in ["BoundaryWalls", "ModularCovers"]:
			var body = map_node.get_node_or_null(body_name)
			if body is CollisionObject2D:
				for child in body.get_children():
					if child is CollisionShape2D and child.shape != null:
						var shape = child.shape
						var w_pos = child.global_position
						if shape is RectangleShape2D:
							var half_w: float = shape.size.x * 0.5
							var half_h: float = shape.size.y * 0.5
							var dx: float = maxf(0.0, absf(pos.x - w_pos.x) - half_w)
							var dy: float = maxf(0.0, absf(pos.y - w_pos.y) - half_h)
							if (dx * dx + dy * dy) < (min_clearance * min_clearance):
								return false
						elif shape is CircleShape2D:
							if pos.distance_to(w_pos) < (shape.radius + min_clearance):
								return false
		var dest_container = map_node.get_node_or_null("DestructibleCovers")
		if dest_container != null:
			for dw in dest_container.get_children():
				if is_instance_valid(dw) and dw is Node2D and "wall_size" in dw:
					var w_size: Vector2 = dw.get("wall_size")
					var w_pos: Vector2 = (dw as Node2D).global_position
					var dx: float = maxf(0.0, absf(pos.x - w_pos.x) - w_size.x * 0.5)
					var dy: float = maxf(0.0, absf(pos.y - w_pos.y) - w_size.y * 0.5)
					if (dx * dx + dy * dy) < (min_clearance * min_clearance):
						return false
	return true

func _get_random_powerup_type() -> int:
	if _powerup_deck.is_empty():
		_powerup_deck = [0, 1, 2, 3, 4, 5] # Health, Shield, Rapid Fire, Ricochet, Monster Energy, Cluster Mines
		_powerup_deck.shuffle()
	return _powerup_deck.pop_back()

func _get_random_safe_arena_position() -> Vector2:
	var active_pus := get_tree().get_nodes_in_group("powerups")
	var bound: float = 2950.0
	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("is_sudden_death") == true:
		var sz_val = mm.get("safe_zone_radius")
		if sz_val != null:
			bound = minf(bound, maxf(300.0, float(sz_val) * 0.85))
	for attempt in range(40):
		var candidate := Vector2(
			randf_range(-bound, bound),
			randf_range(-bound, bound)
		)
		if is_position_safe_from_walls(candidate, 45.0):
			var occupied := false
			for pu in active_pus:
				if is_instance_valid(pu) and not pu.is_queued_for_deletion() and pu is Node2D:
					if (pu as Node2D).global_position.distance_to(candidate) < 100.0:
						occupied = true
						break
			if not occupied:
				return candidate
	return Vector2.ZERO

func spawn_powerup() -> Node2D:
	if get_active_powerup_count() >= max_powerups:
		return null
		
	if _powerup_spawn_positions.is_empty():
		_init_spawn_positions()
		if _powerup_spawn_positions.is_empty():
			return null
			
	# Find empty spawn markers (no power-up within 80px and completely clear of walls)
	var active_pus := get_tree().get_nodes_in_group("powerups")
	var available_positions: Array[Vector2] = []
	
	for pos in _powerup_spawn_positions:
		if not is_position_safe_from_walls(pos, 35.0):
			continue
		var occupied := false
		for pu in active_pus:
			if is_instance_valid(pu) and not pu.is_queued_for_deletion() and pu is Node2D:
				if (pu as Node2D).global_position.distance_to(pos) < 80.0:
					occupied = true
					break
		if not occupied:
			available_positions.append(pos)
			
	var chosen_pos: Vector2 = Vector2.ZERO
	# 50% chance to spawn on a safe tactical marker, 50% chance dynamically across the arena
	if not available_positions.is_empty() and randf() < 0.5:
		chosen_pos = available_positions[randi() % available_positions.size()]
	else:
		var rnd_pos := _get_random_safe_arena_position()
		if rnd_pos != Vector2.ZERO:
			chosen_pos = rnd_pos
		elif not available_positions.is_empty():
			chosen_pos = available_positions[randi() % available_positions.size()]
		else:
			return null
		
	var chosen_type: int = _get_random_powerup_type() # Balanced shuffled random deck
	
	if powerup_scene == null:
		return null
		
	var pu_instance: Node2D = powerup_scene.instantiate() as Node2D
	if pu_instance == null:
		return null
		
	pu_instance.global_position = chosen_pos
	if "net_id" in pu_instance:
		pu_instance.set("net_id", _next_net_id)
		_next_net_id += 1
	if pu_instance.has_method("setup"):
		pu_instance.setup(chosen_type)
	elif "powerup_type" in pu_instance:
		pu_instance.powerup_type = chosen_type
		
	var container := _get_powerup_container()
	container.add_child(pu_instance)
	
	if GameEvents != null:
		GameEvents.powerup_spawned.emit(pu_instance, chosen_type, chosen_pos)
		
	return pu_instance

func _get_powerup_container() -> Node:
	var pu_nodes := get_tree().get_nodes_in_group("powerups_container")
	if not pu_nodes.is_empty():
		return pu_nodes[0]
	var entities := get_tree().get_first_node_in_group("entities")
	if entities != null and entities.has_node("PowerUps"):
		return entities.get_node("PowerUps")
	return self

func get_safe_spawn_point(active_tanks: Array[Node] = []) -> Vector2:
	return select_safe_spawn_point(active_tanks)

func get_spawn_point() -> Vector2:
	return select_safe_spawn_point()

func select_safe_spawn_point(active_tanks: Array[Node] = []) -> Vector2:
	var map_node := get_tree().get_first_node_in_group("world_map")
	var spawn_points: Array[Vector2] = []
	if map_node != null and map_node.has_method("get_spawn_positions"):
		spawn_points = map_node.get_spawn_positions()
	else:
		spawn_points = [
			Vector2(-950, -950), Vector2(950, -950),
			Vector2(-950, 950), Vector2(950, 950),
			Vector2(0, -800), Vector2(0, 800),
			Vector2(-800, 0), Vector2(800, 0)
		]
		
	if spawn_points.is_empty():
		return Vector2.ZERO
		
	if active_tanks.is_empty():
		active_tanks = get_tree().get_nodes_in_group("tanks")
		
	var best_point: Vector2 = spawn_points[0]
	var highest_min_dist: float = -1.0
	
	for pt in spawn_points:
		var min_dist_to_threat: float = INF
		for tank in active_tanks:
			if is_instance_valid(tank) and tank is Node2D:
				var is_dead_val: bool = tank.get("is_dead") if "is_dead" in tank else false
				if not is_dead_val:
					var dist: float = pt.distance_to((tank as Node2D).global_position)
					if dist < min_dist_to_threat:
						min_dist_to_threat = dist
		if min_dist_to_threat > highest_min_dist:
			highest_min_dist = min_dist_to_threat
			best_point = pt
			
	return best_point
