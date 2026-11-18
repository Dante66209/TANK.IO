# res://Scripts/Entities/projectile.gd
class_name Projectile extends Area2D

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

## High-speed ballistic projectile colliding with walls, barrels, and enemy tanks.

@export var speed: float = 650.0
@export var damage: float = 25.0
@export var max_lifetime: float = 2.5
@export var bounces_remaining: int = 0
@export var is_ricochet: bool = false:
	set(val):
		is_ricochet = val
		if is_ricochet and damage <= 25.0:
			damage = 38.0

signal network_impacted(proj: Node2D, hit_pos: Vector2)

var net_id: int = 0
var is_network_puppet: bool = false
var direction: Vector2 = Vector2.RIGHT
var shooter: Node2D = null
var current_lifetime: float = 0.0
var _is_destroyed: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	queue_redraw()

func setup(p_shooter: Node2D, p_direction: Vector2, p_speed: float = 650.0, p_damage: float = 25.0) -> void:
	shooter = p_shooter
	direction = p_direction.normalized()
	speed = p_speed
	damage = p_damage if not is_ricochet else maxf(p_damage, 38.0)
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if _is_destroyed:
		return
		
	global_position += direction * speed * delta
	current_lifetime += delta
	if current_lifetime >= max_lifetime:
		destroy()

func _on_body_entered(body: Node2D) -> void:
	if _is_destroyed or (is_instance_valid(shooter) and body == shooter):
		return
		
	if body.has_method("take_damage"):
		_handle_impact(body)
		return
		
	# Wall collision (StaticBody2D covers and boundaries)
	if bounces_remaining > 0:
		_handle_bounce(body)
	else:
		_handle_impact(body)

func _handle_bounce(_body: Node2D) -> void:
	bounces_remaining -= 1
	
	# Determine collision normal via direct raycast
	var space_state := get_world_2d().direct_space_state
	var normal := -direction
	if space_state != null:
		var ray_from := global_position - direction * 32.0
		var ray_to := global_position + direction * 32.0
		var query := PhysicsRayQueryParameters2D.create(ray_from, ray_to)
		query.collision_mask = 1 | 2 # Layer 1 (Boundary) & Layer 2 (ModularCovers)
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			normal = hit.normal
			global_position = hit.position + normal * 6.0
	
	direction = direction.bounce(normal).normalized()
	rotation = direction.angle()
	
	_spawn_bounce_fx()
	if SoundManagerScript != null:
		SoundManagerScript.play_ricochet(global_position)
	queue_redraw()

func _spawn_bounce_fx() -> void:
	var sparks := CPUParticles2D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.lifetime = 0.2
	sparks.amount = 12
	sparks.direction = direction
	sparks.spread = 60.0
	sparks.initial_velocity_min = 80.0
	sparks.initial_velocity_max = 160.0
	sparks.gravity = Vector2.ZERO
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 4.0
	sparks.color = Color(0.2, 0.9, 1.0, 1.0) if is_ricochet else Color(1.0, 0.8, 0.3, 1.0)
	sparks.global_position = global_position
	
	var parent_node := get_parent()
	if parent_node != null:
		parent_node.add_child(sparks)
		if get_tree() != null:
			var timer := get_tree().create_timer(0.25)
			timer.timeout.connect(sparks.queue_free)

func _on_area_entered(area: Area2D) -> void:
	if _is_destroyed or (is_instance_valid(shooter) and area == shooter):
		return
	if is_instance_valid(shooter) and "owner_tank" in area and area.get("owner_tank") == shooter:
		return
	_handle_impact(area)

func _handle_impact(target: Node2D) -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	
	if not is_network_puppet:
		if target.has_method("take_damage"):
			var valid_shooter: Node2D = shooter if is_instance_valid(shooter) else null
			target.take_damage(damage, valid_shooter, false)
		elif SoundManagerScript != null:
			SoundManagerScript.play_hit(global_position)
		network_impacted.emit(self, global_position)
	elif SoundManagerScript != null and not (target != null and target.has_method("take_damage")):
		SoundManagerScript.play_hit(global_position)
	
	_spawn_impact_fx()
	queue_free()

func network_destroy(hit_pos: Vector2) -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	global_position = hit_pos
	_spawn_impact_fx()
	queue_free()

func destroy() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	_spawn_impact_fx()
	queue_free()

func _spawn_impact_fx() -> void:
	# Small procedural particle spark effect
	var sparks := CPUParticles2D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.lifetime = 0.25
	sparks.amount = 8
	sparks.direction = -direction
	sparks.spread = 45.0
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 140.0
	sparks.gravity = Vector2.ZERO
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 4.0
	sparks.color = Color(1.0, 0.75, 0.2, 1.0)
	sparks.global_position = global_position
	
	var parent_node := get_parent()
	if parent_node != null:
		parent_node.add_child(sparks)
		# Auto clean up sparks when finished
		if get_tree() != null:
			var timer := get_tree().create_timer(0.3)
			timer.timeout.connect(sparks.queue_free)

func _draw() -> void:
	if is_ricochet:
		# Vibrant electric cyan ricochet bullet
		draw_circle(Vector2.ZERO, 7.0, Color(0.1, 0.8, 1.0, 0.35))
		draw_circle(Vector2.ZERO, 4.5, Color(0.2, 0.95, 1.0, 1.0))
		draw_circle(Vector2.ZERO, 2.0, Color(0.9, 1.0, 1.0, 1.0))
		draw_line(Vector2(-14.0, 0.0), Vector2.ZERO, Color(0.1, 0.85, 1.0, 0.8), 3.5)
	else:
		# Standard golden ballistic projectile
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.6, 0.1, 0.3))
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.85, 0.3, 1.0))
		draw_circle(Vector2.ZERO, 2.0, Color(1.0, 1.0, 0.9, 1.0))
		draw_line(Vector2(-10.0, 0.0), Vector2.ZERO, Color(1.0, 0.5, 0.1, 0.7), 3.0)
