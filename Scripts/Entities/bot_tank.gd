# res://Scripts/Entities/bot_tank.gd
class_name BotTank extends Tank

## Autonomous Bot Combat AI (R7).
## Features:
## - Sensory perception via SightArea2D (radius 420px) and AimRayCast2D.
## - 5-whisker context steering ([-45°, -20°, 0°, +20°, +45°], 70px) avoiding Layers 1 & 2.
## - 4-State Finite State Machine: WANDER, COMBAT, SEEK_POWERUP, RETREAT.
## - 1st-order predictive lead aiming and tactical strafing.

enum State { WANDER = 0, COMBAT = 1, SEEK_POWERUP = 2, RETREAT = 3 }

@export var bot_state: State = State.WANDER
var current_state: State:
	get: return bot_state
	set(val): bot_state = val

var current_target: Node2D = null
var current_powerup: Node2D = null
var whisker_rays: Array[RayCast2D] = []

# Perception & Navigation internals
var _waypoints: Array[Vector2] = []
var _current_waypoint_idx: int = 0
var _current_waypoint: Vector2 = Vector2.ZERO
var _turret_scan_timer: float = 0.0
var _strafe_timer: float = 0.0
var _strafe_sign: float = 1.0
var _stuck_timer: float = 0.0
var _escape_sign: float = 1.0
var _bot_mine_timer: float = 6.0

# Node references
@onready var sight_area: Area2D = $SightArea2D
@onready var aim_raycast: RayCast2D = $AimRayCast2D
@onready var whiskers_node: Node2D = $Whiskers

func _ready() -> void:
	is_player = false
	sight_radius = 420.0
	if tank_name == "Tank":
		tank_name = "BotTank"
		
	super._ready()
	if is_network_puppet:
		_disable_ai_sensors()
		return
	
	_setup_whiskers()
	_setup_aim_raycast()
	_setup_sight_area()
	_init_waypoints()

func _disable_ai_sensors() -> void:
	if sight_area != null:
		sight_area.monitoring = false
		sight_area.monitorable = false
	if aim_raycast != null:
		aim_raycast.enabled = false
	for w in whisker_rays:
		if is_instance_valid(w):
			w.enabled = false

func _setup_whiskers() -> void:
	whisker_rays.clear()
	if whiskers_node == null:
		whiskers_node = Node2D.new()
		whiskers_node.name = "Whiskers"
		add_child(whiskers_node)
		
	var existing_rays: Array[Node] = whiskers_node.get_children()
	if existing_rays.is_empty():
		var angles: Array[float] = [-45.0, -20.0, 0.0, 20.0, 45.0]
		for i in range(angles.size()):
			var deg: float = angles[i]
			var rad: float = deg_to_rad(deg)
			var ray := RayCast2D.new()
			ray.name = "Whisker_%d" % i
			ray.enabled = true
			ray.target_position = Vector2.RIGHT.rotated(rad) * 70.0
			ray.collision_mask = 3 # Layer 1 (Boundary) | Layer 2 (Walls)
			ray.collide_with_areas = false
			ray.collide_with_bodies = true
			whiskers_node.add_child(ray)
			whisker_rays.append(ray)
	else:
		for child in existing_rays:
			if child is RayCast2D:
				child.enabled = true
				child.collision_mask = 3
				whisker_rays.append(child)

func _setup_aim_raycast() -> void:
	if aim_raycast == null:
		aim_raycast = RayCast2D.new()
		aim_raycast.name = "AimRayCast2D"
		aim_raycast.enabled = true
		aim_raycast.target_position = Vector2.RIGHT * 420.0
		aim_raycast.collision_mask = 3 # Layer 1 & Layer 2 walls
		aim_raycast.collide_with_areas = false
		aim_raycast.collide_with_bodies = true
		add_child(aim_raycast)
	else:
		aim_raycast.enabled = true
		aim_raycast.collision_mask = 3

func _setup_sight_area() -> void:
	if sight_area != null:
		sight_area.collision_layer = 64
		sight_area.collision_mask = 52 # Layer 3 (Tanks: 4) | Layer 5 (Barrels: 16) | Layer 6 (PowerUps: 32)
		if sight_area.has_node("CollisionShape2D"):
			var col: CollisionShape2D = sight_area.get_node("CollisionShape2D")
			if col.shape is CircleShape2D:
				(col.shape as CircleShape2D).radius = 420.0

func _init_waypoints() -> void:
	var map_node := get_tree().get_first_node_in_group("world_map")
	if map_node != null and map_node.has_method("get_spawn_positions"):
		_waypoints = map_node.get_spawn_positions()
	if _waypoints.is_empty():
		_waypoints = [
			Vector2(-700, -700), Vector2(700, -700),
			Vector2(700, 700), Vector2(-700, 700),
			Vector2(0, 0), Vector2(0, -450), Vector2(0, 450),
			Vector2(-450, 0), Vector2(450, 0)
		]
	_current_waypoint = _waypoints[randi() % _waypoints.size()]

func _physics_process(delta: float) -> void:
	if is_network_puppet or is_dead or controls_locked:
		super._physics_process(delta)
		return
		
	_validate_target()
	_update_fsm_state()
	_execute_fsm_state(delta)
	
	super._physics_process(delta)

func _validate_target() -> void:
	if current_target != null:
		if not is_instance_valid(current_target):
			current_target = null
		else:
			var target_dead: bool = current_target.get("is_dead") if "is_dead" in current_target else false
			var dist: float = global_position.distance_to(current_target.global_position)
			if target_dead or dist > (sight_radius * 1.15):
				current_target = null

func _update_fsm_state() -> void:
	var hp_ratio: float = current_health / max_health if max_health > 0.0 else 1.0
	
	# Priority 1: Low health retreat
	if hp_ratio < 0.25:
		# If a health or shield powerup is nearby in sight, prioritize collecting it
		var nearby_pu := _find_best_powerup(true)
		if nearby_pu != null:
			current_powerup = nearby_pu
			bot_state = State.SEEK_POWERUP
			return
		elif current_target != null:
			bot_state = State.RETREAT
			return
			
	# Priority 2: Power-up seeking when damaged (< 70% HP)
	if hp_ratio < 0.70:
		var nearby_pu := _find_best_powerup(true)
		if nearby_pu != null:
			current_powerup = nearby_pu
			bot_state = State.SEEK_POWERUP
			return
			
	# Priority 3: Combat engagement
	if current_target != null:
		bot_state = State.COMBAT
		return
		
	# Try acquiring target within sight
	var threat := acquire_target()
	if threat != null:
		current_target = threat
		bot_state = State.COMBAT
		return
		
	# Opportunistic power-up pickup when wandering with no immediate threat
	var opportunistic_pu := _find_best_powerup(false)
	if opportunistic_pu != null and global_position.distance_to(opportunistic_pu.global_position) <= 280.0:
		current_powerup = opportunistic_pu
		bot_state = State.SEEK_POWERUP
		return
		
	# Fallback: Wander
	bot_state = State.WANDER

func _execute_fsm_state(delta: float) -> void:
	if _bot_mine_timer > 0.0:
		_bot_mine_timer = maxf(0.0, _bot_mine_timer - delta)
		
	# Sudden Death Closing Zone Priority: steer inward toward (0,0) if near or outside storm perimeter!
	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("is_sudden_death") == true:
		var sz_val = mm.get("safe_zone_radius")
		var safe_r: float = float(sz_val) if sz_val != null else 4550.0
		if global_position.length() > safe_r * 0.80:
			var inward_dir := (-global_position).normalized()
			var steered := _steer_with_whiskers(inward_dir, delta)
			set_chassis_input(steered)
			if current_target != null and is_instance_valid(current_target):
				set_turret_target(current_target.global_position)
				if has_line_of_sight(current_target.global_position):
					shoot()
			else:
				set_turret_target(Vector2.ZERO)
			return
			
	match bot_state:
		State.WANDER:
			_state_wander(delta)
		State.COMBAT:
			_state_combat(delta)
		State.SEEK_POWERUP:
			_state_seek_powerup(delta)
		State.RETREAT:
			_state_retreat(delta)

# ------------------------------------------------------------------------------
# FSM State 1: WANDER
# ------------------------------------------------------------------------------
func _state_wander(delta: float) -> void:
	# Check if waypoint reached
	if global_position.distance_to(_current_waypoint) < 90.0:
		_pick_next_waypoint()
		
	var desired_dir: Vector2 = (_current_waypoint - global_position)
	if desired_dir.length_squared() > 1.0:
		desired_dir = desired_dir.normalized()
	else:
		desired_dir = Vector2.RIGHT
		
	var final_move_dir := _steer_with_whiskers(desired_dir, delta)
	set_chassis_input(final_move_dir)
	
	# Turret scanning sweep (±45 degrees relative to chassis heading)
	_turret_scan_timer += delta * 2.2
	var heading: float = final_move_dir.angle() if final_move_dir != Vector2.ZERO else (chassis_visual.rotation if chassis_visual != null else 0.0)
	var sweep_angle: float = heading + sin(_turret_scan_timer) * (PI / 4.0)
	set_turret_target(global_position + Vector2.RIGHT.rotated(sweep_angle) * 150.0)

func _pick_next_waypoint() -> void:
	if _waypoints.is_empty():
		_init_waypoints()
	if not _waypoints.is_empty():
		_current_waypoint_idx = (_current_waypoint_idx + 1 + (randi() % 2)) % _waypoints.size()
		_current_waypoint = _waypoints[_current_waypoint_idx]

# ------------------------------------------------------------------------------
# FSM State 2: COMBAT
# ------------------------------------------------------------------------------
func _state_combat(delta: float) -> void:
	if current_target == null or not is_instance_valid(current_target):
		bot_state = State.WANDER
		return
		
	var target_pos: Vector2 = current_target.global_position
	var dist: float = global_position.distance_to(target_pos)
	
	# 1st-Order Predictive Lead Aiming
	var speed_val: float = bullet_speed if bullet_speed > 0.0 else BASE_BULLET_SPEED
	var t_impact: float = dist / speed_val
	var target_vel: Vector2 = Vector2.ZERO
	if "velocity" in current_target:
		target_vel = current_target.velocity
	var aim_pos: Vector2 = target_pos + target_vel * t_impact
	
	set_turret_target(aim_pos)
	
	# Fire condition: angular error < 0.15 rad and clear line of sight
	var desired_rot: float = (aim_pos - global_position).angle()
	var current_rot: float = turret_pivot.global_rotation if turret_pivot != null else target_aim_angle
	var angular_error: float = absf(wrapf(current_rot - desired_rot, -PI, PI))
	
	if angular_error < 0.15 and has_line_of_sight(target_pos):
		shoot()
		
	# Occasional tactical mine lob when enemy is at medium-close range
	if _bot_mine_timer <= 0.0 and mines_count > 0 and dist > 110.0 and dist < 310.0 and angular_error < 0.25:
		_bot_mine_timer = randf_range(8.5, 13.5)
		throw_mine()
		
	# Tactical Maneuvering & Strafing (maintaining 140 - 280px distance)
	_strafe_timer += delta
	if _strafe_timer >= 2.0:
		_strafe_timer = 0.0
		_strafe_sign = -_strafe_sign
		
	var to_target: Vector2 = (target_pos - global_position).normalized()
	var desired_dir: Vector2 = Vector2.ZERO
	
	if dist > 280.0:
		# Advance while strafing slightly
		desired_dir = (to_target + to_target.orthogonal() * _strafe_sign * 0.45).normalized()
	elif dist < 140.0:
		# Back up while strafing
		desired_dir = (-to_target + to_target.orthogonal() * _strafe_sign * 0.45).normalized()
	else:
		# Pure lateral strafing within sweet spot
		desired_dir = to_target.orthogonal() * _strafe_sign
		
	var final_move_dir := _steer_with_whiskers(desired_dir, delta)
	set_chassis_input(final_move_dir)

# ------------------------------------------------------------------------------
# FSM State 3: SEEK_POWERUP
# ------------------------------------------------------------------------------
func _state_seek_powerup(delta: float) -> void:
	if current_powerup == null or not is_instance_valid(current_powerup):
		current_powerup = _find_best_powerup(true)
		if current_powerup == null:
			bot_state = State.WANDER
			return
			
	var pu_pos: Vector2 = current_powerup.global_position
	var desired_dir: Vector2 = (pu_pos - global_position)
	if desired_dir.length_squared() > 1.0:
		desired_dir = desired_dir.normalized()
	else:
		desired_dir = Vector2.RIGHT
		
	var final_move_dir := _steer_with_whiskers(desired_dir, delta)
	set_chassis_input(final_move_dir)
	
	# Turret can aim forward or toward target if one is in sight
	if current_target != null and is_instance_valid(current_target):
		set_turret_target(current_target.global_position)
		if has_line_of_sight(current_target.global_position):
			shoot()
	else:
		set_turret_target(pu_pos)

func seek_powerup(powerup: Node2D) -> void:
	if is_instance_valid(powerup):
		current_powerup = powerup
		bot_state = State.SEEK_POWERUP

# ------------------------------------------------------------------------------
# FSM State 4: RETREAT
# ------------------------------------------------------------------------------
func _state_retreat(delta: float) -> void:
	var threat_pos: Vector2 = Vector2.ZERO
	if current_target != null and is_instance_valid(current_target):
		threat_pos = current_target.global_position
	else:
		threat_pos = global_position - Vector2.RIGHT * 200.0
		
	var flee_dir: Vector2 = (global_position - threat_pos)
	if flee_dir.length_squared() > 1.0:
		flee_dir = flee_dir.normalized()
	else:
		flee_dir = Vector2.LEFT
		
	var final_move_dir := _steer_with_whiskers(flee_dir, delta)
	set_chassis_input(final_move_dir)
	
	# Retaliatory fire while retreating if lined up
	if current_target != null and is_instance_valid(current_target):
		set_turret_target(threat_pos)
		var desired_rot: float = (threat_pos - global_position).angle()
		var current_rot: float = turret_pivot.global_rotation if turret_pivot != null else target_aim_angle
		var angular_error: float = absf(wrapf(current_rot - desired_rot, -PI, PI))
		if angular_error < 0.25 and has_line_of_sight(threat_pos):
			shoot()

# ------------------------------------------------------------------------------
# Navigation & Context Steering (5-Whisker Obstacle Avoidance)
# ------------------------------------------------------------------------------
func _steer_with_whiskers(desired_direction: Vector2, delta: float) -> Vector2:
	if desired_direction == Vector2.ZERO:
		return Vector2.ZERO
		
	var base_heading: float = desired_direction.angle()
	if whiskers_node != null:
		whiskers_node.rotation = base_heading
		
	var avoidance_vector: Vector2 = Vector2.ZERO
	var s: int = whisker_rays.size()
	var hitting_whiskers: int = 0
	
	for ray in whisker_rays:
		if not is_instance_valid(ray):
			continue
		ray.force_raycast_update()
		if ray.is_colliding():
			hitting_whiskers += 1
			var col_pt: Vector2 = ray.get_collision_point()
			var col_normal: Vector2 = ray.get_collision_normal()
			var dist: float = global_position.distance_to(col_pt)
			var weight: float = clampf(1.0 - (dist / 70.0), 0.1, 1.0)
			# Wall normal repulsion + push away from hit point
			var repulse: Vector2 = (col_normal * 1.6 + (global_position - col_pt).normalized()).normalized()
			avoidance_vector += repulse * weight * 2.5
			
	# Corner deadlock detection & escape
	if desired_direction.length_squared() > 0.1 and velocity.length() < 12.0:
		_stuck_timer += delta
		if _stuck_timer > 0.4:
			_escape_sign = -_escape_sign if randf() < 0.2 else _escape_sign
			avoidance_vector += desired_direction.orthogonal() * _escape_sign * 3.5
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
		
	var final_dir: Vector2 = desired_direction + avoidance_vector
	if final_dir.length_squared() < 0.0001:
		final_dir = desired_direction.orthogonal() * _escape_sign
		
	final_dir = final_dir.normalized()
	if is_nan(final_dir.x) or is_nan(final_dir.y):
		final_dir = Vector2.RIGHT
		
	return final_dir

# ------------------------------------------------------------------------------
# Perception Queries
# ------------------------------------------------------------------------------
func acquire_target() -> Node2D:
	var tanks: Array[Node] = get_tree().get_nodes_in_group("tanks")
	var closest_target: Node2D = null
	var closest_dist: float = sight_radius # Only within sight radius
	
	for node in tanks:
		if not is_instance_valid(node) or node == self or not (node is Node2D):
			continue
		var is_dead_val: bool = node.get("is_dead") if "is_dead" in node else false
		if is_dead_val:
			continue
		var d: float = global_position.distance_to((node as Node2D).global_position)
		if d < closest_dist:
			closest_dist = d
			closest_target = node as Node2D
			
	current_target = closest_target
	return closest_target

func has_line_of_sight(target: Variant) -> bool:
	if target == null:
		return false
	var target_pos: Vector2
	if target is Vector2:
		target_pos = target
	elif target is Node2D:
		if not is_instance_valid(target):
			return false
		target_pos = target.global_position
	else:
		return false
		
	if aim_raycast == null:
		return true
		
	aim_raycast.global_position = global_position
	aim_raycast.target_position = aim_raycast.to_local(target_pos)
	aim_raycast.force_raycast_update()
	
	if aim_raycast.is_colliding():
		var col = aim_raycast.get_collider()
		if target is Node2D and col == target:
			return true
		return false
	return true

func _find_best_powerup(prefer_health_or_shield: bool = true) -> Node2D:
	var powerups: Array[Node] = get_tree().get_nodes_in_group("powerups")
	var best_pu: Node2D = null
	var min_dist: float = sight_radius
	
	for pu in powerups:
		if not is_instance_valid(pu) or not (pu is Node2D):
			continue
		var collected: bool = pu.get("is_collected") if "is_collected" in pu else false
		if collected:
			continue
		var d: float = global_position.distance_to((pu as Node2D).global_position)
		if d < min_dist:
			var p_type: int = int(pu.get("powerup_type")) if "powerup_type" in pu else 0
			if prefer_health_or_shield:
				if p_type == 0 or p_type == 1: # Health or Shield
					min_dist = d
					best_pu = pu as Node2D
			else:
				min_dist = d
				best_pu = pu as Node2D
				
	return best_pu
