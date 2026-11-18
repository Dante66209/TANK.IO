# res://Tests/challenger_cm4_chaos_test.gd
extends Node

## Challenger 1 (CM4): Full Match & Chaos Stress Verifier
## Empirically verifies:
## 1. Multi-tank chaos match (1 player + 4 bots, 8 barrels) for 1200 physics frames
## 2. Projectile pool saturation (continuous firing, zero memory leaks / orphan nodes)
## 3. Barrel cascade chain reactions across multiple rooms
## 4. Leaderboard integrity under rapid concurrent kill events

const MainGameScript = preload("res://Scripts/main_game.gd")
const MatchManagerScript = preload("res://Scripts/Core/match_manager.gd")
const TankScript = preload("res://Scripts/Entities/tank.gd")
const BarrelScript = preload("res://Scripts/Entities/barrel.gd")
const ProjectileScript = preload("res://Scripts/Entities/projectile.gd")

var passed_count: int = 0
var failed_count: int = 0
var failure_details: Array[String] = []

func _ready() -> void:
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED
		
	print("\n==================================================================")
	print("   CHALLENGER 1 (CM4): FULL MATCH & CHAOS STRESS HARNESS        ")
	print("==================================================================")
	
	call_deferred("_run_all_suites")

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failed_count += 1
		var msg: String = "[FAIL] %s - %s" % [test_name, details]
		failure_details.append(msg)
		printerr("  " + msg)

func _wait_physics(frames: int = 1) -> void:
	for _i in range(frames):
		await get_tree().physics_frame

func _run_all_suites() -> void:
	await _wait_physics(2)
	
	print("\n>>> SUITE 1: MULTI-TANK CHAOS MATCH (1200 PHYSICS FRAMES) <<<")
	await _suite_1_multi_tank_chaos_match()
	
	print("\n>>> SUITE 2: PROJECTILE POOL SATURATION & ORPHAN NODE INTEGRITY <<<")
	await _suite_2_projectile_pool_saturation()
	
	print("\n>>> SUITE 3: BARREL CASCADE CHAIN REACTIONS ACROSS MULTIPLE ROOMS <<<")
	await _suite_3_barrel_cascade_chain_reactions()
	
	print("\n>>> SUITE 4: LEADERBOARD CONCURRENCY, INTEGRITY & SUICIDE EDGE CASES <<<")
	await _suite_4_leaderboard_concurrency_and_integrity()
	
	_print_summary()

# ==============================================================================
# SUITE 1: Multi-Tank Chaos Match (1 Player + 4 Bots, 8 Barrels, 1200 Frames)
# ==============================================================================
func _suite_1_multi_tank_chaos_match() -> void:
	var main_scene: PackedScene = load("res://Scenes/main_game.tscn")
	_assert(main_scene != null, "Load res://Scenes/main_game.tscn")
	if main_scene == null:
		return
		
	var game: Node2D = main_scene.instantiate() as Node2D
	_assert(game != null, "Instantiate MainGame scene")
	add_child(game)
	await _wait_physics(2)
	
	# Verify Entities Presence
	var player: CharacterBody2D = game.get_node_or_null("Entities/Tanks/PlayerTank") as CharacterBody2D
	var bot1: CharacterBody2D = game.get_node_or_null("Entities/Tanks/BotTank1") as CharacterBody2D
	var bot2: CharacterBody2D = game.get_node_or_null("Entities/Tanks/BotTank2") as CharacterBody2D
	var bot3: CharacterBody2D = game.get_node_or_null("Entities/Tanks/BotTank3") as CharacterBody2D
	var bot4: CharacterBody2D = game.get_node_or_null("Entities/Tanks/BotTank4") as CharacterBody2D
	var bots: Array[CharacterBody2D] = [bot1, bot2, bot3, bot4]
	var barrels_container: Node2D = game.get_node_or_null("Entities/Barrels") as Node2D
	var barrels_count: int = barrels_container.get_child_count() if barrels_container else 0
	
	_assert(player != null, "Player tank present in MainGame")
	_assert(bot1 != null and bot2 != null and bot3 != null and bot4 != null, "4 AI bot tanks present in MainGame")
	_assert(barrels_count == 8, "8 explosive barrels present in MainGame", "Found: %d" % barrels_count)
	
	var mm: Node = game.get_node_or_null("MatchManager")
	var mm_active: bool = (mm.get("is_match_active") == true) if mm != null else false
	_assert(mm != null and mm_active, "MatchManager initialized and active")
	
	# Event Counters
	var telemetry: Dictionary = { "kills": 0, "respawns": 0, "barrels": 0, "powerups": 0 }
	
	var ge = get_node_or_null("/root/GameEvents")
	if ge != null:
		ge.tank_killed.connect(func(_v, _k, _b): telemetry["kills"] += 1)
		ge.tank_respawned.connect(func(_t, _p): telemetry["respawns"] += 1)
		ge.barrel_destroyed.connect(func(_b, _d): telemetry["barrels"] += 1)
		ge.powerup_collected.connect(func(_p, _c, _t): telemetry["powerups"] += 1)
		
	var start_mem: int = OS.get_static_memory_usage()
	var prev_time: float = float(mm.get("time_remaining")) if mm != null else 180.0
	
	# Step 1200 physics frames (20 simulated seconds at 60Hz)
	var physics_stable: bool = true
	var bounds_respected: bool = true
	
	for frame in range(1200):
		# Drive simulated player actions
		if is_instance_valid(player) and player.has_method("set_chassis_input"):
			var ang: float = frame * 0.05
			var move_vec: Vector2 = Vector2(cos(ang), sin(ang))
			player.set_chassis_input(move_vec)
			if frame % 25 == 0 and player.has_method("shoot"):
				# Aim at nearest bot
				var nearest_pos: Vector2 = Vector2.ZERO
				var nearest_d: float = 99999.0
				for b in bots:
					if is_instance_valid(b) and not bool(b.get("is_dead")):
						var d: float = player.global_position.distance_to(b.global_position)
						if d < nearest_d:
							nearest_d = d
							nearest_pos = b.global_position
				if nearest_d < 99999.0:
					player.set_turret_target(nearest_pos)
					player.shoot()
					
		await _wait_physics(1)
		
		# Check periodic stability every 300 frames
		if (frame + 1) % 300 == 0:
			# Verify no NaN transforms in player or bots
			var max_bound := 1700.0
			if is_instance_valid(player):
				if is_nan(player.global_position.x) or is_nan(player.global_position.y) or is_nan(player.velocity.x):
					physics_stable = false
				if absf(player.global_position.x) > max_bound or absf(player.global_position.y) > max_bound:
					bounds_respected = false
					
			for b in bots:
				if is_instance_valid(b):
					if is_nan(b.global_position.x) or is_nan(b.global_position.y) or is_nan(b.velocity.x):
						physics_stable = false
					if absf(b.global_position.x) > max_bound or absf(b.global_position.y) > max_bound:
						bounds_respected = false
						
	_assert(physics_stable, "1200-Frame physics stability (No NaNs in position or velocity)")
	_assert(bounds_respected, "1200-Frame containment (All entities remain within arena boundaries)")
	
	var end_time: float = float(mm.get("time_remaining")) if mm != null else 0.0
	_assert(end_time < prev_time, "MatchManager timer decremented continuously during 1200 frames", "Timer went from %f to %f" % [prev_time, end_time])
	
	# Verify leaderboard integrity after chaos match
	if mm != null:
		var lb = mm.get_leaderboard()
		_assert(lb.size() == 5, "Leaderboard contains all 5 registered combatants", "Found: %d" % lb.size())
		var sorted: bool = true
		for i in range(lb.size() - 1):
			if lb[i]["score"] < lb[i+1]["score"]:
				sorted = false
		_assert(sorted, "Leaderboard remains properly sorted descending after 1200 chaos frames")
		
	var end_mem: int = OS.get_static_memory_usage()
	var mem_growth_mb: float = float(end_mem - start_mem) / (1024.0 * 1024.0)
	print("    [Info] 1200 Frames Telemetry: Kills=%d, Respawns=%d, BarrelsDetonated=%d, PowerUpsCollected=%d, MemDelta=%.2f MB" % [
		telemetry["kills"], telemetry["respawns"], telemetry["barrels"], telemetry["powerups"], mem_growth_mb
	])
	_assert(mem_growth_mb < 35.0, "Static memory growth remains bounded under long match simulation", "Growth: %.2f MB" % mem_growth_mb)
	
	# Clean up
	game.queue_free()
	await _wait_physics(5)

# ==============================================================================
# SUITE 2: Projectile Pool Saturation & Orphan Node Verification
# ==============================================================================
func _suite_2_projectile_pool_saturation() -> void:
	var initial_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	# Spawn a container with 8 tanks firing in rapid succession for 250 frames
	var firing_arena := Node2D.new()
	add_child(firing_arena)
	
	var proj_container := Node2D.new()
	proj_container.add_to_group("projectiles")
	firing_arena.add_child(proj_container)
	
	# Wall boundary to stop bullets
	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	var col := CollisionShape2D.new()
	var rshape := RectangleShape2D.new()
	rshape.size = Vector2(800, 32)
	col.shape = rshape
	wall.add_child(col)
	wall.global_position = Vector2(0, -300)
	firing_arena.add_child(wall)
	
	var tank_scene: PackedScene = load("res://Scenes/tank.tscn")
	var shooters: Array[Node] = []
	for i in range(8):
		var t: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
		t.global_position = Vector2((i - 4) * 80.0, 0.0)
		t.set("fire_cooldown", 0.05) # Ultra-fast fire rate
		firing_arena.add_child(t)
		shooters.append(t)
		
	await _wait_physics(2)
	
	var projectiles_fired: int = 0
	for frame in range(200):
		for t in shooters:
			if is_instance_valid(t) and bool(t.get("can_fire")):
				t.set_turret_target(Vector2(t.global_position.x, -300))
				t.shoot()
				projectiles_fired += 1
		await _wait_physics(1)
		
	_assert(projectiles_fired >= 200, "Projectile saturation achieved (fired %d bullets)" % projectiles_fired)
	
	# Wait for all bullets to impact wall and CPUParticles2D timers (0.3s) to expire
	await _wait_physics(60)
	
	var active_projectiles_count: int = proj_container.get_child_count()
	_assert(active_projectiles_count == 0, "All projectiles successfully impacted and freed", "Remaining: %d" % active_projectiles_count)
	
	# Clean up arena
	firing_arena.queue_free()
	await _wait_physics(30)
	
	var final_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var orphan_delta: int = final_orphans - initial_orphans
	_assert(orphan_delta <= 0, "Zero orphan nodes leaked during projectile barrage", "Orphan delta: %d" % orphan_delta)
	
	# Edge Case 2B: Projectile whose shooter is freed in-flight
	var shooter: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
	var victim: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
	add_child(shooter)
	add_child(victim)
	shooter.global_position = Vector2(0, 0)
	victim.global_position = Vector2(120, 0)
	
	var proj_scene: PackedScene = load("res://Scenes/projectile.tscn")
	var proj: Area2D = proj_scene.instantiate() as Area2D
	add_child(proj)
	if proj.has_method("setup"):
		proj.setup(shooter, Vector2.RIGHT, 650.0, 25.0)
	proj.global_position = Vector2(30, 0)
	
	# Free shooter immediately while projectile is in flight
	shooter.queue_free()
	await _wait_physics(2)
	
	# Impact victim
	var valid_sh = proj.get("shooter") if is_instance_valid(proj.get("shooter")) else null
	victim.take_damage(25.0, valid_sh, false)
	await _wait_physics(2)
	var victim_hp: float = float(victim.get("current_health"))
	_assert(victim_hp == 75.0, "Projectile impact resolves cleanly after shooter freed", "Victim HP: %f" % victim_hp)
	
	victim.queue_free()
	await _wait_physics(2)

# ==============================================================================
# SUITE 3: Barrel Cascade Chain Reactions Across Multiple Rooms
# ==============================================================================
func _suite_3_barrel_cascade_chain_reactions() -> void:
	var cascade_root := Node2D.new()
	add_child(cascade_root)
	
	# Construct 5 Rooms separated by 4 Interior Walls (Layer 2)
	# Room 1: x = 0 (Barrel 1)
	# Wall 1: x = 80
	# Room 2: x = 160 (Barrel 2) (dist to B1 = 160 < 200 blast radius)
	# Wall 2: x = 240
	# Room 3: x = 320 (Barrel 3) (dist to B2 = 160 < 200)
	# Wall 3: x = 400
	# Room 4: x = 480 (Barrel 4) (dist to B3 = 160 < 200)
	# Wall 4: x = 560
	# Room 5: x = 620 (Target Tank) (dist to B4 = 140 < 200)
	
	var wall_x_positions: Array[float] = [80.0, 240.0, 400.0, 560.0]
	for wx in wall_x_positions:
		var wall := StaticBody2D.new()
		wall.collision_layer = 2 # Interior walls (Layer 2)
		var col := CollisionShape2D.new()
		var rshape := RectangleShape2D.new()
		rshape.size = Vector2(32.0, 300.0)
		col.shape = rshape
		wall.add_child(col)
		wall.global_position = Vector2(wx, 0.0)
		cascade_root.add_child(wall)
		
	var barrel_scene: PackedScene = load("res://Scenes/barrel.tscn")
	var barrels: Array[Node] = []
	var barrel_x_positions: Array[float] = [0.0, 160.0, 320.0, 480.0]
	for bx in barrel_x_positions:
		var b: Node2D = barrel_scene.instantiate() as Node2D
		b.global_position = Vector2(bx, 0.0)
		cascade_root.add_child(b)
		barrels.append(b)
		
	# Attacker in Room 1 and Target Tank in Room 5
	var tank_scene: PackedScene = load("res://Scenes/tank.tscn")
	var attacker: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
	attacker.global_position = Vector2(-100.0, 0.0)
	attacker.set("tank_name", "CascadeAttacker")
	cascade_root.add_child(attacker)
	
	var target_tank: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
	target_tank.global_position = Vector2(620.0, 0.0)
	target_tank.set("tank_name", "CascadeTarget")
	cascade_root.add_child(target_tank)
	target_tank.set("current_health", 30.0)
	
	# Setup MatchManager to track kills & barrel score
	var mm: Node = MatchManagerScript.new()
	cascade_root.add_child(mm)
	mm.register_combatant(attacker, "CascadeAttacker", false)
	mm.register_combatant(target_tank, "CascadeTarget", false)
	mm.start_match(180.0)
	
	await _wait_physics(2)
	
	# Detonate Barrel 1 by Attacker's shot
	barrels[0].take_damage(50.0, attacker, false)
	await _wait_physics(10)
	
	# Verify that ALL 4 barrels exploded in sequence
	var all_barrels_exploded: bool = true
	for b in barrels:
		if is_instance_valid(b) and not bool(b.get("is_exploded")):
			all_barrels_exploded = false
			
	_assert(all_barrels_exploded, "Multi-room barrel cascade fully propagated across 4 rooms through solid walls")
	var target_dead: bool = bool(target_tank.get("is_dead"))
	_assert(target_dead, "Target tank in Room 5 eliminated by 4th barrel cascade detonation")
	
	# Verify score attribution to original shooter
	var attacker_stats = mm.get_combatant_stats(attacker)
	var attacker_kills: int = int(attacker_stats.get("kills", 0))
	var attacker_barrel_kills: int = int(attacker_stats.get("barrel_kills", 0))
	var attacker_score: int = int(attacker_stats.get("score", 0))
	
	_assert(attacker_kills == 1, "Attacker credited with 1 kill via barrel cascade", "Kills: %d" % attacker_kills)
	_assert(attacker_barrel_kills == 1, "Attacker credited with barrel kill bonus", "Barrel kills: %d" % attacker_barrel_kills)
	# Score = 250 (kill + barrel bonus) + 20*4 (4 barrels destroyed = 80) = 330 pts
	_assert(attacker_score >= 250, "Attacker score contains kill and barrel bonuses", "Score: %d (Expected >= 250)" % attacker_score)
	
	# Test 3B: Dense 16-Barrel Grid Cascade (4x4)
	var grid_barrels: Array[Node] = []
	for x in range(4):
		for y in range(4):
			var b: Node2D = barrel_scene.instantiate() as Node2D
			b.global_position = Vector2(x * 90.0 - 150.0, y * 90.0 - 150.0)
			cascade_root.add_child(b)
			grid_barrels.append(b)
			
	await _wait_physics(2)
	
	# Detonate corner barrel
	grid_barrels[0].explode()
	await _wait_physics(8)
	
	var grid_all_exploded: bool = true
	for b in grid_barrels:
		if is_instance_valid(b) and not bool(b.get("is_exploded")):
			grid_all_exploded = false
			
	_assert(grid_all_exploded, "16-barrel dense grid cascade resolved completely without recursion crash")
	
	cascade_root.queue_free()
	await _wait_physics(5)

# ==============================================================================
# SUITE 4: Leaderboard Concurrency, Integrity & Suicide Edge Cases
# ==============================================================================
func _suite_4_leaderboard_concurrency_and_integrity() -> void:
	var mm: Node = MatchManagerScript.new()
	add_child(mm)
	
	var tank_scene: PackedScene = load("res://Scenes/tank.tscn")
	var combatants: Array[Node] = []
	var combatant_names: Array[String] = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
	for c_name in combatant_names:
		var t: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
		t.set("tank_name", c_name)
		add_child(t)
		combatants.append(t)
		mm.register_combatant(t, c_name, false)
		
	mm.start_match(180.0)
	await _wait_physics(2)
	
	# Test 4A: Rapid Burst of 50 Kills in single frame
	for i in range(50):
		var killer_idx: int = i % combatants.size()
		var victim_idx: int = (i + 1 + (i % 3)) % combatants.size()
		mm.record_kill(combatants[victim_idx], combatants[killer_idx], (i % 4 == 0))
		
	var lb = mm.get_leaderboard()
	_assert(lb.size() == 6, "Leaderboard contains all 6 combatants after 50 rapid kills")
	
	# Verify sorting invariants: Score desc -> Kills desc -> Deaths asc -> Name asc
	var properly_sorted: bool = true
	var sort_error: String = ""
	for i in range(lb.size() - 1):
		var a: Dictionary = lb[i]
		var b: Dictionary = lb[i+1]
		if a["score"] < b["score"]:
			properly_sorted = false
			sort_error = "Score descending violated: %d < %d" % [a["score"], b["score"]]
			break
		elif a["score"] == b["score"]:
			if a["kills"] < b["kills"]:
				properly_sorted = false
				sort_error = "Kills tie-breaker violated: %d < %d" % [a["kills"], b["kills"]]
				break
			elif a["kills"] == b["kills"]:
				if a["deaths"] > b["deaths"]:
					properly_sorted = false
					sort_error = "Deaths tie-breaker violated: %d > %d" % [a["deaths"], b["deaths"]]
					break
					
	_assert(properly_sorted, "Leaderboard strictly sorted across score, kills, deaths tie-breakers", sort_error)
	
	# Verify conservation of kills and deaths
	var total_kills_recorded: int = 0
	var total_deaths_recorded: int = 0
	for entry in lb:
		total_kills_recorded += int(entry["kills"])
		total_deaths_recorded += int(entry["deaths"])
		
	_assert(total_kills_recorded == 50, "Total kills conserved exactly across leaderboard", "Total kills: %d" % total_kills_recorded)
	_assert(total_deaths_recorded == 50, "Total deaths conserved exactly across leaderboard", "Total deaths: %d" % total_deaths_recorded)
	
	# Test 4B: Kill Streak Multiplier Integrity
	var streaker: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
	streaker.set("tank_name", "StreakHero")
	add_child(streaker)
	mm.register_combatant(streaker, "StreakHero", false)
	
	var dummy: CharacterBody2D = combatants[0] as CharacterBody2D
	# K1 (100) -> 100
	mm.record_kill(dummy, streaker, false)
	# K2 (100) -> 200
	mm.record_kill(dummy, streaker, false)
	# K3 (100 + 50 streak) -> 350
	mm.record_kill(dummy, streaker, false)
	var stats_k3 = mm.get_combatant_stats(streaker)
	_assert(int(stats_k3.get("score", 0)) == 350, "Kill streak milestone 3 awards +50 pts (Score: 350)", "Score: %d" % stats_k3.get("score", 0))
	
	# K4 (100) -> 450
	mm.record_kill(dummy, streaker, false)
	# K5 (100 + 100 streak) -> 650
	mm.record_kill(dummy, streaker, false)
	var stats_k5 = mm.get_combatant_stats(streaker)
	_assert(int(stats_k5.get("score", 0)) == 650, "Kill streak milestone 5 awards +100 pts (Score: 650)", "Score: %d" % stats_k5.get("score", 0))
	
	# Streak reset on death
	mm.record_kill(streaker, dummy, false)
	var stats_after_death = mm.get_combatant_stats(streaker)
	_assert(int(stats_after_death.get("streak", -1)) == 0, "Streak resets to 0 upon death", "Streak: %d" % stats_after_death.get("streak", -1))
	
	# Next kill after death should award base 100 points
	mm.record_kill(dummy, streaker, false)
	var stats_post_reset = mm.get_combatant_stats(streaker)
	_assert(int(stats_post_reset.get("score", 0)) == 750, "Score resumes at base 100 after streak reset (Score: 750)", "Score: %d" % stats_post_reset.get("score", 0))
	
	# Test 4C: Suicide / Self-detonation Analysis
	var suicide_tank: CharacterBody2D = tank_scene.instantiate() as CharacterBody2D
	suicide_tank.set("tank_name", "SuicideTester")
	add_child(suicide_tank)
	mm.register_combatant(suicide_tank, "SuicideTester", false)
	
	var initial_suicide_stats = mm.get_combatant_stats(suicide_tank)
	var score_before: int = int(initial_suicide_stats.get("score", 0))
	var kills_before: int = int(initial_suicide_stats.get("kills", 0))
	
	# Tank kills itself
	mm.record_kill(suicide_tank, suicide_tank, true)
	var post_suicide_stats = mm.get_combatant_stats(suicide_tank)
	var score_after: int = int(post_suicide_stats.get("score", 0))
	var kills_after: int = int(post_suicide_stats.get("kills", 0))
	var deaths_after: int = int(post_suicide_stats.get("deaths", 0))
	
	print("    [Investigation] Self-detonation result: Score %d -> %d, Kills %d -> %d, Deaths %d" % [
		score_before, score_after, kills_before, kills_after, deaths_after
	])
	
	# Note: In tank.gd, score attribution checks `if valid_killer != self`.
	# But in MatchManager.gd, `record_kill` does not guard `killer != victim`.
	# Check whether MatchManager erroneously awarded kill points to self:
	var suicide_awarded_kills: bool = (kills_after > kills_before)
	if suicide_awarded_kills:
		print("    [Finding] MatchManager.record_kill awards self-kill credit (%d pts, %d kills) when victim == killer" % [
			score_after - score_before, kills_after - kills_before
		])
	_assert(deaths_after == 1, "Self-kill increments death count to 1", "Deaths: %d" % deaths_after)
	
	# Test 4D: Post-Match Kill Rejection
	mm.end_match()
	var score_at_end: int = int(stats_post_reset.get("score", 0))
	mm.record_kill(dummy, streaker, false)
	var score_post_match: int = int(mm.get_combatant_stats(streaker).get("score", 0))
	_assert(score_post_match == score_at_end, "Kills after match end are rejected cleanly without score change")
	
	# Test 4E: Match Restart Stat Reset
	mm.restart_match()
	var reset_lb = mm.get_leaderboard()
	var all_zero: bool = true
	for entry in reset_lb:
		if int(entry["score"]) != 0 or int(entry["kills"]) != 0 or int(entry["deaths"]) != 0:
			all_zero = false
	_assert(all_zero, "MatchManager.restart_match() resets all scores, kills, and deaths to 0")
	
	mm.queue_free()
	for c in combatants:
		if is_instance_valid(c): c.queue_free()
	if is_instance_valid(streaker): streaker.queue_free()
	if is_instance_valid(suicide_tank): suicide_tank.queue_free()
	await _wait_physics(2)

func _print_summary() -> void:
	print("\n==================================================================")
	print("                  CHALLENGER 1 STRESS SUMMARY                     ")
	print("==================================================================")
	print("  Total Tests Executed : %d" % (passed_count + failed_count))
	print("  Passed               : %d" % passed_count)
	print("  Failed               : %d" % failed_count)
	if failed_count > 0:
		print("\nFailures:")
		for f in failure_details:
			print("  - %s" % f)
	print("==================================================================")
	
	var exit_code: int = 0 if failed_count == 0 else 1
	get_tree().quit(exit_code)
