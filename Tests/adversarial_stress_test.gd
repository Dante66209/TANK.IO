# res://Tests/adversarial_stress_test.gd
extends Node

func _ready() -> void:
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED

	print("\n--- ADVERSARIAL STRESS TEST START ---")
	call_deferred("_run_stress_tests")

func _run_stress_tests() -> void:
	await get_tree().physics_frame
	
	# Test 1: Mid-air projectile whose shooter was deleted
	print("[Stress 1] Testing projectile impact after shooter is freed...")
	var shooter: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	var victim: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(shooter)
	add_child(victim)
	shooter.global_position = Vector2(0, 0)
	victim.global_position = Vector2(100, 0)

	var proj_scene: PackedScene = load("res://Scenes/projectile.tscn")
	var proj: Projectile = proj_scene.instantiate() as Projectile
	add_child(proj)
	proj.setup(shooter, Vector2(1, 0), 1000.0, 25.0)
	proj.global_position = Vector2(50, 0)

	# Now delete the shooter before projectile impacts victim
	shooter.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Projectile moves into victim
	proj.global_position = Vector2(98, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("[Stress 1] Projectile impact resolved. Victim HP: %f" % victim.current_health)
	
	# Test 2: Rapid concurrent damage (100 simultaneous hits in 1 frame)
	print("[Stress 2] Testing 100 simultaneous hits in a single frame...")
	var dummy: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(dummy)
	var attacker: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(attacker)
	
	for _i in range(100):
		dummy.take_damage(2.0, attacker, false)
		
	print("[Stress 2] 100 hits resolved. Dummy HP: %f, is_dead: %s, attacker kills: %d, score: %d" % [
		dummy.current_health, str(dummy.is_dead), attacker.kills, attacker.score
	])
	
	# Test 3: Safe spawn with all spawn points surrounded
	print("[Stress 3] Testing safe spawn resolution when threats are spread across map...")
	var map: WorldMap = load("res://Scenes/map.tscn").instantiate() as WorldMap
	add_child(map)
	var spawn_points = map.get_spawn_positions()
	
	# Place 7 enemies at 7 spawn points
	var enemy_tanks: Array[Tank] = []
	for i in range(7):
		var en: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
		add_child(en)
		en.global_position = spawn_points[i]
		enemy_tanks.append(en)
		
	var respawner: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(respawner)
	var chosen_pt = respawner.select_safe_spawn_point()
	print("[Stress 3] Safe point chosen with 7/8 points occupied: %s (Expected unoccupied point: %s)" % [
		str(chosen_pt), str(spawn_points[7])
	])
	
	# Test 4: Invulnerability absorbing multiple projectile salvos
	print("[Stress 4] Testing invulnerability against projectile salvos...")
	respawner.respawn(chosen_pt)
	for _i in range(10):
		respawner.take_damage(25.0, attacker, false)
	print("[Stress 4] After 10 salvos during invulnerability: HP = %f" % respawner.current_health)

	print("--- ADVERSARIAL STRESS TEST COMPLETED SUCCESSFULLY ---")
	get_tree().quit(0)
