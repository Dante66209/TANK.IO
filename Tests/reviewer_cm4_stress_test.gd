# res://Tests/reviewer_cm4_stress_test.gd
extends "res://Tests/test_base.gd"

## Reviewer 1 (CM4) Adversarial Stress Test Suite
## Independent verification of edge cases, adversarial inputs, and integrity constraints.

func _ready() -> void:
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("_run_all_tests")

func _run_all_tests() -> void:
	print("\n================================================================================")
	print("       REVIEWER 1 (CM4): ADVERSARIAL STRESS & INTEGRITY VERIFICATION SUITE       ")
	print("================================================================================")
	
	var tests := [
		"test_adv_bot_corner_deadlock_and_nan_resilience",
		"test_adv_predictive_aim_math_and_lead_vector",
		"test_adv_barrel_aoe_wall_penetration_vs_projectile_blocking",
		"test_adv_powerup_stat_stacking_and_spillover_absorption",
		"test_adv_match_manager_complex_scoring_and_tie_breaking",
		"test_adv_safe_respawn_threat_filtering",
		"test_adv_fog_of_war_culling_transitions"
	]
	
	var total_passed := 0
	var total_failed := 0
	
	for t_name in tests:
		failed_assertions = 0
		passed_assertions = 0
		failure_messages.clear()
		test_name = t_name
		setup()
		print("\n>>> RUNNING: %s <<<" % t_name)
		await call(t_name)
		teardown()
		if failed_assertions == 0:
			total_passed += 1
			print("  [PASS] %s" % t_name)
		else:
			total_failed += 1
			print("  [FAIL] %s - Errors: %s" % [t_name, str(failure_messages)])
			
	print("\n================================================================================")
	print("  TOTAL TESTS: %d | PASSED: %d | FAILED: %d" % [tests.size(), total_passed, total_failed])
	print("================================================================================")
	
	if total_failed == 0:
		print("  VERDICT: ADVERSARIAL STRESS SUITE PASSED (EXIT 0)")
		get_tree().quit(0)
	else:
		printerr("  VERDICT: ADVERSARIAL STRESS SUITE FAILED (EXIT 1)")
		get_tree().quit(1)

# ------------------------------------------------------------------------------
# Test 1: Bot Deadlock & NaN Resilience in Confined Wall Box
# ------------------------------------------------------------------------------
func test_adv_bot_corner_deadlock_and_nan_resilience() -> void:
	var bot: Node = spawn_scene("res://Scenes/bot_tank.tscn")
	if not assert_not_null(bot, "Bot tank must instantiate"): return
	bot.global_position = Vector2(0, 0)
	
	# Create 4 bounding walls forming a tiny 80x80 box
	var box_walls := StaticBody2D.new()
	box_walls.collision_layer = 3 # Layers 1 & 2
	track_node(box_walls)
	add_child(box_walls)
	
	var offsets := [Vector2(0, -40), Vector2(0, 40), Vector2(-40, 0), Vector2(40, 0)]
	var sizes := [Vector2(100, 10), Vector2(100, 10), Vector2(10, 100), Vector2(10, 100)]
	for i in range(4):
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = sizes[i]
		col.shape = rect
		col.position = offsets[i]
		box_walls.add_child(col)
		
	# Force bot into WANDER state and step for 60 frames in confined box
	if "bot_state" in bot:
		bot.bot_state = 0 # WANDER
	if bot.has_method("set_chassis_input"):
		bot.set_chassis_input(Vector2(1, 1).normalized())
		
	for _f in range(60):
		await wait_physics_frames(1)
		# Assert bot coordinates never become NaN or Inf
		assert_false(is_nan(bot.global_position.x) or is_nan(bot.global_position.y), "Bot position must never evaluate to NaN")
		assert_false(is_inf(bot.global_position.x) or is_inf(bot.global_position.y), "Bot position must never evaluate to Inf")
		if "velocity" in bot:
			assert_false(is_nan(bot.velocity.x) or is_nan(bot.velocity.y), "Bot velocity must never evaluate to NaN")

# ------------------------------------------------------------------------------
# Test 2: 1st-Order Predictive Lead Calculation Accuracy
# ------------------------------------------------------------------------------
func test_adv_predictive_aim_math_and_lead_vector() -> void:
	var bot: Node = spawn_scene("res://Scenes/bot_tank.tscn")
	var target: Node = spawn_scene("res://Scenes/player_tank.tscn")
	if not assert_not_null(bot, "Bot must exist"): return
	if not assert_not_null(target, "Target must exist"): return
	
	bot.global_position = Vector2(0, 0)
	target.global_position = Vector2(300, 0)
	target.set("velocity", Vector2(0, 200)) # Target moving North-South at 200 px/s
	
	var bullet_speed: float = bot.get("bullet_speed") if "bullet_speed" in bot else 650.0
	var dist: float = 300.0
	var expected_t_impact: float = dist / bullet_speed
	var expected_aim_pos: Vector2 = target.global_position + Vector2(0, 200) * expected_t_impact
	
	# Process one state combat frame
	bot.set("current_target", target)
	if bot.has_method("_state_combat"):
		bot.call("_state_combat", 0.016)
		
	var actual_turret_target: Vector2 = bot.get("turret_target_pos") if "turret_target_pos" in bot else Vector2.ZERO
	assert_approx_equal(actual_turret_target.x, expected_aim_pos.x, 5.0, "Predictive lead X coordinate matches intercept")
	assert_approx_equal(actual_turret_target.y, expected_aim_pos.y, 5.0, "Predictive lead Y coordinate matches intercept")

# ------------------------------------------------------------------------------
# Test 3: Barrel AoE Wall Penetration vs Direct Projectile Blocking
# ------------------------------------------------------------------------------
func test_adv_barrel_aoe_wall_penetration_vs_projectile_blocking() -> void:
	# Place Layer 2 Wall at X = 50
	var wall := StaticBody2D.new()
	wall.collision_layer = 2 # Walls
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	col.shape = rect
	wall.add_child(col)
	wall.global_position = Vector2(50, 0)
	track_node(wall)
	add_child(wall)
	
	# Place Barrel at (0, 0)
	var barrel := spawn_scene("res://Scenes/barrel.tscn")
	if not assert_not_null(barrel, "Barrel scene must exist"): return
	barrel.global_position = Vector2(0, 0)
	
	# Place Tank at (100, 0) behind the wall (distance 100px < 200px blast radius)
	var tank := spawn_scene("res://Scenes/player_tank.tscn")
	if not assert_not_null(tank, "Tank scene must exist"): return
	tank.global_position = Vector2(100, 0)
	tank.set("current_health", 100.0)
	
	# Step physics frames to ensure spatial partitioning registers
	await wait_physics_frames(5)
	
	# Detonate barrel
	if barrel.has_method("explode"):
		barrel.explode()
	await wait_physics_frames(2)
	
	var hp_after: float = tank.get("current_health") if "current_health" in tank else 100.0
	assert_true(hp_after < 100.0, "Barrel AoE blast wave penetrates Layer 2 wall to damage sheltered tank (HP: %f)" % hp_after)
	
	# Now test that direct projectile DOES get blocked by wall
	var shooter := spawn_scene("res://Scenes/player_tank.tscn")
	shooter.global_position = Vector2(0, 0)
	var proj_scene: PackedScene = load("res://Scenes/projectile.tscn")
	var proj: Area2D = proj_scene.instantiate() as Area2D
	track_node(proj)
	add_child(proj)
	proj.global_position = Vector2(10, 0)
	proj.setup(shooter, Vector2.RIGHT, 650.0, 25.0)
	
	# Step frames for projectile to collide with wall
	await wait_physics_frames(10)
	# Projectile must have collided with wall and been freed/destroyed
	assert_true(not is_instance_valid(proj) or proj.get("_is_destroyed") == true, "Direct projectile is stopped by Layer 2 wall")

# ------------------------------------------------------------------------------
# Test 4: Power-Up Stat Stacking & Spillover Damage Absorption
# ------------------------------------------------------------------------------
func test_adv_powerup_stat_stacking_and_spillover_absorption() -> void:
	var tank: Node = spawn_scene("res://Scenes/player_tank.tscn")
	if not assert_not_null(tank, "Tank must exist"): return
	tank.set("current_health", 60.0)
	
	# Apply Health (+40 -> 100)
	tank.apply_powerup(0, 0.0, 40.0)
	assert_equal(tank.get("current_health"), 100.0, "Health powerup restores to 100 HP")
	
	# Apply Shield (+50)
	tank.apply_powerup(1, 10.0, 50.0)
	assert_equal(tank.get("shield"), 50.0, "Shield powerup grants 50 shield points")
	
	# Apply Rapid-Fire
	tank.apply_powerup(2, 8.0, 0.6)
	var expected_cd: float = 0.35 * 0.4
	var expected_spd: float = 650.0 * 1.3
	assert_approx_equal(tank.get("fire_cooldown"), expected_cd, 0.01, "Rapid fire reduces fire cooldown by 60%")
	assert_approx_equal(tank.get("bullet_speed"), expected_spd, 1.0, "Rapid fire boosts bullet speed by 30%")
	
	# Test Spillover: Deal 70 damage. 50 should be absorbed by shield, 20 from health (100 -> 80 HP)
	tank.take_damage(70.0, null, false)
	assert_equal(tank.get("shield"), 0.0, "Shield completely depleted after absorbing 50 damage")
	assert_equal(tank.get("current_health"), 80.0, "Spillover damage of 20 correctly deducted from HP (leaving 80 HP)")

# ------------------------------------------------------------------------------
# Test 5: MatchManager Complex Scoring, Kill Streaks, and Tie-Breaking
# ------------------------------------------------------------------------------
func test_adv_match_manager_complex_scoring_and_tie_breaking() -> void:
	var mm_script = load_script("res://Scripts/Core/match_manager.gd")
	if not assert_not_null(mm_script, "MatchManager script must exist"): return
	var mm = mm_script.new()
	track_node(mm)
	add_child(mm)
	
	var tank_a := Node2D.new()
	tank_a.name = "Tank_A"
	track_node(tank_a)
	add_child(tank_a)
	
	var tank_b := Node2D.new()
	tank_b.name = "Tank_B"
	track_node(tank_b)
	add_child(tank_b)
	
	var tank_c := Node2D.new()
	tank_c.name = "Tank_C"
	track_node(tank_c)
	add_child(tank_c)
	
	mm.register_combatant(tank_a, "Tank A", true)
	mm.register_combatant(tank_b, "Tank B", false)
	mm.register_combatant(tank_c, "Tank C", false)
	
	mm.start_match(180.0)
	
	# Tank A gets 1 normal kill (+100)
	mm.record_kill(tank_b, tank_a, false)
	var stats_a: Dictionary = mm.get_combatant_stats(tank_a)
	assert_equal(stats_a["score"], 100, "Kill 1 grants 100 points")
	assert_equal(stats_a["streak"], 1, "Streak is 1")
	
	# Tank A gets kill 2 (+100 -> 200)
	mm.record_kill(tank_c, tank_a, false)
	stats_a = mm.get_combatant_stats(tank_a)
	assert_equal(stats_a["score"], 200, "Kill 2 grants 100 points")
	assert_equal(stats_a["streak"], 2, "Streak is 2")
	
	# Tank A gets kill 3 (+100 + 50 streak bonus -> 350)
	mm.record_kill(tank_b, tank_a, false)
	stats_a = mm.get_combatant_stats(tank_a)
	assert_equal(stats_a["score"], 350, "Kill 3 triggers 3-streak bonus (+50 pts, total 350)")
	assert_equal(stats_a["streak"], 3, "Streak is 3")
	
	# Tank A gets barrel kill (+100 + 150 barrel bonus = 250 -> 600)
	mm.record_kill(tank_c, tank_a, true)
	stats_a = mm.get_combatant_stats(tank_a)
	assert_equal(stats_a["score"], 600, "Barrel kill grants +150 bonus (total +250, new score 600)")
	assert_equal(stats_a["barrel_kills"], 1, "Barrel kills incremented")
	
	# Tank B kills Tank A: resets Tank A streak to 0, grants Tank B 100 pts
	mm.record_kill(tank_a, tank_b, false)
	stats_a = mm.get_combatant_stats(tank_a)
	assert_equal(stats_a["streak"], 0, "Tank A streak reset to 0 upon death")
	assert_equal(stats_a["deaths"], 1, "Tank A deaths is 1")
	
	# Test Tie Breaking: Setup equal scores between Tank B and Tank C (100 pts each)
	# But Tank B has 1 kill, Tank C has 0 kills, 10 barrel score
	mm.record_barrel_destroyed(tank_c) # +20
	mm.record_barrel_destroyed(tank_c) # +20
	mm.record_barrel_destroyed(tank_c) # +20
	mm.record_barrel_destroyed(tank_c) # +20
	mm.record_barrel_destroyed(tank_c) # +20 -> 100 pts, 0 kills
	
	var lb: Array = mm.get_leaderboard()
	assert_equal(lb[0]["name"], "Tank A", "Leaderboard rank 1 is Tank A with 600 pts")
	assert_equal(lb[1]["name"], "Tank B", "Leaderboard rank 2 is Tank B (100 pts, 1 kill over 0 kills)")
	assert_equal(lb[2]["name"], "Tank C", "Leaderboard rank 3 is Tank C (100 pts, 0 kills)")

# ------------------------------------------------------------------------------
# Test 6: Safe Respawn Max-Min Threat Filtering
# ------------------------------------------------------------------------------
func test_adv_safe_respawn_threat_filtering() -> void:
	var sm_script = load_script("res://Scripts/Core/spawn_manager.gd")
	if not assert_not_null(sm_script, "SpawnManager must exist"): return
	var sm = sm_script.new()
	track_node(sm)
	add_child(sm)
	
	# 8 Default spawn points:
	# (-950, -950), (950, -950), (-950, 950), (950, 950),
	# (0, -800), (0, 800), (-800, 0), (800, 0)
	
	# Crowd 7 spawn points with active enemy tanks
	var enemy_positions := [
		Vector2(-950, -950), Vector2(950, -950),
		Vector2(-950, 950), Vector2(0, -800),
		Vector2(0, 800), Vector2(-800, 0), Vector2(800, 0)
	]
	var dummy_script := GDScript.new()
	dummy_script.source_code = "extends CharacterBody2D\nvar is_dead: bool = false\n"
	dummy_script.reload()
	
	var active_enemies: Array[Node] = []
	for pos in enemy_positions:
		var dummy := CharacterBody2D.new()
		dummy.set_script(dummy_script)
		dummy.global_position = pos
		dummy.is_dead = false
		active_enemies.append(dummy)
		track_node(dummy)
		add_child(dummy)
		
	# Also add a dead enemy at the 8th point (950, 950)
	var dead_tank := CharacterBody2D.new()
	dead_tank.set_script(dummy_script)
	dead_tank.global_position = Vector2(950, 950)
	dead_tank.is_dead = true
	active_enemies.append(dead_tank)
	track_node(dead_tank)
	add_child(dead_tank)
	
	# The safe spawn selection must pick (950, 950) because dead tanks are ignored
	var chosen_pt: Vector2 = sm.select_safe_spawn_point(active_enemies)
	assert_vector_approx(chosen_pt, Vector2(950, 950), 1.0, "Safe respawn selects uncrowded point (950, 950), correctly ignoring dead enemy")

# ------------------------------------------------------------------------------
# Test 7: Fog of War Culling Transitions
# ------------------------------------------------------------------------------
func test_adv_fog_of_war_culling_transitions() -> void:
	var fow_script = load_script("res://Scripts/World/fog_of_war.gd")
	if not assert_not_null(fow_script, "FogOfWar must exist"): return
	var fow = fow_script.new()
	track_node(fow)
	add_child(fow)
	
	var player := spawn_scene("res://Scenes/player_tank.tscn")
	player.global_position = Vector2(0, 0)
	fow.player_tank = player
	
	var enemy := spawn_scene("res://Scenes/bot_tank.tscn")
	enemy.global_position = Vector2(600, 0) # Outside 450px
	
	await wait_process_frames(2)
	assert_false(enemy.get("is_in_sight"), "Enemy at 600px is culled out of sight (is_in_sight = false)")
	
	# Move enemy into sight (300px)
	enemy.global_position = Vector2(300, 0)
	await wait_process_frames(2)
	assert_true(enemy.get("is_in_sight"), "Enemy at 300px is revealed (is_in_sight = true)")
