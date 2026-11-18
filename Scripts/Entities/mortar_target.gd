# res://Scripts/Entities/mortar_target.gd
class_name MortarTarget extends Node2D

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

## High-danger mortar artillery strike.
## Renders an opaque-to-vibrant expanding/pulsing red telegraph zone,
## detonating after a 2-second warning with massive AoE radial damage and screen shake.

@export var telegraph_duration: float = 2.0
@export var blast_radius: float = 140.0
@export var blast_damage: float = 60.0
@export var is_mortar: bool = true

var is_network_puppet: bool = false
var tank_name: String = "Mortero de Artillería"
var time_elapsed: float = 0.0
var _detonated: bool = false

func _ready() -> void:
	add_to_group("mortars")
	add_to_group("mortar")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _detonated:
		return
		
	time_elapsed += delta
	queue_redraw()
	
	if time_elapsed >= telegraph_duration:
		detonate()

func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	
	# Audio & Shake
	if SoundManagerScript != null:
		SoundManagerScript.play_mortar_explosion(global_position)
		
	var players := get_tree().get_nodes_in_group("player") if get_tree() != null else []
	if players.is_empty():
		if GameEvents != null:
			GameEvents.screen_shake_requested.emit(0.25)
	elif is_instance_valid(players[0]) and players[0] is Node2D:
		var dist_player: float = global_position.distance_to((players[0] as Node2D).global_position)
		if dist_player < 1950.0 and GameEvents != null:
			var trauma := clampf((1.0 - (dist_player / 1950.0)) * 0.65, 0.0, 0.65)
			GameEvents.screen_shake_requested.emit(trauma)
		
	# Radial AoE Damage against Tanks & Barrels (authoritative only)
	if not is_network_puppet and get_tree() != null:
		var tanks := get_tree().get_nodes_in_group("tanks")
		for tank in tanks:
			if is_instance_valid(tank) and tank is Node2D:
				var is_dead_val: bool = tank.get("is_dead") if "is_dead" in tank else false
				if not is_dead_val:
					var dist: float = global_position.distance_to((tank as Node2D).global_position)
					if dist <= blast_radius:
						var falloff: float = clampf(1.0 - (dist / (blast_radius * 1.25)), 0.45, 1.0)
						var dmg: float = blast_damage * falloff
						if tank.has_method("take_damage"):
							tank.take_damage(dmg, self, false)
							
		var barrels := get_tree().get_nodes_in_group("barrels")
		for barrel in barrels:
			if is_instance_valid(barrel) and barrel is Node2D:
				var dist: float = global_position.distance_to((barrel as Node2D).global_position)
				if dist <= blast_radius:
					if barrel.has_method("take_damage"):
						barrel.take_damage(blast_damage, self)
						
		for dw in get_tree().get_nodes_in_group("destructible_walls"):
			if is_instance_valid(dw) and dw is Node2D and dw.has_method("take_damage"):
				var dist_w: float = global_position.distance_to((dw as Node2D).global_position)
				if dist_w <= blast_radius:
					dw.take_damage(blast_damage, self, false)
						
	_spawn_explosion_vfx()
	visible = false
	queue_free()

func _spawn_explosion_vfx() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
		
	var particles := CPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.6
	particles.amount = 40
	particles.spread = 180.0
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 260.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 9.0
	particles.color = Color(1.0, 0.35, 0.1, 1.0)
	particles.global_position = global_position
	parent_node.add_child(particles)
	
	if get_tree() != null:
		var timer := get_tree().create_timer(0.7)
		timer.timeout.connect(particles.queue_free)

func _draw() -> void:
	if _detonated:
		return
		
	var progress := clampf(time_elapsed / maxf(0.01, telegraph_duration), 0.0, 1.0)
	
	# 1. Semi-opaque to highly vibrant red danger circle
	var alpha := lerpf(0.12, 0.72, progress)
	var fill_color := Color(1.0, 0.08, 0.08, alpha)
	draw_circle(Vector2.ZERO, blast_radius, fill_color)
	
	# 2. Outer hazard perimeter ring with bright pulsing border
	var pulse := (sin(time_elapsed * 12.0) + 1.0) * 0.5
	var border_color := Color(1.0, 0.2 + pulse * 0.3, 0.2, 0.9)
	draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 48, border_color, 3.5)
	
	# 3. Contracting countdown ring moving from outer border towards center
	var contract_r := blast_radius * (1.0 - progress)
	draw_arc(Vector2.ZERO, contract_r, 0.0, TAU, 36, Color(1.0, 0.9, 0.2, 0.95), 2.5)
	
	# 4. Center artillery crosshairs
	var cross_col := Color(1.0, 0.9, 0.3, 0.9)
	draw_line(Vector2(-14, 0), Vector2(14, 0), cross_col, 2.5)
	draw_line(Vector2(0, -14), Vector2(0, 14), cross_col, 2.5)
	draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
