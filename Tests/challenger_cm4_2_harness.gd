# res://Tests/challenger_cm4_2_harness.gd
extends Node

## Challenger 2 Verification Harness: Edge Case & Boundary Hardening
## Milestone: CM4 (Final Milestone)
## Focus:
##  1. Match buzzer-beater timing & score update before freeze
##  2. Replay / restart flow state & node hygiene
##  3. Wall-penetrating barrel explosion vs outer perimeter drop-off
##  4. Simultaneous power-up pickup race resolution

const MatchManagerScript = preload("res://Scripts/Core/match_manager.gd")
const TankScript = preload("res://Scripts/Entities/tank.gd")
const BarrelScript = preload("res://Scripts/Entities/barrel.gd")
const PowerUpScript = preload("res://Scripts/Entities/powerup.gd")
const ProjectileScript = preload("res://Scripts/Entities/projectile.gd")
const PodiumScreenScript = preload("res://Scripts/UI/podium_screen.gd")
const GameHUDScript = preload("res://Scripts/UI/hud.gd")
const MainGameScript = preload("res://Scripts/main_game.gd")

var passed_count: int = 0
var failed_count: int = 0
var current_test_name: String = ""

# Signal recording buffers
var test_lb_updates: Array = []
var test_match_ended_payload: Array = []
var test_collected_events: Array = []
var test_phys_collected_count: int = 0

func _on_test_leaderboard_updated(lb) -> void:
	test_lb_updates.append(lb)

func _on_test_match_ended(lb) -> void:
	test_match_ended_payload = lb

func _on_test_powerup_collected(p, c, t) -> void:
	test_collected_events.append({ "powerup": p, "collector": c, "type": t })

func _on_test_phys_collected(_p, _c, _t) -> void:
	test_phys_collected_count += 1

func _ready() -> void:
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED

	print("\n================================================================================")
	print("   CHALLENGER 2: EDGE CASE & BOUNDARY HARDENING VERIFICATION HARNESS (CM4)     ")
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

func assert_false(cond: bool, msg: String) -> bool:
	return assert_true(not cond, msg)

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

func assert_not_null(val, msg: String) -> bool:
	if val != null:
		passed_count += 1
		return true
	else:
		failed_count += 1
		printerr("  [FAIL] %s: %s (Expected non-null, got null)" % [current_test_name, msg])
		return false

func _run_all_challenger_tests() -> void:
	await get_tree().physics_frame
	
	await test_group_1_buzzer_beater()
	await test_group_2_replay_restart_flow()
	await test_group_3_wall_penetrating_barrel_explosion()
	await test_group_4_simultaneous_powerup_race()
	
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
# GROUP 1: MATCH BUZZER-BEATER TIMING & SCORE UPDATES
# ==============================================================================
func test_group_1_buzzer_beater() -> void:
	print("\n--- GROUP 1: MATCH BUZZER-BEATER TIMING & SCORE UPDATES ---")
	
	# 1.1 Exact buzzer-beater kill at t = 0.05s before 0:00
	current_test_name = "T1.1_buzzer_beater_kill_registered"
	var mm = MatchManagerScript.new()
	add_child(mm)
	
	var tank_player = load("res://Scenes/player_tank.tscn").instantiate()
	var tank_bot = load("res://Scenes/bot_tank.tscn").instantiate()
	add_child(tank_player)
	add_child(tank_bot)
	await get_tree().physics_frame
	
	mm.register_combatant(tank_player, "Player", true)
	mm.register_combatant(tank_bot, "Bot Alpha", false)
	
	test_lb_updates.clear()
	test_match_ended_payload.clear()
	GameEvents.leaderboard_updated.connect(_on_test_leaderboard_updated)
	GameEvents.match_ended.connect(_on_test_match_ended)
	
	mm.start_match(10.0)
	assert_true(mm.is_match_active, "Match must be active after start_match")
	assert_false(mm.is_match_ended, "Match must not be ended initially")
	
	# Fast-forward time remaining to 0.05s
	mm.time_remaining = 0.05
	
	# Register direct kill at t = 0.05s (before 0:00)
	mm.record_kill(tank_bot, tank_player, false)
	
	# Verify score updated immediately before freeze
	var player_stats: Dictionary = mm.get_combatant_stats(tank_player)
	assert_equal(player_stats.get("score"), 100, "Player must receive 100 points for buzzer-beater kill")
	assert_equal(player_stats.get("kills"), 1, "Player kills must increment to 1")
	var bot_stats: Dictionary = mm.get_combatant_stats(tank_bot)
	assert_equal(bot_stats.get("deaths"), 1, "Bot deaths must increment to 1")
	assert_true(test_lb_updates.size() > 0, "Leaderboard update signal must be emitted")
	assert_false(mm.is_match_ended, "Match must NOT yet be ended before time runs out")
	print("  [PASS] %s" % current_test_name)
	
	# 1.2 Advance physics process across 0:00 threshold to trigger match freeze
	current_test_name = "T1.2_match_freeze_and_final_scoring"
	tank_player.velocity = Vector2(100, 100)
	
	# Step physics frames to reach 0.0
	for _i in range(6):
		await get_tree().physics_frame
		
	assert_true(mm.is_match_ended, "Match must be ended when time_remaining <= 0.0")
	assert_false(mm.is_match_active, "Match must not be active after time_remaining reaches 0.0")
	assert_approx(mm.time_remaining, 0.0, 0.001, "time_remaining must clamp cleanly to 0.0")
	
	# Verify freeze effect on tanks
	assert_equal(tank_player.velocity, Vector2.ZERO, "Tank velocity must be frozen to Vector2.ZERO")
	assert_true(mm.is_match_ended, "MatchManager correctly enforces match_ended freeze state")
	
	# Verify final match_ended leaderboard preserved the buzzer-beater kill
	assert_true(test_match_ended_payload.size() >= 2, "match_ended must contain at least 2 combatants")
	if test_match_ended_payload.size() >= 2:
		assert_equal(test_match_ended_payload[0].get("name"), "Player", "Player must be 1st place in match_ended leaderboard")
		assert_equal(test_match_ended_payload[0].get("score"), 100, "Player score must be 100 in match_ended leaderboard")
	print("  [PASS] %s" % current_test_name)
	
	# 1.3 Post-buzzer kill rejection (kill attempted after match freeze)
	current_test_name = "T1.3_post_buzzer_kill_rejection"
	var prev_bot_score: int = bot_stats.get("score", 0)
	var prev_player_deaths: int = player_stats.get("deaths", 0)
	
	# Attempt late kill after match ended
	mm.record_kill(tank_player, tank_bot, false)
	
	var bot_stats_after: Dictionary = mm.get_combatant_stats(tank_bot)
	assert_equal(bot_stats_after.get("score", 0), prev_bot_score, "Late kill must NOT award score to Bot")
	assert_equal(bot_stats_after.get("kills", 0), 0, "Late kill must NOT increment Bot kills")
	var player_stats_after: Dictionary = mm.get_combatant_stats(tank_player)
	assert_equal(player_stats_after.get("deaths", 0), prev_player_deaths, "Late kill must NOT increment Player deaths")
	print("  [PASS] %s" % current_test_name)
	
	# 1.4 PodiumScreen visual reflection of buzzer-beater result
	current_test_name = "T1.4_podium_screen_displays_buzzer_winner"
	var podium_scene = load("res://Scenes/podium_screen.tscn")
	var podium = podium_scene.instantiate()
	add_child(podium)
	await get_tree().physics_frame
	
	podium.display_results(mm.get_leaderboard())
	assert_true(podium.visible, "Podium screen must be visible after display_results")
	assert_equal(podium.first_place_name.text, "Player", "Podium 1st place name must be Player")
	assert_equal(podium.first_place_score.text, "100 pts", "Podium 1st place score must display 100 pts")
	assert_equal(podium.player_rank_label.text, "#1", "Player rank badge must show #1")
	assert_equal(podium.player_score_label.text, "100", "Player score label must show 100")
	print("  [PASS] %s" % current_test_name)
	
	# 1.5 Buzzer-Beater Barrel Kill (+250 points & barrel_kills count)
	current_test_name = "T1.5_buzzer_beater_barrel_kill_bonus"
	var mm_barrel = MatchManagerScript.new()
	add_child(mm_barrel)
	mm_barrel.register_combatant(tank_player, "Player", true)
	mm_barrel.register_combatant(tank_bot, "Bot Alpha", false)
	mm_barrel.start_match(10.0)
	mm_barrel.time_remaining = 0.05
	
	# Buzzer-beater kill with is_barrel = true
	mm_barrel.record_kill(tank_bot, tank_player, true)
	var p_barrel_stats := mm_barrel.get_combatant_stats(tank_player)
	assert_equal(p_barrel_stats.get("score"), 250, "Barrel buzzer-beater must award 250 points (100 base + 150 barrel bonus)")
	assert_equal(p_barrel_stats.get("barrel_kills"), 1, "Player barrel_kills stat must be 1")
	
	podium.display_results(mm_barrel.get_leaderboard())
	assert_equal(podium.player_barrel_kills_label.text, "1", "Podium screen must show 1 barrel kill")
	mm_barrel.queue_free()
	print("  [PASS] %s" % current_test_name)
	
	# 1.6 Robustness against null/freed combatants during buzzer-beater
	current_test_name = "T1.6_buzzer_beater_null_combatant_robustness"
	var mm_null = MatchManagerScript.new()
	add_child(mm_null)
	mm_null.start_match(5.0)
	mm_null.time_remaining = 0.05
	# Call record_kill with null entities
	mm_null.record_kill(null, null, false)
	mm_null.record_kill(tank_bot, null, true)
	assert_true(mm_null.is_match_active, "Null combatants must not crash MatchManager")
	mm_null.queue_free()
	print("  [PASS] %s" % current_test_name)
	
	# Disconnect and cleanup
	GameEvents.leaderboard_updated.disconnect(_on_test_leaderboard_updated)
	GameEvents.match_ended.disconnect(_on_test_match_ended)
	podium.queue_free()
	tank_player.queue_free()
	tank_bot.queue_free()
	mm.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# GROUP 2: REPLAY / RESTART FLOW STATE & NODE HYGIENE
# ==============================================================================
func test_group_2_replay_restart_flow() -> void:
	print("\n--- GROUP 2: REPLAY / RESTART FLOW STATE & NODE HYGIENE ---")
	
	# 2.1 Direct MatchManager.restart_match() contract
	current_test_name = "T2.1_match_manager_restart_state_contract"
	var mm = MatchManagerScript.new()
	add_child(mm)
	var tank1 = load("res://Scenes/player_tank.tscn").instantiate()
	add_child(tank1)
	await get_tree().physics_frame
	
	mm.register_combatant(tank1, "Tank1", true)
	mm.start_match(60.0)
	mm.record_kill(null, tank1, false) # Give score
	tank1.can_fire = false
	tank1.score = 100
	
	assert_equal(mm.get_combatant_stats(tank1).get("score"), 100, "Score should be 100 before restart")
	
	# Call restart_match()
	mm.restart_match()
	
	assert_true(mm.is_match_active, "Match must be active after restart")
	assert_false(mm.is_match_ended, "Match must not be ended after restart")
	assert_approx(mm.time_remaining, 60.0, 0.01, "time_remaining must be reset to match_duration")
	assert_equal(mm.get_combatant_stats(tank1).get("score"), 0, "Combatant score in registry must be reset to 0")
	assert_equal(tank1.score, 0, "Tank entity score must be reset to 0")
	assert_true(tank1.can_fire, "Tank can_fire must be restored to true on restart")
	
	mm.queue_free()
	tank1.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 2.2 Rapid Double-Restart Re-entrancy
	current_test_name = "T2.2_rapid_double_restart_reentrancy"
	var mm2 = MatchManagerScript.new()
	add_child(mm2)
	mm2.start_match(120.0)
	mm2.restart_match()
	mm2.restart_match()
	assert_true(mm2.is_match_active, "Match must remain active after rapid double restart")
	assert_approx(mm2.time_remaining, 120.0, 0.01, "time_remaining must cleanly reset without corrupting")
	mm2.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 2.3 Full Scene Replay Flow via MainGame instantiation & state reset
	current_test_name = "T2.3_full_game_replay_lifecycle"
	var main_scene = load("res://Scenes/main_game.tscn")
	var game = main_scene.instantiate()
	add_child(game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Check initial state
	var barrels_container: Node2D = game.get_node("Entities/Barrels") as Node2D
	var initial_barrel_count: int = barrels_container.get_child_count()
	assert_equal(initial_barrel_count, 8, "MainGame must start with exactly 8 barrels")
	
	var player_tank = game.get_node("Entities/Tanks/PlayerTank")
	var initial_player_pos: Vector2 = player_tank.global_position
	
	# Alter state: move player, destroy a barrel, alter scores
	player_tank.global_position = Vector2(888, 888)
	var first_barrel = barrels_container.get_child(0)
	first_barrel.take_damage(100.0, player_tank, false) # Detonate barrel
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	assert_true(player_tank.global_position != initial_player_pos, "Player position altered")
	
	# Clean up previous match instance and re-instantiate fresh (replay flow)
	game.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var fresh_game = main_scene.instantiate()
	add_child(fresh_game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Verify fresh game state:
	var fresh_barrels: Node2D = fresh_game.get_node("Entities/Barrels") as Node2D
	assert_equal(fresh_barrels.get_child_count(), 8, "Fresh game must restore all 8 barrels cleanly")
	
	var fresh_player = fresh_game.get_node("Entities/Tanks/PlayerTank")
	assert_equal(fresh_player.global_position, initial_player_pos, "Fresh game must reset player position to initial spawn point")
	assert_equal(fresh_player.score, 0, "Fresh game player score must be 0")
	
	var fresh_mm = fresh_game.get_node("MatchManager")
	assert_approx(fresh_mm.time_remaining, 180.0, 1.0, "Match timer must reset to 180.0s")
	
	# Verify no duplicate UI in tree
	var hud_count: int = 0
	var podium_count: int = 0
	for child in fresh_game.get_children():
		if child is CanvasLayer:
			if child.name == "HUD":
				hud_count += 1
			elif child.name == "PodiumScreen":
				podium_count += 1
	assert_equal(hud_count, 1, "There must be exactly 1 HUD instance (no duplicate UI)")
	assert_equal(podium_count, 1, "There must be exactly 1 PodiumScreen instance (no duplicate UI)")
	
	fresh_game.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 2.4 Damaged / Mid-respawn dead tank restart behavior comparison
	current_test_name = "T2.4_mid_match_dead_tank_restart_comparison"
	var damaged_tank = load("res://Scenes/player_tank.tscn").instantiate()
	add_child(damaged_tank)
	damaged_tank.current_health = 25.0
	damaged_tank.shield = 40.0
	
	var mm3 = MatchManagerScript.new()
	add_child(mm3)
	mm3.register_combatant(damaged_tank, "Damaged", true)
	mm3.restart_match()
	
	# MatchManager alone resets scoring and timers, but does not mutate physics health
	assert_equal(damaged_tank.current_health, 25.0, "MatchManager.restart_match() scopes strictly to match statistics")
	
	damaged_tank.queue_free()
	mm3.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)

# ==============================================================================
# GROUP 3: WALL-PENETRATING BARREL EXPLOSION DYNAMICS
# ==============================================================================
func test_group_3_wall_penetrating_barrel_explosion() -> void:
	print("\n--- GROUP 3: WALL-PENETRATING BARREL EXPLOSION DYNAMICS ---")
	
	current_test_name = "T3.1_barrel_explosion_wall_penetration_and_radius_cutoff"
	
	# Setup test arena root
	var arena: Node2D = Node2D.new()
	add_child(arena)
	
	# 1. Place Barrel at (0, 0) - blast radius = 200px
	var barrel_scene = load("res://Scenes/barrel.tscn")
	var barrel = barrel_scene.instantiate()
	barrel.global_position = Vector2(0, 0)
	arena.add_child(barrel)
	
	# 2. Place Physical Wall (StaticBody2D, Layer 2) directly between barrel and target
	# Centered at x = 60, size = (30, 300)
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 2 # Layer 2: Modular Covers
	wall.collision_mask = 12 # Tanks & Projectiles
	var wall_col: CollisionShape2D = CollisionShape2D.new()
	var wall_box: RectangleShape2D = RectangleShape2D.new()
	wall_box.size = Vector2(30, 300)
	wall_col.shape = wall_box
	wall.add_child(wall_col)
	wall.global_position = Vector2(60, 0)
	arena.add_child(wall)
	
	# 3. Target A: Sheltered Tank behind wall at (120, 0) -> distance = 120px <= 200px
	var tank_scene = load("res://Scenes/player_tank.tscn")
	var tank_sheltered = tank_scene.instantiate()
	tank_sheltered.global_position = Vector2(120, 0)
	arena.add_child(tank_sheltered)
	
	# 4. Target B: Tank OUTSIDE blast radius at (250, 0) -> distance = 250px > 200px
	var tank_outside = tank_scene.instantiate()
	tank_outside.global_position = Vector2(250, 0)
	arena.add_child(tank_outside)
	
	# 5. Target C: Precision Boundary Inside at (0, 195) -> South, distance = 195px <= 200px
	var tank_boundary_in = tank_scene.instantiate()
	tank_boundary_in.global_position = Vector2(0, 195)
	arena.add_child(tank_boundary_in)
	
	# 6. Target D: Precision Boundary Outside at (0, -205) -> North (non-overlapping), distance = 205px > 200px
	var tank_boundary_out = tank_scene.instantiate()
	tank_boundary_out.global_position = Vector2(0, -205)
	arena.add_child(tank_boundary_out)
	
	# Wait 2 physics frames for physics space registration
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Verify all tanks are at full health initially
	assert_equal(tank_sheltered.current_health, 100.0, "Sheltered tank starts at 100 HP")
	assert_equal(tank_outside.current_health, 100.0, "Outside tank starts at 100 HP")
	assert_equal(tank_boundary_in.current_health, 100.0, "Boundary-in tank starts at 100 HP")
	assert_equal(tank_boundary_out.current_health, 100.0, "Boundary-out tank starts at 100 HP")
	
	# Detonate barrel
	barrel.explode()
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Calculations:
	# blast_radius = 200.0, min_damage = 25.0, max_damage = 85.0
	# For dist = 120.0: ratio = 1.0 - 120/200 = 0.40. blast_damage = lerp(25, 85, 0.40) = 49.0 HP.
	# Expected health = 100.0 - 49.0 = 51.0 HP.
	assert_true(tank_sheltered.current_health < 100.0, "Sheltered tank BEHIND WALL MUST take damage from wall-penetrating AoE")
	assert_approx(tank_sheltered.current_health, 51.0, 1.0, "Sheltered tank takes expected attenuated damage (~49 HP, leaving ~51 HP)")
	
	# Outside blast radius target must take 0 damage
	assert_equal(tank_outside.current_health, 100.0, "Target outside blast radius (250px) MUST take exactly 0 damage")
	
	# Precision inside (195px): ratio = 1.0 - 195/200 = 0.025. blast_damage = lerp(25, 85, 0.025) = ~26.5 HP.
	assert_true(tank_boundary_in.current_health < 100.0, "Target just inside boundary (195px) takes damage")
	assert_approx(tank_boundary_in.current_health, 73.5, 2.0, "Target at 195px takes ~26.5 damage")
	
	# Precision outside (-205px): outside radius -> 0 damage
	assert_equal(tank_boundary_out.current_health, 100.0, "Target just outside boundary (205px) MUST take exactly 0 damage")
	print("  [PASS] %s" % current_test_name)
	
	# 3.2 Contrast verification: Direct ballistic projectile is stopped by the wall
	current_test_name = "T3.2_ballistic_bullet_blocked_by_wall_contrast"
	var proj_scene = load("res://Scenes/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.global_position = Vector2(10, 0) # Fired toward target at (120, 0)
	arena.add_child(proj)
	proj.setup(null, Vector2.RIGHT, 650.0, 25.0)
	
	var sheltered_hp_before: float = tank_sheltered.current_health
	
	# Step physics frames to let bullet travel and hit wall at x = 60
	for _i in range(10):
		await get_tree().physics_frame
		
	assert_equal(tank_sheltered.current_health, sheltered_hp_before, "Ballistic bullet MUST be stopped by wall, dealing 0 damage to sheltered tank")
	print("  [PASS] %s" % current_test_name)
	
	# 3.3 Wall-penetrating barrel-to-barrel chain reaction through solid wall
	current_test_name = "T3.3_barrel_to_barrel_wall_penetrating_chain_reaction"
	var barrel1 = barrel_scene.instantiate()
	barrel1.global_position = Vector2(-2000, 0)
	arena.add_child(barrel1)
	
	# Wall separating barrel 1 and barrel 2
	var wall2 = StaticBody2D.new()
	wall2.collision_layer = 2
	var wall2_col = CollisionShape2D.new()
	var wall2_box = RectangleShape2D.new()
	wall2_box.size = Vector2(30, 300)
	wall2_col.shape = wall2_box
	wall2.add_child(wall2_col)
	wall2.global_position = Vector2(-1940, 0)
	arena.add_child(wall2)
	
	# Barrel 2 behind wall at dist = 120px (<= 200px)
	var barrel2 = barrel_scene.instantiate()
	barrel2.global_position = Vector2(-1880, 0)
	arena.add_child(barrel2)
	
	# Tank near barrel 2 at dist = 80px from barrel 2
	var chain_tank = tank_scene.instantiate()
	chain_tank.global_position = Vector2(-1800, 0)
	arena.add_child(chain_tank)
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Detonate barrel 1
	barrel1.explode()
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Barrel 2 must have detonated in chain reaction through the wall
	var barrel2_detonated: bool = not is_instance_valid(barrel2) or barrel2.is_exploded
	assert_true(barrel2_detonated, "Barrel 2 must detonate via chain reaction through wall (and be freed)")
	# Tank near barrel 2 must take damage from secondary explosion
	assert_true(chain_tank.current_health < 100.0, "Tank must take damage from barrel chain reaction")
	print("  [PASS] %s" % current_test_name)
	
	arena.queue_free()
	await get_tree().physics_frame

# ==============================================================================
# GROUP 4: SIMULTANEOUS POWER-UP COLLECTION RACE
# ==============================================================================
func test_group_4_simultaneous_powerup_race() -> void:
	print("\n--- GROUP 4: SIMULTANEOUS POWER-UP COLLECTION RACE ---")
	
	# 4.1 Direct simultaneous collection call race
	current_test_name = "T4.1_direct_simultaneous_collect_race"
	var pu_scene = load("res://Scenes/powerup.tscn")
	var pu = pu_scene.instantiate()
	pu.global_position = Vector2(5000, 5000)
	add_child(pu)
	pu.setup(PowerUpScript.Type.SHIELD)
	
	var tank_a = load("res://Scenes/player_tank.tscn").instantiate()
	tank_a.global_position = Vector2(6000, 6000)
	var tank_b = load("res://Scenes/player_tank.tscn").instantiate()
	tank_b.global_position = Vector2(7000, 7000)
	add_child(tank_a)
	add_child(tank_b)
	
	test_collected_events.clear()
	GameEvents.powerup_collected.connect(_on_test_powerup_collected)
	await get_tree().physics_frame
	
	# Tank A and Tank B attempt collection simultaneously on the same frame
	pu.collect(tank_a)
	pu.collect(tank_b)
	
	assert_equal(tank_a.shield, 50.0, "Tank A (first in race) must receive shield (+50.0)")
	assert_equal(tank_b.shield, 0.0, "Tank B (second in race) must receive 0 shield")
	assert_equal(test_collected_events.size(), 1, "powerup_collected event must be emitted EXACTLY ONCE")
	if test_collected_events.size() > 0:
		assert_equal(test_collected_events[0]["collector"], tank_a, "Winner of race must be Tank A")
	assert_true(pu.is_collected, "Power-up must be marked as collected")
	assert_true(pu.is_queued_for_deletion(), "Power-up must be queued for deletion")
	
	GameEvents.powerup_collected.disconnect(_on_test_powerup_collected)
	tank_a.queue_free()
	tank_b.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 4.2 Physical Area2D collision race with overlapping shapes
	current_test_name = "T4.2_physical_area2d_collision_overlap_race"
	var pu2 = pu_scene.instantiate()
	pu2.global_position = Vector2(0, 0)
	add_child(pu2)
	pu2.setup(PowerUpScript.Type.SHIELD)
	
	var tank_c = load("res://Scenes/player_tank.tscn").instantiate()
	tank_c.global_position = Vector2(-5, 0) # Inside pickup collision shape
	add_child(tank_c)
	
	var tank_d = load("res://Scenes/player_tank.tscn").instantiate()
	tank_d.global_position = Vector2(5, 0) # Also inside pickup collision shape
	add_child(tank_d)
	
	test_phys_collected_count = 0
	GameEvents.powerup_collected.connect(_on_test_phys_collected)
	
	# Step physics frames to resolve Area2D overlap
	for _i in range(5):
		await get_tree().physics_frame
		
	# Exactly one tank must receive shield
	var c_has_shield: bool = tank_c.shield == 50.0
	var d_has_shield: bool = tank_d.shield == 50.0
	assert_true(c_has_shield != d_has_shield, "Exactly ONE tank must receive shield in physical collision race (exclusive OR)")
	assert_equal(test_phys_collected_count, 1, "Exactly one powerup_collected event emitted in physical race")
	
	GameEvents.powerup_collected.disconnect(_on_test_phys_collected)
	tank_c.queue_free()
	tank_d.queue_free()
	if is_instance_valid(pu2) and not pu2.is_queued_for_deletion():
		pu2.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 4.3 Dead Tank Collection Rejection
	current_test_name = "T4.3_dead_tank_cannot_collect_powerup"
	var pu3 = pu_scene.instantiate()
	add_child(pu3)
	pu3.setup(PowerUpScript.Type.HEALTH)
	
	var dead_tank = load("res://Scenes/player_tank.tscn").instantiate()
	add_child(dead_tank)
	dead_tank.is_dead = true
	dead_tank.current_health = 0.0
	
	pu3.collect(dead_tank)
	assert_false(pu3.is_collected, "PowerUp must NOT be collected by a dead tank")
	assert_equal(dead_tank.current_health, 0.0, "Dead tank HP must remain 0.0")
	
	dead_tank.queue_free()
	pu3.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 4.4 Quad-Tank Pickup Contention (4 tanks contending simultaneously)
	current_test_name = "T4.4_quad_tank_simultaneous_pickup_race"
	var pu4 = pu_scene.instantiate()
	pu4.global_position = Vector2(8000, 8000)
	add_child(pu4)
	pu4.setup(PowerUpScript.Type.RAPID_FIRE)
	
	var quad_tanks: Array = []
	for i in range(4):
		var t = load("res://Scenes/player_tank.tscn").instantiate()
		t.global_position = Vector2(9000 + i * 200, 8000)
		add_child(t)
		quad_tanks.append(t)
	await get_tree().physics_frame
	
	test_collected_events.clear()
	GameEvents.powerup_collected.connect(_on_test_powerup_collected)
	
	# Simultaneous burst from all 4 tanks
	for t in quad_tanks:
		pu4.collect(t)
		
	var buff_count: int = 0
	for t in quad_tanks:
		if t.has_rapid_fire:
			buff_count += 1
			
	assert_equal(buff_count, 1, "In a 4-tank race, exactly ONE tank must obtain rapid fire buff")
	assert_equal(test_collected_events.size(), 1, "Exactly one powerup_collected event emitted in 4-tank race")
	
	GameEvents.powerup_collected.disconnect(_on_test_powerup_collected)
	for t in quad_tanks:
		t.queue_free()
	if is_instance_valid(pu4) and not pu4.is_queued_for_deletion():
		pu4.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
	
	# 4.5 Duplicate power-up pickup refresh clamping (no over-stacking)
	current_test_name = "T4.5_duplicate_shield_clamping_at_max"
	var stacking_tank = load("res://Scenes/player_tank.tscn").instantiate()
	add_child(stacking_tank)
	await get_tree().physics_frame
	
	# Collect first shield (+50)
	stacking_tank.apply_powerup(PowerUpScript.Type.SHIELD, 10.0, 50.0)
	assert_equal(stacking_tank.shield, 50.0, "Initial shield is 50.0")
	
	# Collect second shield (+50)
	stacking_tank.apply_powerup(PowerUpScript.Type.SHIELD, 10.0, 50.0)
	assert_equal(stacking_tank.shield, 50.0, "Duplicate shield must not stack above max_shield (50.0)")
	
	stacking_tank.queue_free()
	await get_tree().physics_frame
	print("  [PASS] %s" % current_test_name)
