# res://Tests/challenger_cm1_2_harness.gd
extends Node

## Challenger 2 Verification Harness: Combat Damage, Elimination & Safe Respawn
## Milestone: Compound Milestone 1 (CM1)

var passed_count: int = 0
var failed_count: int = 0
var current_test_name: String = ""

func _ready() -> void:
	# Disable background MCP server if present
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED

	print("\n================================================================================")
	print("  CHALLENGER 2: COMBAT DAMAGE, ELIMINATION & SAFE RESPAWN VERIFICATION HARNESS  ")
	print("================================================================================")

	call_deferred("_run_all_challenger_tests")

func assert_true(cond: bool, msg: String) -> bool:
	if cond:
		passed_count += 1
		return true
	else:
		failed_count += 1
		printerr("  [FAIL] %s: %s" % [current_test_name, msg])
		return false

func assert_equal(val, expected, msg: String) -> bool:
	if val == expected:
		passed_count += 1
		return true
	else:
		failed_count += 1
		printerr("  [FAIL] %s: %s (Expected '%s', got '%s')" % [current_test_name, msg, str(expected), str(val)])
		return false

func assert_approx(val: float, expected: float, tolerance: float, msg: String) -> bool:
	if abs(val - expected) <= tolerance:
		passed_count += 1
		return true
	else:
		failed_count += 1
		printerr("  [FAIL] %s: %s (Expected approx %f, got %f, tolerance %f)" % [current_test_name, msg, expected, val, tolerance])
		return false

func _run_all_challenger_tests() -> void:
	await get_tree().physics_frame
	
	await test_group_1_overkill_damage_clamping()
	await test_group_2_shield_absorption()
	await test_group_3_elimination_state_and_timer()
	await test_group_4_attacker_scoring()
	await test_group_5_safe_respawn_and_invulnerability()
	
	print("\n================================================================================")
	print("                         CHALLENGER TEST RESULTS                                ")
	print("================================================================================")
	print("  Passed Assertions: %d" % passed_count)
	print("  Failed Assertions: %d" % failed_count)
	print("================================================================================")
	
	if failed_count == 0:
		print("  VERDICT: ALL CHALLENGER TESTS PASSED (EXIT CODE 0)\n")
		get_tree().quit(0)
	else:
		printerr("  VERDICT: CHALLENGER TESTS FAILED (EXIT CODE 1)\n")
		get_tree().quit(1)

# ==============================================================================
# GROUP 1: OVERKILL DAMAGE CLAMPING
# ==============================================================================
func test_group_1_overkill_damage_clamping() -> void:
	print("\n--- GROUP 1: OVERKILL DAMAGE CLAMPING ---")
	
	# 1.1 Standard Overkill (150 damage vs 100 HP)
	current_test_name = "T1.1_standard_overkill"
	var tank1: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank1)
	tank1.take_damage(150.0, null, false)
	assert_equal(tank1.current_health, 0.0, "HP must clamp to 0.0 on 150 damage")
	assert_true(tank1.is_dead, "Tank must be marked dead")
	tank1.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

	# 1.2 Extreme Overkill (1,000,000 damage)
	current_test_name = "T1.2_extreme_overkill_1e6"
	var tank2: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank2)
	tank2.take_damage(1000000.0, null, false)
	assert_equal(tank2.current_health, 0.0, "HP must not be negative on 1,000,000 damage")
	assert_false(is_nan(tank2.current_health), "HP must not be NaN")
	assert_false(is_inf(tank2.current_health), "HP must not be Inf")
	tank2.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

	# 1.3 Astronomical Overkill (1e20 damage)
	current_test_name = "T1.3_astronomical_overkill_1e20"
	var tank3: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank3)
	tank3.take_damage(1e20, null, false)
	assert_equal(tank3.current_health, 0.0, "HP must clamp to 0.0 under 1e20 damage")
	tank3.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

	# 1.4 Fractional Precision Overkill
	current_test_name = "T1.4_fractional_overkill_precision"
	var tank4: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank4)
	tank4.take_damage(99.999, null, false)
	assert_approx(tank4.current_health, 0.001, 0.0001, "HP must retain fractional remainder 0.001")
	assert_false(tank4.is_dead, "Tank must remain alive with 0.001 HP")
	tank4.take_damage(0.002, null, false)
	assert_equal(tank4.current_health, 0.0, "HP must clamp cleanly to 0.0 from fractional overkill")
	assert_true(tank4.is_dead, "Tank must be eliminated")
	tank4.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

	# 1.5 Repeated Damage at Zero HP (Dead state immunity)
	current_test_name = "T1.5_repeated_damage_while_dead"
	var tank5: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank5)
	tank5.take_damage(100.0, null, false)
	var initial_deaths = tank5.deaths
	tank5.take_damage(500.0, null, false)
	tank5.take_damage(1000.0, null, false)
	assert_equal(tank5.current_health, 0.0, "HP must remain 0.0 on subsequent hits while dead")
	assert_equal(tank5.deaths, initial_deaths, "Deaths count must not re-increment on repeated hits while dead")
	tank5.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

# ==============================================================================
# GROUP 2: SHIELD ABSORPTION
# ==============================================================================
func test_group_2_shield_absorption() -> void:
	print("\n--- GROUP 2: SHIELD ABSORPTION ---")

	# 2.1 Sub-shield damage absorption (HP untouched)
	current_test_name = "T2.1_sub_shield_absorption"
	var tank: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank)
	tank.apply_powerup(Tank.PowerUpType.SHIELD, 10.0, 50.0)
	assert_equal(tank.shield, 50.0, "Shield should be initialized to 50.0")
	assert_equal(tank.current_health, 100.0, "Health should start at 100.0")
	
	tank.take_damage(30.0, null, false)
	assert_equal(tank.shield, 20.0, "Shield should absorb 30.0, leaving 20.0")
	assert_equal(tank.current_health, 100.0, "Health must remain completely untouched (100.0)")
	print("  [PASS] %s" % current_test_name)

	# 2.2 Shield break with HP spillover
	current_test_name = "T2.2_shield_break_spillover"
	tank.take_damage(35.0, null, false) # 20 from shield, 15 from HP
	assert_equal(tank.shield, 0.0, "Shield should be depleted to 0.0")
	assert_equal(tank.current_health, 85.0, "Health should deduct remaining 15.0 damage (85.0 HP)")
	assert_false(tank.is_dead, "Tank should remain alive")
	print("  [PASS] %s" % current_test_name)

	# 2.3 Shield saves from lethal HP hit
	current_test_name = "T2.3_shield_saves_from_lethal_hp"
	tank.current_health = 15.0 # Low HP
	tank.apply_powerup(Tank.PowerUpType.SHIELD, 10.0, 50.0)
	tank.take_damage(40.0, null, false) # 40 damage > 15 HP, but shield absorbs 40
	assert_equal(tank.shield, 10.0, "Shield should absorb all 40 damage, leaving 10 shield")
	assert_equal(tank.current_health, 15.0, "Health should stay at 15.0 without death")
	assert_false(tank.is_dead, "Tank must survive lethal hit thanks to shield")
	print("  [PASS] %s" % current_test_name)

	# 2.4 Exact lethal hit through shield + HP
	current_test_name = "T2.4_exact_shield_and_hp_lethal"
	tank.current_health = 50.0
	tank.shield = 25.0
	tank.take_damage(75.0, null, false) # 25 from shield, 50 from HP
	assert_equal(tank.shield, 0.0, "Shield depleted to 0.0")
	assert_equal(tank.current_health, 0.0, "Health depleted to 0.0")
	assert_true(tank.is_dead, "Tank eliminated when damage equals shield + health")
	print("  [PASS] %s" % current_test_name)

	# 2.5 Shield Aura Visibility
	current_test_name = "T2.5_shield_aura_visibility"
	var tank_aura: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(tank_aura)
	tank_aura.apply_powerup(Tank.PowerUpType.SHIELD, 10.0, 50.0)
	var aura_node: Node2D = tank_aura.get_node_or_null("ShieldAura")
	assert_not_null(aura_node, "ShieldAura node must exist")
	if aura_node:
		assert_true(aura_node.visible, "Shield aura must be visible when shield is active")
	tank_aura.take_damage(50.0, null, false) # Deplete shield
	if aura_node:
		assert_false(aura_node.visible, "Shield aura must hide when shield is depleted")
	tank_aura.queue_free()
	tank.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

# ==============================================================================
# GROUP 3: ELIMINATION STATE AND 3.5S RESPAWN TIMER
# ==============================================================================
func test_group_3_elimination_state_and_timer() -> void:
	print("\n--- GROUP 3: ELIMINATION STATE & 3.5S RESPAWN TIMER ---")

	current_test_name = "T3.1_elimination_event_and_component_disabling"
	var victim: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	var attacker: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	victim.tank_name = "VictimTank"
	attacker.tank_name = "AttackerTank"
	add_child(victim)
	add_child(attacker)

	var signal_received: Dictionary = {"received": false, "victim": null, "killer": null, "is_barrel": false}
	var callback = func(p_victim: Node2D, p_killer: Node2D, p_barrel: bool):
		signal_received["received"] = true
		signal_received["victim"] = p_victim
		signal_received["killer"] = p_killer
		signal_received["is_barrel"] = p_barrel
		
	GameEvents.tank_killed.connect(callback)

	victim.take_damage(100.0, attacker, false)

	# Signal check
	assert_true(signal_received["received"], "GameEvents.tank_killed must be emitted")
	assert_equal(signal_received["victim"], victim, "Victim in signal must match victim tank")
	assert_equal(signal_received["killer"], attacker, "Killer in signal must match attacker tank")
	assert_equal(signal_received["is_barrel"], false, "is_barrel must be false for direct kill")

	GameEvents.tank_killed.disconnect(callback)

	# State check
	assert_true(victim.is_dead, "Victim is_dead must be true")
	assert_equal(victim.deaths, 1, "Victim deaths must be incremented to 1")

	# Visuals hidden check
	var chassis_v = victim.get_node_or_null("ChassisVisual")
	var turret_p = victim.get_node_or_null("TurretPivot")
	var overhead_u = victim.get_node_or_null("OverheadUI")
	var shield_a = victim.get_node_or_null("ShieldAura")
	
	if chassis_v: assert_false(chassis_v.visible, "ChassisVisual must be hidden upon elimination")
	if turret_p: assert_false(turret_p.visible, "TurretPivot must be hidden upon elimination")
	if overhead_u: assert_false(overhead_u.visible, "OverheadUI must be hidden upon elimination")
	if shield_a: assert_false(shield_a.visible, "ShieldAura must be hidden upon elimination")

	# Collision disabled check
	assert_equal(victim.get_collision_layer_value(3), false, "Layer 3 (Tanks) must be disabled")
	assert_equal(victim.get_collision_mask_value(1), false, "Mask Layer 1 (Boundary) must be disabled")
	assert_equal(victim.get_collision_mask_value(2), false, "Mask Layer 2 (Walls) must be disabled")
	assert_equal(victim.get_collision_mask_value(3), false, "Mask Layer 3 (Tanks) must be disabled")
	assert_equal(victim.get_collision_mask_value(5), false, "Mask Layer 5 (Barrels) must be disabled")
	assert_equal(victim.collision_layer, 0, "collision_layer must be 0")

	# Movement & firing disabled
	victim.set_chassis_input(Vector2(1, 0))
	victim._physics_process(0.016)
	assert_equal(victim.velocity, Vector2.ZERO, "Velocity must be Vector2.ZERO while dead")
	var bullet_fired: bool = false
	victim.shoot()
	# Check projectile count
	var proj_nodes = get_tree().get_nodes_in_group("projectiles")
	assert_equal(proj_nodes.size(), 0, "Shooting while dead must produce no projectiles")

	# Respawn timer check
	assert_approx(victim._respawn_timer, 3.5, 0.05, "Respawn timer must be initiated to exactly 3.5s")
	print("  [PASS] %s" % current_test_name)

	# 3.2 Timer decrement and respawn trigger
	current_test_name = "T3.2_respawn_timer_tick_and_auto_respawn"
	# Simulate 1.0s (60 frames at 1/60s)
	for _i in range(60):
		victim._physics_process(1.0 / 60.0)
	assert_approx(victim._respawn_timer, 2.5, 0.1, "Respawn timer should decrement to ~2.5s after 1s")
	assert_true(victim.is_dead, "Tank must remain dead while timer > 0")

	# Simulate remaining 2.6s (156 frames) to exceed 3.5s total
	for _i in range(160):
		victim._physics_process(1.0 / 60.0)
		if not victim.is_dead:
			break
			
	assert_false(victim.is_dead, "Tank must auto-respawn after 3.5s elapsed")
	assert_equal(victim.current_health, 100.0, "HP must be restored to 100.0 on auto-respawn")

	victim.queue_free()
	attacker.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

# ==============================================================================
# GROUP 4: ATTACKER SCORING RESOLUTION
# ==============================================================================
func test_group_4_attacker_scoring() -> void:
	print("\n--- GROUP 4: ATTACKER SCORING RESOLUTION ---")

	current_test_name = "T4.1_kill_score_standard_100"
	var attacker: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	var victim1: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	attacker.tank_name = "Killer"
	victim1.tank_name = "Victim1"
	add_child(attacker)
	add_child(victim1)

	assert_equal(attacker.score, 0, "Attacker starts with 0 score")
	assert_equal(attacker.kills, 0, "Attacker starts with 0 kills")
	assert_equal(attacker.kill_streak, 0, "Attacker starts with 0 streak")

	victim1.take_damage(100.0, attacker, false)
	assert_equal(attacker.score, 100, "Attacker must receive +100 score on first kill")
	assert_equal(attacker.kills, 1, "Attacker kills must increment to 1")
	assert_equal(attacker.kill_streak, 1, "Attacker streak must be 1")
	assert_equal(victim1.score, 0, "Victim score must not change")
	print("  [PASS] %s" % current_test_name)

	# 4.2 Second Kill (streak 2)
	current_test_name = "T4.2_second_kill_score"
	var victim2: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	victim2.tank_name = "Victim2"
	add_child(victim2)

	victim2.take_damage(100.0, attacker, false)
	assert_equal(attacker.score, 200, "Attacker score must now be 200")
	assert_equal(attacker.kills, 2, "Attacker kills must now be 2")
	assert_equal(attacker.kill_streak, 2, "Attacker streak must be 2")
	print("  [PASS] %s" % current_test_name)

	# 4.3 Third Kill with Streak Bonus (+50)
	current_test_name = "T4.3_streak_bonus_at_3"
	var victim3: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	victim3.tank_name = "Victim3"
	add_child(victim3)

	victim3.take_damage(100.0, attacker, false)
	# 200 + 100 (base) + 50 (streak 3 bonus) = 350
	assert_equal(attacker.score, 350, "Attacker score at 3 streak must be 350 (+100 base + 50 bonus)")
	assert_equal(attacker.kills, 3, "Attacker kills must be 3")
	assert_equal(attacker.kill_streak, 3, "Attacker streak must be 3")
	print("  [PASS] %s" % current_test_name)

	# 4.4 Barrel Kill Attribution (+250)
	current_test_name = "T4.4_barrel_kill_score_bonus"
	var victim4: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	victim4.tank_name = "Victim4"
	add_child(victim4)

	victim4.take_damage(100.0, attacker, true) # is_barrel = true
	# 350 + 250 (barrel) = 600
	assert_equal(attacker.score, 600, "Attacker score must increase by 250 on barrel kill")
	assert_equal(attacker.barrel_kills, 1, "Attacker barrel_kills must increment to 1")
	print("  [PASS] %s" % current_test_name)

	# 4.5 Suicide / Self-Kill Protection
	current_test_name = "T4.5_suicide_no_score"
	var prev_score = attacker.score
	var prev_kills = attacker.kills
	attacker.take_damage(100.0, attacker, false) # Attacker damages itself
	assert_equal(attacker.score, prev_score, "Self-damage elimination must NOT award score to self")
	assert_equal(attacker.kills, prev_kills, "Self-damage elimination must NOT increment kills")
	assert_equal(attacker.kill_streak, 0, "Dying resets kill streak to 0")
	print("  [PASS] %s" % current_test_name)

	attacker.queue_free()
	victim1.queue_free()
	victim2.queue_free()
	victim3.queue_free()
	victim4.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# GROUP 5: SAFE RESPAWN POINT SELECTION, HP RESTORE & 1.5S INVULNERABILITY
# ==============================================================================
func test_group_5_safe_respawn_and_invulnerability() -> void:
	print("\n--- GROUP 5: SAFE RESPAWN & 1.5S INVULNERABILITY ---")

	# Load WorldMap scene to supply 8 standard spawn points
	var map: WorldMap = load("res://Scenes/map.tscn").instantiate() as WorldMap
	add_child(map)
	await get_tree().physics_frame

	var spawn_points: Array[Vector2] = map.get_spawn_positions()
	assert_equal(spawn_points.size(), 8, "Map must provide 8 spawn points")

	# 5.1 Furthest from Single Threat at NW (-950, -950)
	current_test_name = "T5.1_maximin_furthest_from_nw_threat"
	var threat_nw: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(threat_nw)
	threat_nw.global_position = Vector2(-950, -950)

	var respawning_tank: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(respawning_tank)

	var selected_pos: Vector2 = respawning_tank.select_safe_spawn_point()
	# The furthest point in the 8 points from (-950, -950) is SE (950, 950)
	assert_equal(selected_pos, Vector2(950, 950), "Safe spawn from NW threat must select SE (950, 950)")
	print("  [PASS] %s" % current_test_name)

	# 5.2 Furthest from Single Threat at SE (950, 950)
	current_test_name = "T5.2_maximin_furthest_from_se_threat"
	threat_nw.global_position = Vector2(950, 950)
	selected_pos = respawning_tank.select_safe_spawn_point()
	assert_equal(selected_pos, Vector2(-950, -950), "Safe spawn from SE threat must select NW (-950, -950)")
	print("  [PASS] %s" % current_test_name)

	# 5.3 Multi-Threat Maximin Scenario (NW, NE, SE occupied -> SW free)
	current_test_name = "T5.3_maximin_multi_threat_quadrants"
	var threat_ne: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	var threat_se: Tank = load("res://Scenes/tank.tscn").instantiate() as Tank
	add_child(threat_ne)
	add_child(threat_se)

	threat_nw.global_position = Vector2(-950, -950) # NW
	threat_ne.global_position = Vector2(950, -950)  # NE
	threat_se.global_position = Vector2(950, 950)   # SE
	# Free quadrant is SW (-950, 950)
	selected_pos = respawning_tank.select_safe_spawn_point()
	assert_equal(selected_pos, Vector2(-950, 950), "Safe spawn with NW, NE, SE occupied must choose SW (-950, 950)")
	print("  [PASS] %s" % current_test_name)

	# 5.4 Dead Enemies Filtered from Threat Calculation
	current_test_name = "T5.4_dead_enemies_filtered_from_threats"
	# Kill threats NE and SE
	threat_ne.is_dead = true
	threat_se.is_dead = true
	# Only NW is alive, so furthest should be SE (950, 950) again
	selected_pos = respawning_tank.select_safe_spawn_point()
	assert_equal(selected_pos, Vector2(950, 950), "Dead enemies must not be counted as active threats")
	print("  [PASS] %s" % current_test_name)

	# 5.5 Respawn State Restoration
	current_test_name = "T5.5_respawn_state_restoration"
	respawning_tank.take_damage(100.0, null, false) # Eliminate
	assert_true(respawning_tank.is_dead, "Tank is dead")
	
	respawning_tank.respawn(selected_pos)
	assert_equal(respawning_tank.global_position, selected_pos, "Tank position set to safe spawn point")
	assert_false(respawning_tank.is_dead, "is_dead must be false after respawn")
	assert_equal(respawning_tank.current_health, 100.0, "HP must be restored to full 100.0")
	assert_equal(respawning_tank.shield, 0.0, "Shield must be reset to 0.0")
	assert_true(respawning_tank.can_fire, "can_fire must be restored to true")
	
	# Visuals restored
	var chassis_v = respawning_tank.get_node_or_null("ChassisVisual")
	var turret_p = respawning_tank.get_node_or_null("TurretPivot")
	var overhead_u = respawning_tank.get_node_or_null("OverheadUI")
	if chassis_v: assert_true(chassis_v.visible, "Chassis visual restored")
	if turret_p: assert_true(turret_p.visible, "Turret visual restored")
	if overhead_u: assert_true(overhead_u.visible, "Overhead UI restored")

	# Collisions restored
	assert_true(respawning_tank.get_collision_layer_value(3), "Layer 3 collision restored")
	assert_true(respawning_tank.get_collision_mask_value(1), "Mask 1 restored")
	assert_true(respawning_tank.get_collision_mask_value(2), "Mask 2 restored")
	assert_true(respawning_tank.get_collision_mask_value(3), "Mask 3 restored")
	assert_true(respawning_tank.get_collision_mask_value(5), "Mask 5 restored")
	print("  [PASS] %s" % current_test_name)

	# 5.6 Post-Respawn Invulnerability (1.5s)
	current_test_name = "T5.6_post_respawn_invulnerability"
	assert_true(respawning_tank.is_invulnerable, "Tank must be invulnerable immediately upon respawn")
	assert_approx(respawning_tank._invulnerability_timer, 1.5, 0.05, "Invulnerability timer set to 1.5s")
	
	# Attempt damage during invulnerability
	respawning_tank.take_damage(50.0, threat_nw, false)
	assert_equal(respawning_tank.current_health, 100.0, "Damage during invulnerability must be completely absorbed/ignored (HP remains 100)")
	print("  [PASS] %s" % current_test_name)

	# 5.7 Invulnerability Expiration after 1.5s
	current_test_name = "T5.7_invulnerability_expiration"
	# Step 95 physics frames at 60Hz (~1.58s)
	for _i in range(95):
		respawning_tank._physics_process(1.0 / 60.0)
		
	assert_false(respawning_tank.is_invulnerable, "Invulnerability must expire after 1.5s")
	
	# Now apply damage
	respawning_tank.take_damage(25.0, threat_nw, false)
	assert_equal(respawning_tank.current_health, 75.0, "Damage must be deducted after invulnerability expires (HP = 75.0)")
	print("  [PASS] %s" % current_test_name)

	# Cleanup
	map.queue_free()
	threat_nw.queue_free()
	threat_ne.queue_free()
	threat_se.queue_free()
	respawning_tank.queue_free()
	await get_tree().physics_frame

func assert_not_null(val, msg: String) -> bool:
	if val != null:
		passed_count += 1
		return true
	else:
		failed_count += 1
		printerr("  [FAIL] %s: %s (Expected non-null, got null)" % [current_test_name, msg])
		return false

func assert_false(cond: bool, msg: String) -> bool:
	return assert_true(not cond, msg)
