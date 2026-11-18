# res://Scripts/Entities/barrel.gd
class_name Barrel extends StaticBody2D

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

## Destructible explosive barrel with wall-penetrating AoE damage.
## StaticBody2D on Layer 5 (Barrels: 16), Mask: Layers 3 & 4 (Tanks: 4, Projectiles: 8 -> 12).

@export var max_hp: float = 30.0
@export var blast_radius: float = 200.0
@export var min_damage: float = 25.0
@export var max_damage: float = 85.0
@export var respawn_delay: float = 15.0

signal network_barrel_damaged(barrel: Node2D, new_hp: float)
signal network_barrel_exploded(barrel: Node2D)
signal network_barrel_respawned(barrel: Node2D)

var net_slot: int = -1
var is_network_puppet: bool = false
var current_hp: float = 30.0
var hp: float:
	get: return current_hp
	set(v): current_hp = v
var aoe_radius: float:
	get: return blast_radius
var last_attacker: Node2D = null
var is_exploded: bool = false
var is_in_sight: bool = true
var _respawn_timer: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("barrels")
	add_to_group("destructibles")
	current_hp = max_hp
	collision_layer = 16 # Layer 5
	collision_mask = 12  # Layers 3 & 4 (Tanks & Projectiles)
	if GameEvents != null and not GameEvents.match_started.is_connected(_on_match_started):
		GameEvents.match_started.connect(_on_match_started)
	queue_redraw()

func _process(delta: float) -> void:
	if is_network_puppet or not is_exploded or respawn_delay <= 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		if _is_clear_of_tanks(46.0):
			respawn_barrel()
		else:
			_respawn_timer = 0.5

func _on_match_started(_duration: float) -> void:
	if is_exploded:
		respawn_barrel()

func _is_clear_of_tanks(min_dist: float) -> bool:
	if get_tree() == null:
		return true
	for t in get_tree().get_nodes_in_group("tanks"):
		if is_instance_valid(t) and t is Node2D and t.get("is_dead") != true:
			if global_position.distance_to((t as Node2D).global_position) < min_dist:
				return false
	return true

func respawn_barrel() -> void:
	apply_network_respawn_fx()
	network_barrel_respawned.emit(self)

func apply_network_respawn_fx() -> void:
	is_exploded = false
	current_hp = max_hp
	last_attacker = null
	_respawn_timer = 0.0
	collision_layer = 16
	collision_mask = 12
	if collision_shape != null:
		collision_shape.set_deferred("disabled", false)
	visible = true
	_spawn_respawn_vfx()
	queue_redraw()

func take_damage(amount: float, attacker: Node2D, is_barrel: bool = false) -> void:
	if is_network_puppet or is_exploded:
		return
		
	if is_instance_valid(attacker):
		last_attacker = attacker
		
	current_hp -= amount
	queue_redraw()
	
	if current_hp <= 0.0:
		explode()
	else:
		if SoundManagerScript != null:
			SoundManagerScript.play_hit(global_position)
		network_barrel_damaged.emit(self, current_hp)

func apply_network_damage_fx(new_hp: float) -> void:
	current_hp = new_hp
	queue_redraw()
	if SoundManagerScript != null:
		SoundManagerScript.play_hit(global_position)

func explode() -> void:
	if is_network_puppet or is_exploded:
		return
	is_exploded = true
	
	# Disable collisions immediately to prevent repeated hits
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
		
	_perform_aoe_blast()
	_play_explode_fx()
	network_barrel_exploded.emit(self)
	
	var valid_attacker: Node2D = last_attacker if is_instance_valid(last_attacker) else null
	if GameEvents != null:
		GameEvents.barrel_destroyed.emit(self, valid_attacker)
		
	visible = false
	if respawn_delay > 0.0:
		_respawn_timer = respawn_delay
	else:
		queue_free()

func apply_network_explode_fx() -> void:
	if is_exploded:
		return
	is_exploded = true
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	_play_explode_fx()
	visible = false

func _play_explode_fx() -> void:
	_spawn_explosion_vfx()
	if SoundManagerScript != null:
		SoundManagerScript.play_explosion(global_position)
	var players := get_tree().get_nodes_in_group("player") if get_tree() != null else []
	if players.is_empty():
		if GameEvents != null:
			GameEvents.screen_shake_requested.emit(0.25)
	elif is_instance_valid(players[0]) and players[0] is Node2D:
		var dist_player: float = global_position.distance_to((players[0] as Node2D).global_position)
		if dist_player < 1850.0 and GameEvents != null:
			var trauma := clampf((1.0 - (dist_player / 1850.0)) * 0.6, 0.0, 0.6)
			GameEvents.screen_shake_requested.emit(trauma)

func _perform_aoe_blast() -> void:
	var world_2d := get_world_2d()
	if world_2d == null:
		return
	var space_state := world_2d.direct_space_state
	if space_state == null:
		return
		
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = blast_radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	# Mask: Layer 3 (Tanks = 4) and Layer 5 (Barrels = 16) -> 20
	# DELIBERATELY IGNORES Layer 2 (Walls = 2) so the blast wave penetrates walls per GDD specification!
	query.collision_mask = 20
	query.collide_with_bodies = true
	query.collide_with_areas = true
	
	var hits := space_state.intersect_shape(query, 64)
	var processed_colliders: Array[Node] = []
	
	for hit in hits:
		var collider: Object = hit.collider
		if collider == null or collider == self or not is_instance_valid(collider):
			continue
		if collider in processed_colliders:
			continue
		processed_colliders.append(collider)
		
		var collider_pos: Vector2 = (collider as Node2D).global_position if collider is Node2D else global_position
		var dist: float = global_position.distance_to(collider_pos)
		if dist > blast_radius:
			continue
			
		var ratio: float = clamp(1.0 - (dist / blast_radius), 0.0, 1.0)
		var blast_damage: float = lerp(min_damage, max_damage, ratio)
		
		if collider.has_method("take_damage"):
			var valid_attacker: Node2D = last_attacker if is_instance_valid(last_attacker) else null
			collider.take_damage(blast_damage, valid_attacker, true)
			
	if get_tree() != null:
		for dw in get_tree().get_nodes_in_group("destructible_walls"):
			if is_instance_valid(dw) and dw is Node2D and dw.has_method("take_damage"):
				var d_wall: float = global_position.distance_to((dw as Node2D).global_position)
				if d_wall <= blast_radius:
					dw.take_damage(max_damage, last_attacker if is_instance_valid(last_attacker) else null, true)

func _spawn_explosion_vfx() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
		
	# Explosion particle burst
	var particles := CPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 0.65
	particles.amount = 40
	particles.spread = 180.0
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 260.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 9.0
	particles.color = Color(1.0, 0.45, 0.1, 1.0)
	particles.global_position = global_position
	parent_node.add_child(particles)
	
	if get_tree() != null:
		var timer := get_tree().create_timer(0.7)
		timer.timeout.connect(particles.queue_free)

func _spawn_respawn_vfx() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var spark := CPUParticles2D.new()
	spark.emitting = true
	spark.one_shot = true
	spark.explosiveness = 0.85
	spark.lifetime = 0.35
	spark.amount = 14
	spark.spread = 180.0
	spark.initial_velocity_min = 35.0
	spark.initial_velocity_max = 85.0
	spark.gravity = Vector2.ZERO
	spark.scale_amount_min = 2.5
	spark.scale_amount_max = 4.5
	spark.color = Color(1.0, 0.78, 0.2, 0.9)
	spark.global_position = global_position
	parent_node.add_child(spark)
	if get_tree() != null:
		var timer := get_tree().create_timer(0.42)
		timer.timeout.connect(spark.queue_free)

func _draw() -> void:
	if is_exploded:
		return
	# Outer steel rim
	draw_circle(Vector2.ZERO, 18.0, Color(0.2, 0.2, 0.24, 1.0))
	# Red drum body
	var drum_color := Color(0.85, 0.2, 0.15, 1.0)
	if current_hp < max_hp:
		drum_color = Color(0.95, 0.4, 0.1, 1.0)
	draw_circle(Vector2.ZERO, 16.0, drum_color)
	# Inner ring
	draw_circle(Vector2.ZERO, 12.0, Color(0.7, 0.15, 0.1, 1.0))
	# Hazard yellow stripes
	draw_line(Vector2(-8, -4), Vector2(8, -4), Color(1.0, 0.85, 0.1, 0.9), 3.0)
	draw_line(Vector2(-8, 4), Vector2(8, 4), Color(1.0, 0.85, 0.1, 0.9), 3.0)
	# Center black dot
	draw_circle(Vector2.ZERO, 4.0, Color(0.1, 0.1, 0.12, 1.0))
