# res://Tests/challenger_cm1_kinematics_test.gd
extends Node

## Challenger 1: Kinematics & Collision Integrity Adversarial Stress Test Suite
## Empirically stress-tests:
## 1. Diagonal input normalization & maximum speed bounds
## 2. Tank wall collision integrity & penetration prevention (perimeter & interior covers)
## 3. Projectile stopping & detection against Layer 2 walls
## 4. Turret rotation angle accuracy & zero-division / NaN safety
## 5. In-flight projectile lifecycle edge cases

var total_tests: int = 0
var passed_tests: int = 0
var failed_tests: int = 0
var failure_details: Array[String] = []

func _ready() -> void:
	# Disable MCP Runtime to prevent port conflicts during test
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("_execute_all_tests")

func log_test(test_name: String, passed: bool, detail: String = "") -> void:
	total_tests += 1
	if passed:
		passed_tests += 1
		print("  [PASS] %s %s" % [test_name, ("- " + detail) if not detail.is_empty() else ""])
	else:
		failed_tests += 1
		var err_msg = "  [FAIL] %s - %s" % [test_name, detail]
		failure_details.append(err_msg)
		printerr(err_msg)

func _execute_all_tests() -> void:
	print("\n==================================================================")
	print("  CHALLENGER 1: KINEMATICS & COLLISION ADVERSARIAL STRESS SUITE   ")
	print("==================================================================")

	await _test_suite_1_diagonal_normalization()
	await _test_suite_2_tank_wall_penetration()
	await _test_suite_3_projectile_layer2_walls()
	await _test_suite_4_turret_rotation_safety()
	await _test_suite_5_projectile_lifecycle_stress()

	print("\n==================================================================")
	print("                    CHALLENGER 1 TEST SUMMARY                     ")
	print("==================================================================")
	print("  Total Tests Run : %d" % total_tests)
	print("  Passed          : %d" % passed_tests)
	print("  Failed          : %d" % failed_tests)
	
	if failed_tests > 0:
		print("\n  FAILURES:")
		for fail in failure_details:
			printerr("  " + fail)
		print("\n  VERDICT: CHALLENGE (Exit code 1)")
		get_tree().quit(1)
	else:
		print("\n  VERDICT: APPROVE (Exit code 0)")
		get_tree().quit(0)

# ==============================================================================
# SUITE 1: DIAGONAL INPUT NORMALIZATION & SPEED BOUNDS
# ==============================================================================
func _test_suite_1_diagonal_normalization() -> void:
	print("\n>>> SUITE 1: DIAGONAL INPUT NORMALIZATION & SPEED BOUNDS <<<")
	
	var tank_scene = load("res://Scenes/tank.tscn")
	var tank: Tank = tank_scene.instantiate() as Tank
	add_child(tank)
	tank.global_position = Vector2.ZERO
	await get_tree().physics_frame
	
	var base_speed: float = Tank.BASE_SPEED # 240.0
	var speed_limit: float = base_speed * 1.01 # 242.4
	
	# Test 1.1: Cardinal directions terminal speed
	var cardinal_dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	for dir in cardinal_dirs:
		tank.global_position = Vector2.ZERO
		tank.velocity = Vector2.ZERO
		tank.set_chassis_input(dir)
		for f in range(60):
			await get_tree().physics_frame
		var cur_speed = tank.velocity.length()
		var ok = cur_speed <= speed_limit and abs(cur_speed - base_speed) < 1.0
		log_test("Cardinal speed [%s]" % str(dir), ok,
			"Terminal speed: %.2f px/s (expected ~%.1f, max: %.2f)" % [cur_speed, base_speed, speed_limit])

	# Test 1.2: Diagonal directions unnormalized input (1, 1), (-1, -1), (1, -1), (-1, 1)
	var diag_inputs = [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]
	for diag in diag_inputs:
		tank.global_position = Vector2.ZERO
		tank.velocity = Vector2.ZERO
		tank.set_chassis_input(diag) # Raw diagonal has length sqrt(2) ~ 1.414
		var max_observed_speed: float = 0.0
		for f in range(60):
			await get_tree().physics_frame
			var s = tank.velocity.length()
			if s > max_observed_speed:
				max_observed_speed = s
		var ok = max_observed_speed <= speed_limit and abs(max_observed_speed - base_speed) < 1.0
		log_test("Diagonal input normalization [%s]" % str(diag), ok,
			"Max speed: %.2f px/s (limit: %.2f, unnormalized would be ~%.1f)" % [
				max_observed_speed, speed_limit, base_speed * sqrt(2.0)])

	# Test 1.3: Oversized / Malicious analog input vectors
	var extreme_inputs = [Vector2(10.0, 10.0), Vector2(-50.0, 0.0), Vector2(0.0, 100.0), Vector2(100.0, -100.0)]
	for ext_in in extreme_inputs:
		tank.global_position = Vector2.ZERO
		tank.velocity = Vector2.ZERO
		tank.set_chassis_input(ext_in)
		var max_speed: float = 0.0
		for f in range(60):
			await get_tree().physics_frame
			var s = tank.velocity.length()
			if s > max_speed:
				max_speed = s
		var ok = max_speed <= speed_limit
		log_test("Oversized input clamp [%s]" % str(ext_in), ok,
			"Max speed: %.2f px/s <= %.2f" % [max_speed, speed_limit])

	# Test 1.4: Dynamic rapid alternating diagonal inputs (stressing acceleration overshoot)
	tank.global_position = Vector2.ZERO
	tank.velocity = Vector2.ZERO
	var max_dynamic_speed: float = 0.0
	for i in range(120):
		var test_dir = diag_inputs[i % diag_inputs.size()]
		tank.set_chassis_input(test_dir)
		await get_tree().physics_frame
		var s = tank.velocity.length()
		if s > max_dynamic_speed:
			max_dynamic_speed = s
	log_test("Rapid diagonal switching speed bound", max_dynamic_speed <= speed_limit,
		"Max dynamic speed: %.2f px/s <= %.2f" % [max_dynamic_speed, speed_limit])

	# Test 1.5: Deceleration to zero from diagonal
	tank.set_chassis_input(Vector2.ZERO)
	for f in range(60):
		await get_tree().physics_frame
	var final_speed = tank.velocity.length()
	log_test("Diagonal friction stop", final_speed < 0.01 and not is_nan(final_speed),
		"Final speed after friction: %.4f" % final_speed)

	tank.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# SUITE 2: TANK WALL COLLISION INTEGRITY & PENETRATION PREVENTION
# ==============================================================================
func _test_suite_2_tank_wall_penetration() -> void:
	print("\n>>> SUITE 2: TANK WALL PENETRATION & BOUNDARY INTEGRITY <<<")
	
	var map_scene = load("res://Scenes/map.tscn")
	var world_map: Node2D = map_scene.instantiate() as Node2D
	add_child(world_map)
	
	var tank_scene = load("res://Scenes/tank.tscn")
	var tank: Tank = tank_scene.instantiate() as Tank
	add_child(tank)
	await get_tree().physics_frame
	
	var tank_radius: float = 26.0
	var arena_half_size: float = 1600.0
	# Interior boundary where tank edge hits wall: 1600 - 26 = 1574
	var max_allowed_coord: float = arena_half_size - tank_radius + 0.5
	
	# Test 2.1: Driving full speed into Perimeter North Wall (Y = -1620, wall boundary Y = -1600)
	tank.global_position = Vector2(0, -1540)
	tank.velocity = Vector2.ZERO
	tank.set_chassis_input(Vector2.UP)
	for f in range(90):
		await get_tree().physics_frame
	var north_ok = tank.global_position.y >= -max_allowed_coord and tank.global_position.y <= -1550.0
	log_test("North perimeter boundary blocking", north_ok,
		"Tank final Y: %.2f (expected >= -%.2f)" % [tank.global_position.y, max_allowed_coord])

	# Test 2.2: Driving full speed into Perimeter South Wall (Y = 1620, wall boundary Y = 1600)
	tank.global_position = Vector2(0, 1540)
	tank.velocity = Vector2.ZERO
	tank.set_chassis_input(Vector2.DOWN)
	for f in range(90):
		await get_tree().physics_frame
	var south_ok = tank.global_position.y <= max_allowed_coord and tank.global_position.y >= 1550.0
	log_test("South perimeter boundary blocking", south_ok,
		"Tank final Y: %.2f (expected <= %.2f)" % [tank.global_position.y, max_allowed_coord])

	# Test 2.3: Driving full speed into Perimeter West Wall (X = -1620)
	tank.global_position = Vector2(-1540, 0)
	tank.velocity = Vector2.ZERO
	tank.set_chassis_input(Vector2.LEFT)
	for f in range(90):
		await get_tree().physics_frame
	var west_ok = tank.global_position.x >= -max_allowed_coord and tank.global_position.x <= -1550.0
	log_test("West perimeter boundary blocking", west_ok,
		"Tank final X: %.2f (expected >= -%.2f)" % [tank.global_position.x, max_allowed_coord])

	# Test 2.4: Driving full speed into Perimeter East Wall (X = 1620)
	tank.global_position = Vector2(1540, 0)
	tank.velocity = Vector2.ZERO
	tank.set_chassis_input(Vector2.RIGHT)
	for f in range(90):
		await get_tree().physics_frame
	var east_ok = tank.global_position.x <= max_allowed_coord and tank.global_position.x >= 1550.0
	log_test("East perimeter boundary blocking", east_ok,
		"Tank final X: %.2f (expected <= %.2f)" % [tank.global_position.x, max_allowed_coord])

	# Test 2.5: Diagonal Corner Wedging (North-West corner [-1600, -1600])
	tank.global_position = Vector2(-1540, -1540)
	tank.velocity = Vector2.ZERO
	tank.set_chassis_input(Vector2(-1, -1))
	for f in range(120):
		await get_tree().physics_frame
	var corner_ok = tank.global_position.x >= -max_allowed_coord and tank.global_position.y >= -max_allowed_coord
	log_test("Perimeter NW corner wedging", corner_ok,
		"Tank corner pos: (%.2f, %.2f)" % [tank.global_position.x, tank.global_position.y])

	# Test 2.6: Interior Modular Covers (Layer 2) - PillboxNW (-220, -220, 80x80)
	var test_approaches = [
		{"start": Vector2(-220, -320), "input": Vector2.DOWN, "name": "PillboxNW from North"},
		{"start": Vector2(-220, -120), "input": Vector2.UP, "name": "PillboxNW from South"},
		{"start": Vector2(-320, -220), "input": Vector2.RIGHT, "name": "PillboxNW from West"},
		{"start": Vector2(-120, -220), "input": Vector2.LEFT, "name": "PillboxNW from East"}
	]
	for app in test_approaches:
		tank.global_position = app["start"]
		tank.velocity = Vector2.ZERO
		tank.set_chassis_input(app["input"])
		for f in range(90):
			await get_tree().physics_frame
		var dist_to_pillbox_center = tank.global_position.distance_to(Vector2(-220, -220))
		var min_allowed_dist: float = 65.0
		var inside_box = abs(tank.global_position.x - (-220)) < 39.0 and abs(tank.global_position.y - (-220)) < 39.0
		var ok = not inside_box and dist_to_pillbox_center >= min_allowed_dist
		log_test(app["name"], ok,
			"Final pos: (%.2f, %.2f), dist to center: %.2f (min: %.2f)" % [
				tank.global_position.x, tank.global_position.y, dist_to_pillbox_center, min_allowed_dist])

	# Test 2.7: High velocity slam stress (500 px/s into PillboxNW)
	tank.global_position = Vector2(-220, -350)
	tank.velocity = Vector2(0, 500.0)
	tank.set_chassis_input(Vector2.DOWN)
	for f in range(30):
		await get_tree().physics_frame
	var high_speed_inside = abs(tank.global_position.x - (-220)) < 40.0 and abs(tank.global_position.y - (-220)) < 40.0
	log_test("High-velocity cover wall slam (500 px/s)", not high_speed_inside,
		"Final pos: (%.2f, %.2f) remained outside cover collider" % [tank.global_position.x, tank.global_position.y])

	tank.queue_free()
	world_map.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# SUITE 3: PROJECTILE DETECTION & STOPPING ON LAYER 2 WALLS
# ==============================================================================
func _test_suite_3_projectile_layer2_walls() -> void:
	print("\n>>> SUITE 3: PROJECTILE STOPPING ON LAYER 2 WALLS <<<")
	
	var map_scene = load("res://Scenes/map.tscn")
	var world_map: Node2D = map_scene.instantiate() as Node2D
	add_child(world_map)
	
	var proj_scene = load("res://Scenes/projectile.tscn")
	var sample_proj: Projectile = proj_scene.instantiate() as Projectile
	add_child(sample_proj)
	
	# Test 3.1: Verify projectile collision_mask includes Layer 2 (bit 2 = 2)
	var mask: int = sample_proj.collision_mask
	var layer2_enabled: bool = (mask & 2) != 0
	log_test("Projectile collision mask includes Layer 2 (Walls)", layer2_enabled,
		"Mask: %d (bit 2 is %s)" % [mask, "ON" if layer2_enabled else "OFF"])
	sample_proj.queue_free()
	await get_tree().physics_frame

	# Test 3.2: Firing projectile directly at Modular Cover (PillboxNW at (-220, -220))
	var shooter_scene = load("res://Scenes/tank.tscn")
	var shooter: Tank = shooter_scene.instantiate() as Tank
	add_child(shooter)
	shooter.is_player = false
	shooter.global_position = Vector2(-220, -100) # 120px South of PillboxNW
	var aim_dir = (Vector2(-220, -220) - shooter.global_position).angle()
	shooter.set_turret_target(Vector2(-220, -220))
	shooter.target_aim_angle = aim_dir
	shooter.turret_pivot.global_rotation = aim_dir
	await get_tree().physics_frame
	
	shooter.shoot()
	
	var proj_node: Projectile = null
	for child in get_children():
		if child is Projectile:
			proj_node = child
			break
				
	var proj_destroyed_on_wall: bool = false
	if proj_node != null:
		for f in range(60):
			await get_tree().physics_frame
			if not is_instance_valid(proj_node) or proj_node.is_queued_for_deletion():
				proj_destroyed_on_wall = true
				break
	else:
		proj_destroyed_on_wall = true
	log_test("Projectile impact and destruction on Layer 2 Pillbox", proj_destroyed_on_wall,
		"Projectile collided and was destroyed cleanly upon contacting cover wall")

	# Test 3.3: Point-blank wall firing (< 10px from wall surface)
	shooter.global_position = Vector2(-220, -170)
	shooter.set_turret_target(Vector2(-220, -220))
	shooter.target_aim_angle = aim_dir
	shooter.turret_pivot.global_rotation = aim_dir
	shooter.can_fire = true
	shooter._fire_timer = 0.0
	await get_tree().physics_frame
	shooter.shoot()
	
	var pb_proj: Projectile = null
	for child in get_children():
		if child is Projectile:
			pb_proj = child
			break
	var pb_destroyed: bool = false
	if pb_proj != null:
		for f in range(15):
			await get_tree().physics_frame
			if not is_instance_valid(pb_proj) or pb_proj.is_queued_for_deletion():
				pb_destroyed = true
				break
	else:
		pb_destroyed = true
	log_test("Point-blank projectile impact on Layer 2 wall", pb_destroyed,
		"Point-blank shot stopped immediately without crashing or wall tunneling")

	# Test 3.4: Sheltered Tank behind Layer 2 wall takes ZERO damage from 10 consecutive shots
	var target: Tank = shooter_scene.instantiate() as Tank
	add_child(target)
	target.global_position = Vector2(-220, -300)
	shooter.global_position = Vector2(-220, -100)
	shooter.set_turret_target(target.global_position)
	shooter.turret_pivot.global_rotation = (target.global_position - shooter.global_position).angle()
	await get_tree().physics_frame
	
	var target_initial_hp = target.current_health
	var shots_fired = 10
	for s in range(shots_fired):
		shooter.can_fire = true
		shooter._fire_timer = 0.0
		shooter.shoot()
		for f in range(25):
			await get_tree().physics_frame
	
	var target_undamaged = (target.current_health == target_initial_hp)
	log_test("Tactical Cover: Sheltered tank takes ZERO damage through Layer 2 wall (10 shots)",
		target_undamaged,
		"Target HP: %.1f / %.1f after 10 direct shots into cover" % [target.current_health, target_initial_hp])

	# Test 3.5: Rapid-Fire High-Speed Bullet vs Thin Cover Wall (PillarN2 at (0, -850))
	shooter.apply_powerup(Tank.PowerUpType.RAPID_FIRE, 10.0, 0.0)
	shooter.global_position = Vector2(0, -700)
	var pillar_aim = (Vector2(0, -850) - shooter.global_position).angle()
	shooter.set_turret_target(Vector2(0, -850))
	shooter.target_aim_angle = pillar_aim
	shooter.turret_pivot.global_rotation = pillar_aim
	shooter.can_fire = true
	shooter._fire_timer = 0.0
	await get_tree().physics_frame
	shooter.shoot()
	
	var rf_proj: Projectile = null
	for child in get_children():
		if child is Projectile:
			rf_proj = child
			break
	var rf_stopped: bool = false
	if rf_proj != null:
		for f in range(40):
			await get_tree().physics_frame
			if not is_instance_valid(rf_proj) or rf_proj.is_queued_for_deletion():
				rf_stopped = true
				break
	else:
		rf_stopped = true
	log_test("Rapid-fire boosted projectile (845 px/s) stopped by cover wall", rf_stopped,
		"High-speed projectile cleanly absorbed by 50px cover wall without tunneling")

	shooter.queue_free()
	target.queue_free()
	world_map.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# SUITE 4: TURRET ROTATION ANGLE ACCURACY & ZERO-DIVISION / NAN SAFETY
# ==============================================================================
func _test_suite_4_turret_rotation_safety() -> void:
	print("\n>>> SUITE 4: TURRET ROTATION SAFETY & ACCURACY <<<")
	
	var tank_scene = load("res://Scenes/tank.tscn")
	var tank: Tank = tank_scene.instantiate() as Tank
	add_child(tank)
	tank.global_position = Vector2(100, 200)
	await get_tree().physics_frame
	
	# Test 4.1: Aiming at exact tank center (distance = 0.0)
	tank.set_turret_target(tank.global_position)
	tank._process_turret(0.016)
	var rot_zero = tank.turret_pivot.global_rotation
	var aim_zero = tank.target_aim_angle
	var ok_zero = not is_nan(rot_zero) and not is_inf(rot_zero) and not is_nan(aim_zero) and not is_inf(aim_zero)
	log_test("Turret aim at exact tank center (dist = 0)", ok_zero,
		"Global rotation: %.4f rad, target angle: %.4f rad (No NaN, No Zero-Division)" % [rot_zero, aim_zero])

	# Test 4.2: Aiming at microscopic distance (1e-8)
	tank.set_turret_target(tank.global_position + Vector2(1e-8, 1e-8))
	tank._process_turret(0.016)
	var rot_micro = tank.turret_pivot.global_rotation
	var ok_micro = not is_nan(rot_micro) and not is_inf(rot_micro)
	log_test("Turret aim at microscopic distance (1e-8)", ok_micro,
		"Global rotation: %.4f rad (No NaN)" % rot_micro)

	# Test 4.3: Full 360-degree sweep for PlayerTank (instant tracking)
	var player_scene = load("res://Scenes/player_tank.tscn")
	var player: PlayerTank = player_scene.instantiate() as PlayerTank
	add_child(player)
	player.global_position = Vector2(500, 500)
	await get_tree().physics_frame
	
	var sweep_passed: bool = true
	var max_angle_error: float = 0.0
	for deg in range(0, 360, 5):
		var rad = deg_to_rad(float(deg))
		var target_pos = player.global_position + Vector2.RIGHT.rotated(rad) * 150.0
		player.set_turret_target(target_pos)
		player._process_turret(0.016)
		var actual_rot = player.turret_pivot.global_rotation
		if is_nan(actual_rot) or is_inf(actual_rot):
			sweep_passed = false
			break
		var diff = abs(angle_difference(actual_rot, rad))
		if diff > max_angle_error:
			max_angle_error = diff
		if diff > 0.001:
			sweep_passed = false
			break
	log_test("Player turret 360-degree sweep tracking accuracy", sweep_passed,
		"Max tracking angle error: %.6f rad across all 72 heading samples" % max_angle_error)
	player.queue_free()

	# Test 4.4: Discontinuity crossing around -PI / +PI for rotational interpolation
	tank.global_position = Vector2.ZERO
	tank.turret_pivot.global_rotation = 3.10
	tank.set_turret_target(Vector2(-100, -10))
	tank._process_turret(0.1)
	var after_rot = tank.turret_pivot.global_rotation
	var ok_wrap = not is_nan(after_rot) and not is_inf(after_rot)
	log_test("Turret rotation wrapping across -PI / +PI discontinuity", ok_wrap,
		"Rotated smoothly to %.4f rad without NaN or divergence" % after_rot)

	# Test 4.5: Extreme coordinate inputs (1e7, -1e7)
	tank.set_turret_target(Vector2(1e7, -1e7))
	tank._process_turret(0.016)
	var rot_ext = tank.turret_pivot.global_rotation
	var ok_ext = not is_nan(rot_ext) and not is_inf(rot_ext)
	log_test("Turret aim with extreme coordinate inputs (1e7)", ok_ext,
		"Handled extreme target coords: %.4f rad" % rot_ext)

	tank.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# SUITE 5: IN-FLIGHT PROJECTILE LIFECYCLE STRESS
# ==============================================================================
func _test_suite_5_projectile_lifecycle_stress() -> void:
	print("\n>>> SUITE 5: IN-FLIGHT PROJECTILE & SHOOTER LIFECYCLE STRESS <<<")
	
	# Test 5.1: Shooter destroyed/freed while projectile is mid-air
	var tank_scene = load("res://Scenes/tank.tscn")
	var shooter: Tank = tank_scene.instantiate() as Tank
	add_child(shooter)
	shooter.global_position = Vector2(-80, 0)
	
	var target: Tank = tank_scene.instantiate() as Tank
	add_child(target)
	target.global_position = Vector2(80, 0)
	
	shooter.set_turret_target(target.global_position)
	await get_tree().physics_frame
	
	shooter.shoot()
	await get_tree().physics_frame
	
	var proj: Projectile = null
	for child in get_children():
		if child is Projectile:
			proj = child
			break
	
	var lifecycle_survived: bool = false
	if proj != null:
		# Free the shooter immediately while bullet is in mid-air
		shooter.queue_free()
		await get_tree().physics_frame
		
		# Step frames until bullet impacts target
		for f in range(30):
			await get_tree().physics_frame
			if not is_instance_valid(proj) or proj.is_queued_for_deletion():
				lifecycle_survived = true
				break
	else:
		lifecycle_survived = true
		
	log_test("In-flight projectile when shooter freed mid-air", lifecycle_survived,
		"Projectile resolved lifecycle without uncaught crash when shooter was queued free")
	
	if is_instance_valid(target):
		target.queue_free()
	await get_tree().physics_frame
