# res://Scripts/World/destructible_wall.gd
class_name DestructibleWall extends StaticBody2D

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

## Partially Destructible Gotcha Tactical Barricade (Layer 2: Walls).
## Absorbs ~5 cannon shots (125 HP), displays progressive fracture cracks as HP drops,
## shatters into splinters opening new sightlines, and respawns after 20s.

@export var wall_size: Vector2 = Vector2(180.0, 44.0)
@export var max_health: float = 125.0
@export var respawn_delay: float = 20.0

signal network_wall_damaged(wall: Node2D, new_hp: float)
signal network_wall_shattered(wall: Node2D)
signal network_wall_restored(wall: Node2D)

var net_slot: int = -1
var is_network_puppet: bool = false
var current_health: float = 125.0
var current_hp: float:
	get: return current_health
	set(v): current_health = v
var is_destroyed: bool = false
var _respawn_timer: float = 0.0

var _col_shape: CollisionShape2D = null
var _flash_timer: float = 0.0

func _ready() -> void:
	add_to_group("destructible_walls")
	add_to_group("destructibles")
	current_health = max_health
	collision_layer = 2
	collision_mask = 0
	if GameEvents != null and not GameEvents.match_started.is_connected(_on_match_started):
		GameEvents.match_started.connect(_on_match_started)
	
	_ensure_collider()
	queue_redraw()

func _ensure_collider() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			_col_shape = child
			break
	if _col_shape == null:
		_col_shape = CollisionShape2D.new()
		_col_shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = wall_size
		_col_shape.shape = rect
		add_child(_col_shape)
	elif _col_shape.shape is RectangleShape2D:
		(_col_shape.shape as RectangleShape2D).size = wall_size

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		queue_redraw()
	if not is_network_puppet and is_destroyed and respawn_delay > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			if _is_clear_of_tanks(38.0):
				restore()
				_spawn_restore_fx()
			else:
				_respawn_timer = 0.5

func _on_match_started(_duration: float) -> void:
	if is_destroyed or current_health < max_health:
		restore()

func _is_clear_of_tanks(min_clearance: float) -> bool:
	if get_tree() == null:
		return true
	var half := wall_size * 0.5
	for t in get_tree().get_nodes_in_group("tanks"):
		if is_instance_valid(t) and t is Node2D and t.get("is_dead") != true:
			var t_pos: Vector2 = (t as Node2D).global_position
			var dx: float = maxf(0.0, absf(t_pos.x - global_position.x) - half.x)
			var dy: float = maxf(0.0, absf(t_pos.y - global_position.y) - half.y)
			if (dx * dx + dy * dy) < (min_clearance * min_clearance):
				return false
	return true

func take_damage(amount: float, _attacker: Node2D = null, _is_barrel: bool = false) -> void:
	if is_network_puppet or is_destroyed:
		return
		
	current_health = maxf(0.0, current_health - amount)
	_flash_timer = 0.08
	
	if current_health <= 0.0:
		shatter()
	else:
		if SoundManagerScript != null:
			SoundManagerScript.play_hit(global_position)
		_spawn_splinter_fx(8, 90.0)
		queue_redraw()
		network_wall_damaged.emit(self, current_health)

func apply_network_damage_fx(new_hp: float) -> void:
	current_health = new_hp
	_flash_timer = 0.08
	if SoundManagerScript != null:
		SoundManagerScript.play_hit(global_position)
	_spawn_splinter_fx(8, 90.0)
	queue_redraw()

func shatter() -> void:
	if is_network_puppet or is_destroyed:
		return
	apply_network_shatter_fx()
	network_wall_shattered.emit(self)

func apply_network_shatter_fx() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	_respawn_timer = respawn_delay
	collision_layer = 0
	if _col_shape != null:
		_col_shape.set_deferred("disabled", true)
		
	if SoundManagerScript != null:
		SoundManagerScript.play_wood_break(global_position)
	_spawn_splinter_fx(26, 190.0)
	visible = false

func restore() -> void:
	apply_network_restore_fx()
	network_wall_restored.emit(self)

func apply_network_restore_fx() -> void:
	is_destroyed = false
	_respawn_timer = 0.0
	current_health = max_health
	collision_layer = 2
	if _col_shape != null:
		_col_shape.set_deferred("disabled", false)
	visible = true
	queue_redraw()

func _spawn_restore_fx() -> void:
	var fx_parent: Node = get_parent()
	if fx_parent != null and fx_parent.name == "DestructibleCovers" and fx_parent.get_parent() != null:
		fx_parent = fx_parent.get_parent()
	if fx_parent == null:
		return
	var sparks := CPUParticles2D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.lifetime = 0.35
	sparks.amount = 16
	sparks.spread = 180.0
	sparks.initial_velocity_min = 30.0
	sparks.initial_velocity_max = 105.0
	sparks.gravity = Vector2.ZERO
	sparks.scale_amount_min = 2.5
	sparks.scale_amount_max = 5.0
	sparks.color = Color(0.95, 0.80, 0.32, 0.9)
	sparks.global_position = global_position
	fx_parent.add_child(sparks)
	if get_tree() != null:
		var timer := get_tree().create_timer(0.45)
		timer.timeout.connect(sparks.queue_free)

func _spawn_splinter_fx(count: int, max_vel: float) -> void:
	var fx_parent: Node = get_parent()
	if fx_parent != null and fx_parent.name == "DestructibleCovers" and fx_parent.get_parent() != null:
		fx_parent = fx_parent.get_parent()
	if fx_parent == null:
		return
	var chips := CPUParticles2D.new()
	chips.emitting = true
	chips.one_shot = true
	chips.explosiveness = 0.95
	chips.lifetime = 0.42
	chips.amount = count
	chips.spread = 180.0
	chips.initial_velocity_min = 45.0
	chips.initial_velocity_max = max_vel
	chips.gravity = Vector2.ZERO
	chips.scale_amount_min = 3.0
	chips.scale_amount_max = 6.5
	chips.color = Color(0.82, 0.62, 0.25, 1.0)
	chips.global_position = global_position
	fx_parent.add_child(chips)
	if get_tree() != null:
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(chips.queue_free)

func _draw() -> void:
	if is_destroyed:
		return
		
	var half := wall_size * 0.5
	var rect := Rect2(-half, wall_size)
	var hp_ratio := clampf(current_health / maxf(1.0, max_health), 0.0, 1.0)
	
	# Base Gotcha tactical barricade color (olive-ochre composite, distinct from steel walls)
	var base_col := Color(0.56, 0.46, 0.22, 1.0)
	if hp_ratio < 0.4:
		base_col = Color(0.50, 0.34, 0.16, 1.0)
	elif hp_ratio < 0.75:
		base_col = Color(0.53, 0.41, 0.19, 1.0)
		
	if _flash_timer > 0.0:
		base_col = Color(0.95, 0.88, 0.65, 1.0)
		
	draw_rect(rect, base_col, true)
	
	# Inner paneling slats
	var inner_rect := Rect2(-half + Vector2(4, 4), wall_size - Vector2(8, 8))
	draw_rect(inner_rect, base_col.lightened(0.1), false, 2.0)
	
	# End-cap hazard stripes (Gotcha bunker style)
	var cap_w := minf(16.0, wall_size.x * 0.18)
	var cap_h := minf(16.0, wall_size.y * 0.18)
	if wall_size.x >= wall_size.y:
		draw_rect(Rect2(-half, Vector2(cap_w, wall_size.y)), Color(0.85, 0.68, 0.15, 0.85), true)
		draw_rect(Rect2(Vector2(half.x - cap_w, -half.y), Vector2(cap_w, wall_size.y)), Color(0.85, 0.68, 0.15, 0.85), true)
	else:
		draw_rect(Rect2(-half, Vector2(wall_size.x, cap_h)), Color(0.85, 0.68, 0.15, 0.85), true)
		draw_rect(Rect2(Vector2(-half.x, half.y - cap_h), Vector2(wall_size.x, cap_h)), Color(0.85, 0.68, 0.15, 0.85), true)
		
	# Outer dark metallic frame
	draw_rect(rect, Color(0.22, 0.18, 0.10, 1.0), false, 3.0)
	
	# Progressive fracture cracks
	var crack_col := Color(0.10, 0.08, 0.05, 0.92)
	if hp_ratio < 0.78:
		draw_line(Vector2(-half.x * 0.35, -half.y * 0.6), Vector2(0.0, 0.0), crack_col, 2.5)
		draw_line(Vector2(0.0, 0.0), Vector2(half.x * 0.28, half.y * 0.55), crack_col, 2.5)
		draw_line(Vector2(0.0, 0.0), Vector2(half.x * 0.15, -half.y * 0.45), crack_col, 2.0)
	if hp_ratio < 0.45:
		draw_line(Vector2(-half.x * 0.7, half.y * 0.4), Vector2(-half.x * 0.15, -half.y * 0.1), crack_col, 3.0)
		draw_line(Vector2(-half.x * 0.15, -half.y * 0.1), Vector2(half.x * 0.65, -half.y * 0.5), crack_col, 3.0)
		draw_line(Vector2(half.x * 0.1, half.y * 0.1), Vector2(half.x * 0.72, half.y * 0.65), crack_col, 2.5)
