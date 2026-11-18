# res://Scripts/Entities/mine.gd
class_name ProximityMine extends Area2D

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

## Throwable Stealth Proximity Mine ("Q" gadget).
## Launches in a 2.5D parabolic arc toward the aimed direction, arms on landing,
## fades to almost invisible on the ground, and detonates on enemy tank proximity.

@export var flight_duration: float = 0.45
@export var arm_delay: float = 0.22
@export var trigger_radius: float = 50.0
@export var blast_radius: float = 135.0
@export var blast_damage: float = 70.0
@export var stealth_alpha: float = 0.14
@export var arc_peak_height: float = 48.0
@export var max_lifetime: float = 90.0

signal network_mine_detonated(mine: Node2D)

var net_id: int = 0
var is_network_puppet: bool = false
var owner_tank: Node2D = null
var start_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var tank_name: String = "Mina de Proximidad"
var is_mine: bool = true
var is_cluster_mine: bool = false

var is_in_flight: bool = true
var is_armed: bool = false
var visual_alpha: float = 1.0
var current_arc_height: float = 0.0

var _elapsed: float = 0.0
var _arm_elapsed: float = 0.0
var _lifetime: float = 0.0
var _spin_angle: float = 0.0
var _detonated: bool = false
var _col_shape: CollisionShape2D = null

func _ready() -> void:
	add_to_group("mines")
	add_to_group("mine")
	collision_layer = 0
	collision_mask = 0
	
	_col_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	_col_shape.shape = circle
	add_child(_col_shape)
	
	if start_pos == Vector2.ZERO and target_pos == Vector2.ZERO:
		start_pos = global_position
		target_pos = global_position
	queue_redraw()

func setup(p_owner: Node2D, p_start: Vector2, p_target: Vector2, p_is_cluster: bool = false, p_play_sound: bool = true) -> void:
	owner_tank = p_owner
	start_pos = p_start
	target_pos = p_target
	is_cluster_mine = p_is_cluster
	if is_cluster_mine:
		tank_name = "Mina Racimo"
	global_position = p_start
	is_in_flight = true
	is_armed = false
	visual_alpha = 1.0
	_elapsed = 0.0
	_arm_elapsed = 0.0
	if p_play_sound and SoundManagerScript != null:
		SoundManagerScript.play_mine_throw(p_start)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _detonated:
		return
		
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()
		return
		
	if is_in_flight:
		_elapsed += delta
		var t := clampf(_elapsed / maxf(0.01, flight_duration), 0.0, 1.0)
		# Smooth ease-out ground travel + parabolic arc height
		var eased_t := 1.0 - pow(1.0 - t, 1.35)
		global_position = start_pos.lerp(target_pos, eased_t)
		current_arc_height = sin(t * PI) * arc_peak_height
		_spin_angle += delta * 14.0
		
		if t >= 1.0:
			is_in_flight = false
			global_position = target_pos
			current_arc_height = 0.0
			_spin_angle = 0.0
		queue_redraw()
		return
		
	if not is_armed:
		_arm_elapsed += delta
		var arm_t := clampf(_arm_elapsed / maxf(0.01, arm_delay), 0.0, 1.0)
		visual_alpha = lerpf(1.0, stealth_alpha, arm_t)
		if arm_t >= 1.0:
			is_armed = true
			visual_alpha = stealth_alpha
			collision_layer = 16 # Layer 5: destructible by enemy gunfire / blasts
			if SoundManagerScript != null:
				SoundManagerScript.play_mine_arm(global_position)
		queue_redraw()
		return
		
	# Armed & stealthy on ground: subtle micro-shimmer while remaining nearly invisible
	visual_alpha = stealth_alpha + sin(_lifetime * 4.0) * 0.02
	if not is_network_puppet:
		_check_proximity_trigger()
	queue_redraw()

func _check_proximity_trigger() -> void:
	if is_network_puppet or get_tree() == null:
		return
	var tanks := get_tree().get_nodes_in_group("tanks")
	for t in tanks:
		if not is_instance_valid(t) or not (t is Node2D):
			continue
		if is_instance_valid(owner_tank) and t == owner_tank:
			continue
		var dead_val: bool = t.get("is_dead") if "is_dead" in t else false
		if dead_val:
			continue
		if global_position.distance_to((t as Node2D).global_position) <= trigger_radius:
			detonate()
			return

func take_damage(_amount: float, _attacker: Node2D = null, _is_barrel: bool = false) -> void:
	if is_network_puppet or _detonated or is_in_flight:
		return
	detonate()

func detonate() -> void:
	if is_network_puppet or _detonated:
		return
	_detonated = true
	collision_layer = 0
	if _col_shape != null:
		_col_shape.set_deferred("disabled", true)
	network_mine_detonated.emit(self)
	_play_mine_detonate_fx()
		
	if get_tree() != null:
		var attacker_ref: Node2D = owner_tank if is_instance_valid(owner_tank) else self
		
		# Damage enemy tanks in blast radius
		var tanks := get_tree().get_nodes_in_group("tanks")
		for t in tanks:
			if not is_instance_valid(t) or not (t is Node2D):
				continue
			if is_instance_valid(owner_tank) and t == owner_tank:
				continue
			var dead_val: bool = t.get("is_dead") if "is_dead" in t else false
			if dead_val:
				continue
			var dist: float = global_position.distance_to((t as Node2D).global_position)
			if dist <= blast_radius:
				var falloff := clampf(1.0 - (dist / (blast_radius * 1.4)), 0.65, 1.0)
				var dmg := blast_damage * falloff
				if "_incoming_mine_hit" in t:
					t.set("_incoming_mine_hit", true)
				if t.has_method("take_damage"):
					t.take_damage(dmg, attacker_ref, false)
					
		# Chain-detonate nearby barrels & damage destructible walls
		for grp in ["barrels", "destructible_walls"]:
			for obj in get_tree().get_nodes_in_group(grp):
				if is_instance_valid(obj) and obj != self and obj is Node2D:
					var dist: float = global_position.distance_to((obj as Node2D).global_position)
					if dist <= blast_radius and obj.has_method("take_damage"):
						obj.take_damage(blast_damage, attacker_ref, false)
						
	_spawn_explosion_vfx()
	visible = false
	queue_free()

func apply_network_detonate_fx() -> void:
	if _detonated:
		return
	_detonated = true
	collision_layer = 0
	if _col_shape != null:
		_col_shape.set_deferred("disabled", true)
	_play_mine_detonate_fx()
	_spawn_explosion_vfx()
	visible = false
	queue_free()

func _play_mine_detonate_fx() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_explosion(global_position)
	if get_tree() != null:
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			if GameEvents != null:
				GameEvents.screen_shake_requested.emit(0.25)
		elif is_instance_valid(players[0]) and players[0] is Node2D:
			var dist_player: float = global_position.distance_to((players[0] as Node2D).global_position)
			if dist_player < 1850.0 and GameEvents != null:
				var trauma := clampf((1.0 - (dist_player / 1850.0)) * 0.58, 0.0, 0.58)
				GameEvents.screen_shake_requested.emit(trauma)

func _spawn_explosion_vfx() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var particles := CPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.98
	particles.lifetime = 0.55
	particles.amount = 36
	particles.spread = 180.0
	particles.initial_velocity_min = 90.0
	particles.initial_velocity_max = 250.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 3.5
	particles.scale_amount_max = 8.5
	particles.color = Color(1.0, 0.42, 0.12, 1.0)
	particles.global_position = global_position
	parent_node.add_child(particles)
	if get_tree() != null:
		var timer := get_tree().create_timer(0.65)
		timer.timeout.connect(particles.queue_free)

func _draw() -> void:
	if _detonated:
		return
		
	var alpha := clampf(visual_alpha, 0.05, 1.0)
	
	# While airborne: draw ground shadow, faint landing ring, and elevated spinning mine
	if is_in_flight:
		var height_ratio := clampf(current_arc_height / maxf(1.0, arc_peak_height), 0.0, 1.0)
		var shadow_r := lerpf(13.0, 7.5, height_ratio)
		draw_circle(Vector2(0, 6.0), shadow_r, Color(0.0, 0.0, 0.0, 0.35 * (1.0 - height_ratio * 0.4)))
		
		var to_landing := target_pos - global_position
		draw_arc(to_landing, 16.0, 0.0, TAU, 24, Color(1.0, 0.35, 0.2, 0.32), 1.5)
		
		var lob_offset := Vector2(0.0, -current_arc_height)
		var lob_scale := 1.0 + height_ratio * 0.38
		draw_set_transform(lob_offset, _spin_angle, Vector2(lob_scale, lob_scale))
		_draw_mine_body(1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		# Landed / Stealth mine on ground
		if not is_armed:
			# Brief arming ring shrink
			var arm_r := lerpf(trigger_radius, 14.0, clampf(_arm_elapsed / maxf(0.01, arm_delay), 0.0, 1.0))
			draw_arc(Vector2.ZERO, arm_r, 0.0, TAU, 32, Color(1.0, 0.3, 0.2, alpha * 0.65), 1.5)
		_draw_mine_body(alpha, not is_armed)

func _draw_mine_body(alpha: float, bright_led: bool) -> void:
	# Outer tactical casing
	var rim_col := Color(1.0, 0.56, 0.14, alpha) if is_cluster_mine else Color(0.42, 0.48, 0.55, alpha)
	var prong_col := Color(0.85, 0.45, 0.16, alpha) if is_cluster_mine else Color(0.32, 0.36, 0.42, alpha)
	draw_circle(Vector2.ZERO, 13.0, Color(0.16, 0.19, 0.22, alpha))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, rim_col, 2.0)
	# 4 radial prongs
	for i in range(4):
		var ang := float(i) * (PI * 0.5) + PI * 0.25
		var p1 := Vector2.RIGHT.rotated(ang) * 9.0
		var p2 := Vector2.RIGHT.rotated(ang) * 15.0
		draw_line(p1, p2, prong_col, 3.0)
	# Inner pressure plate
	draw_circle(Vector2.ZERO, 8.0, Color(0.24, 0.28, 0.32, alpha))
	# Center LED core
	var base_led := Color(1.0, 0.38, 0.08) if is_cluster_mine else Color(1.0, 0.2, 0.15)
	var led_col := Color(base_led.r, base_led.g, base_led.b, alpha if not bright_led else minf(1.0, alpha + 0.3))
	draw_circle(Vector2.ZERO, 3.5, led_col)
