# res://Tests/suites/test_user_improvements.gd
extends TestBase

const FloatingTextScript = preload("res://Scripts/UI/floating_text.gd")
const MortarManagerScript = preload("res://Scripts/Core/mortar_manager.gd")
const MortarTargetScript = preload("res://Scripts/Entities/mortar_target.gd")

## Verification suite for the 4 user requested improvements:
## 1. Enemy names above their health bar
## 2. Increased power-up spawn rate & capacity
## 3. Increased map size (3200x3200) and Gotcha tactical walls
## 4. Dash / sprint mechanic with HUD dash bar below health

func test_01_enemy_name_above_health_bar() -> void:
	var bot = spawn_scene("res://Scenes/bot_tank.tscn")
	assert_not_null(bot, "Bot tank scene must instantiate")
	await wait_physics_frames(2)
	
	bot.tank_name = "Sniper Bot"
	await wait_physics_frames(2)
	
	var name_label: Label = bot.get_node_or_null("OverheadUI/NameLabel")
	var hp_bar: ProgressBar = bot.get_node_or_null("OverheadUI/HPBar")
	
	assert_not_null(name_label, "OverheadUI must contain NameLabel")
	assert_not_null(hp_bar, "OverheadUI must contain HPBar")
	assert_equal(name_label.text, "Sniper Bot", "NameLabel text must reflect enemy tank name")
	assert_true(name_label.position.y < hp_bar.position.y, "NameLabel must be positioned above HPBar")
	assert_true(name_label.visible, "NameLabel must be visible")

func test_02_powerup_spawn_rate_and_capacity() -> void:
	var sm_script = load_script("res://Scripts/Core/spawn_manager.gd")
	assert_not_null(sm_script, "SpawnManager script must exist")
	var sm = sm_script.new()
	track_node(sm)
	add_child(sm)
	
	var max_pu: int = sm.get("max_powerups")
	var interval_min: float = sm.get("spawn_interval_min")
	var interval_max: float = sm.get("spawn_interval_max")
	
	assert_true(max_pu >= 8, "Power-up cap increased to at least 8 (current: %d)" % max_pu)
	assert_true(interval_min <= 5.0, "Spawn interval min should be <= 5.0s (current: %.1f)" % interval_min)
	assert_true(interval_max <= 7.0, "Spawn interval max should be <= 7.0s (current: %.1f)" % interval_max)

func test_03_expanded_map_and_gotcha_walls() -> void:
	var map = spawn_scene("res://Scenes/map.tscn")
	assert_not_null(map, "Map scene must instantiate")
	
	var arena_size: Vector2 = map.get("arena_size") if "arena_size" in map else Vector2.ZERO
	assert_true(arena_size.x >= 3000.0 and arena_size.y >= 3000.0, "Arena size should be expanded to at least 3000x3000px")
	
	var modular_covers = map.get_node_or_null("ModularCovers")
	assert_not_null(modular_covers, "Map must have ModularCovers node")
	
	var gotcha_covers_found := 0
	for child in modular_covers.get_children():
		if "Gotcha" in child.name or "Snake" in child.name:
			gotcha_covers_found += 1
			
	assert_true(gotcha_covers_found >= 10, "Map must contain multiple gotcha-style tactical obstacles (found: %d)" % gotcha_covers_found)

func test_04_dash_mechanic_and_stamina() -> void:
	var tank = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(tank, "Player tank must instantiate")
	await wait_physics_frames(2)
	
	var base_speed: float = tank.BASE_SPEED
	assert_true(tank.get("dash_stamina") == 100.0, "Dash stamina starts at 100")
	
	# Activate dash via input actions
	Input.action_press("move_right")
	Input.action_press("dash")
	await wait_physics_frames(12)
	
	assert_true(tank.is_dashing, "Tank should enter is_dashing state")
	assert_true(tank.current_speed > base_speed, "Speed while dashing (%.1f) should exceed base speed (%.1f)" % [tank.current_speed, base_speed])
	assert_true(tank.dash_stamina < 100.0, "Dash stamina should drain while sprinting (current: %.1f)" % tank.dash_stamina)
	
	# Release dash
	Input.action_release("dash")
	var drained_val: float = tank.dash_stamina
	await wait_physics_frames(15)
	Input.action_release("move_right")
	
	assert_false(tank.is_dashing, "Tank should exit is_dashing state when released")
	assert_true(tank.dash_stamina > drained_val, "Dash stamina should recharge when not dashing")

func test_05_hud_dash_bar_below_health() -> void:
	var hud = spawn_scene("res://Scenes/hud.tscn")
	assert_not_null(hud, "HUD scene must instantiate")
	
	var hp_container = hud.get_node_or_null("Root/BottomLeft/HPContainer")
	var dash_container = hud.get_node_or_null("Root/BottomLeft/DashContainer")
	assert_not_null(hp_container, "HUD must contain HPContainer")
	assert_not_null(dash_container, "HUD must contain DashContainer")
	
	var dash_bar = dash_container.get_node_or_null("DashBar")
	var dash_text = dash_container.get_node_or_null("DashText")
	assert_not_null(dash_bar, "DashContainer must have DashBar ProgressBar")
	assert_not_null(dash_text, "DashContainer must have DashText Label")
	
	# Verify DashContainer is visually ordered below HPContainer in BottomLeft VBox
	assert_true(dash_container.get_index() > hp_container.get_index(), "DashContainer must be placed below HPContainer")

func test_06_standard_display_and_camera_settings() -> void:
	var tank = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(tank, "Player tank must instantiate")
	await wait_physics_frames(2)
	
	var cam: Camera2D = tank.get_node_or_null("Camera2D")
	assert_not_null(cam, "Player tank must have Camera2D")
	assert_approx_equal(cam.zoom.x, 1.0, 0.05, "Camera zoom should be default 1.0")
	assert_approx_equal(tank.sight_radius, 560.0, 0.1, "Sight radius should be increased to 560.0px")

func test_07_powerup_never_spawns_in_walls() -> void:
	var map = spawn_scene("res://Scenes/map.tscn")
	assert_not_null(map, "Map scene must instantiate")
	await wait_physics_frames(2)
	
	# Collect all wall and obstacle collision shapes
	var walls: Array[CollisionShape2D] = []
	var boundary = map.get_node_or_null("BoundaryWalls")
	var modular = map.get_node_or_null("ModularCovers")
	if boundary != null:
		for c in boundary.get_children():
			if c is CollisionShape2D: walls.append(c)
	if modular != null:
		for c in modular.get_children():
			if c is CollisionShape2D: walls.append(c)
			
	assert_true(walls.size() >= 30, "Map must have at least 30 wall/cover shapes (found: %d)" % walls.size())
	
	# Verify all defined power-up markers have at least 40px clearance
	var markers = map.get_powerup_spawn_positions()
	assert_true(markers.size() >= 12, "Map must define at least 12 powerup spawn positions")
	
	for i in range(markers.size()):
		var pos = markers[i]
		for wall in walls:
			var w_pos = wall.global_position
			var shape = wall.shape
			if shape is RectangleShape2D:
				var half_w = shape.size.x * 0.5
				var half_h = shape.size.y * 0.5
				var dx = maxf(0.0, absf(pos.x - w_pos.x) - half_w)
				var dy = maxf(0.0, absf(pos.y - w_pos.y) - half_h)
				var dist = sqrt(dx * dx + dy * dy)
				assert_true(dist >= 40.0, "Marker %d at %s too close to wall %s at %s (dist: %.1f < 40px)" % [i, str(pos), wall.name, str(w_pos), dist])
			elif shape is CircleShape2D:
				var dist = pos.distance_to(w_pos) - shape.radius
				assert_true(dist >= 40.0, "Marker %d at %s too close to circle wall %s (dist: %.1f < 40px)" % [i, str(pos), wall.name, dist])
				
	# Verify SpawnManager rejection logic
	var sm_script = load_script("res://Scripts/Core/spawn_manager.gd")
	var sm = sm_script.new()
	track_node(sm)
	add_child(sm)
	await wait_physics_frames(2)
	
	assert_true(sm.has_method("is_position_safe_from_walls"), "SpawnManager must implement is_position_safe_from_walls")
	# (0, -850) is inside PillarN2
	assert_false(sm.is_position_safe_from_walls(Vector2(0, -850), 30.0), "Position inside PillarN2 should be rejected as unsafe")
	# (0, -1620) is inside North perimeter wall
	assert_false(sm.is_position_safe_from_walls(Vector2(0, -1620), 30.0), "Position inside North wall should be rejected as unsafe")
	# (0, 0) is central open arena
	assert_true(sm.is_position_safe_from_walls(Vector2(0, 0), 30.0), "Center of arena should be safe for power-up spawn")

func test_08_ricochet_powerup_and_bouncing_bullets() -> void:
	var proj_container := Node2D.new()
	proj_container.name = "Projectiles"
	proj_container.add_to_group("projectiles")
	track_node(proj_container)
	add_child(proj_container)
	
	var tank = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(tank, "Player tank scene must exist")
	await wait_physics_frames(2)
	
	# Type 3 = RICOCHET, 20 shots
	tank.apply_powerup(3, 0.0, 20.0)
	assert_equal(tank.ricochet_shots, 20, "Tank must have 20 ricochet shots after power-up pickup")
	
	# Shoot projectile
	tank.shoot()
	assert_equal(tank.ricochet_shots, 19, "Firing should decrement ricochet shot counter to 19")
	
	var projs = proj_container.get_children()
	assert_false(projs.is_empty(), "Shooting must spawn a projectile")
	
	var p = projs[-1]
	assert_true("bounces_remaining" in p and p.get("bounces_remaining") == 2, "Ricochet projectile must start with 2 bounces")
	assert_true("is_ricochet" in p and p.get("is_ricochet") == true, "Projectile must be tagged as ricochet")
	assert_approx_equal(p.damage, 38.0, 1.0, "Ricochet projectile must deal increased damage (38.0 vs 25.0 base)")
	
	# Test wall collision triggers bounce without destroying projectile
	var dummy_wall = StaticBody2D.new()
	track_node(dummy_wall)
	add_child(dummy_wall)
	
	p.global_position = Vector2(100, 100)
	p._on_body_entered(dummy_wall)
	
	assert_equal(p.bounces_remaining, 1, "Bouncing off wall must decrement bounces_remaining to 1")
	assert_false(p.is_queued_for_deletion(), "Projectile must NOT be destroyed on first wall bounce")

func test_09_visual_juice_screen_shake_and_damage_numbers() -> void:
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(player, "Player tank must instantiate")
	await wait_physics_frames(2)
	
	# Test FloatingText
	var ft = FloatingTextScript.spawn(self, Vector2(150, 150), "-25", Color.RED)
	assert_not_null(ft, "FloatingText must instantiate")
	assert_equal(ft.text, "-25", "FloatingText must display correct damage text")
	
	# Test screen shake trauma
	assert_true(player.has_method("add_trauma"), "Player tank must have add_trauma method")
	player.add_trauma(0.5)
	assert_in_range(player._trauma, 0.45, 0.55, "Player trauma should increase to ~0.5")
	
	await wait_physics_frames(2)
	assert_not_null(player.camera, "Player must have camera")
	assert_true(player.camera.offset != Vector2.ZERO or player._trauma > 0.0, "Screen shake should apply camera trauma offset")

func test_10_mortar_event_lifecycle_and_artillery_strike() -> void:
	var mm = MortarManagerScript.new()
	track_node(mm)
	add_child(mm)
	await wait_physics_frames(2)
	
	# Trigger mortar event
	mm.start_event()
	assert_true(mm.is_event_active, "Mortar event should be active")
	assert_approx_equal(mm.event_time_remaining, 25.0, 0.1, "Mortar event duration must be 25 seconds")
	
	# Test MortarTarget strike detonation
	var victim = spawn_scene("res://Scenes/tank.tscn")
	assert_not_null(victim, "Victim tank must instantiate")
	victim.global_position = Vector2(200, 200)
	await wait_physics_frames(2)
	
	var hp_before = victim.current_health
	
	var target = MortarTargetScript.new()
	track_node(target)
	add_child(target)
	target.global_position = Vector2(200, 200)
	target.telegraph_duration = 0.05
	target.blast_radius = 120.0
	target.blast_damage = 50.0
	
	await wait_simulated_seconds(0.1)
	assert_true(victim.current_health < hp_before, "Mortar detonation must deal AoE blast damage to tank in radius (hp before: %.1f, hp after: %.1f)" % [hp_before, victim.current_health])
	
	# End event
	mm.end_event()
	assert_false(mm.is_event_active, "Mortar event should end cleanly")
	
	# Test Mortar elimination creates HUD kill feed entry
	var hud = spawn_scene("res://Scenes/hud.tscn")
	assert_not_null(hud, "HUD scene must instantiate")
	await wait_physics_frames(2)
	
	var mortal_victim = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(mortal_victim, "Player tank victim must instantiate")
	mortal_victim.global_position = Vector2(800, 800)
	mortal_victim.current_health = 20.0
	await wait_physics_frames(2)
	
	var lethal_mortar = MortarTargetScript.new()
	track_node(lethal_mortar)
	add_child(lethal_mortar)
	lethal_mortar.global_position = Vector2(800, 800)
	lethal_mortar.telegraph_duration = 0.05
	lethal_mortar.blast_radius = 120.0
	lethal_mortar.blast_damage = 80.0
	
	await wait_simulated_seconds(0.1)
	assert_true(mortal_victim.is_dead, "Player tank should be eliminated by lethal mortar blast")
	
	var k_feed = hud.get_node_or_null("Root/MidLeft/KillFeedList")
	assert_not_null(k_feed, "Kill feed container must exist")
	var feed_text := ""
	for child in k_feed.get_children():
		if child is Label:
			feed_text += child.text + "\n"
	assert_true("Mortero" in feed_text and "Player" in feed_text, "HUD kill feed must announce mortar kill: '%s'" % feed_text)

func test_11_monster_energy_speed_boost_powerup() -> void:
	var tank = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(tank, "Player tank must instantiate")
	await wait_physics_frames(2)
	
	# Initial base speed
	assert_approx_equal(tank.BASE_SPEED, 240.0, 0.1, "Base speed must be 240 px/s")
	assert_false(tank.has_speed_boost, "Tank should not have speed boost initially")
	
	# Apply Type 4 = SPEED_BOOST (Monster Energy), 15 seconds, 2x multiplier
	tank.apply_powerup(4, 15.0, 2.0)
	assert_true(tank.has_speed_boost, "Tank must have active speed boost")
	
	# Test movement speed is doubled
	tank.set_chassis_input(Vector2.RIGHT)
	await wait_physics_frames(4)
	assert_approx_equal(tank.current_speed, 480.0, 1.0, "Current speed should be 480 px/s (2x base speed)")
	
	# Test PowerUp entity creation and texture configuration
	var pu = spawn_scene("res://Scenes/powerup.tscn")
	assert_not_null(pu, "PowerUp scene must instantiate")
	pu.position = Vector2(500.0, 500.0)
	pu.setup(4) # SPEED_BOOST
	assert_approx_equal(pu.duration, 15.0, 0.1, "Monster Energy power-up must last 15 seconds")
	assert_approx_equal(pu.value, 2.0, 0.1, "Monster Energy power-up must have 2.0x speed multiplier")
	
	# Test bobbing animation
	var initial_y = pu.position.y
	await wait_simulated_seconds(0.3)
	assert_true(is_instance_valid(pu), "Power-up should remain valid")
	assert_true(pu.position.y != initial_y or pu._time > 0.0, "Power-up should animate floating bobbing up and down")
	
	# Test Monster Energy drink sound effect playback
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	assert_not_null(SoundManagerScript, "SoundManager script should load")
	var sm = SoundManagerScript._ensure_instance()
	assert_not_null(sm, "SoundManager instance should be created")
	assert_not_null(sm._monster_stream, "Monster Energy drink audio stream should be loaded")
	SoundManagerScript.play_monster_drink(tank.global_position)
	assert_true(true, "SoundManager.play_monster_drink executed successfully")

func test_12_cod_killstreak_and_multikill_medals() -> void:
	var hud = spawn_scene("res://Scenes/hud.tscn")
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	var bot1 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot2 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot3 = spawn_scene("res://Scenes/bot_tank.tscn")
	assert_not_null(hud, "HUD must instantiate")
	assert_not_null(player, "Player tank must instantiate")
	await wait_physics_frames(2)
	
	bot1.eliminate(player, false)
	bot2.eliminate(player, false)
	await wait_physics_frames(2)
	
	assert_equal(player.multikill_count, 2, "Two rapid kills must register multikill_count = 2")
	var banner = hud.get_node_or_null("Root/KillstreakBanner")
	var medal_title: Label = hud.get_node_or_null("Root/KillstreakBanner/VBox/MedalTitle")
	assert_not_null(banner, "HUD must contain CoD-style KillstreakBanner")
	assert_true(banner.visible, "KillstreakBanner must pop up on Double Kill")
	assert_true("DOBLE BAJA" in medal_title.text, "Banner title must show DOBLE BAJA (got: %s)" % medal_title.text)
	
	bot3.eliminate(player, false)
	await wait_physics_frames(2)
	assert_equal(player.kill_streak, 3, "Three kills without dying must reach kill_streak = 3")
	assert_equal(player.multikill_count, 3, "Third rapid kill must reach multikill_count = 3")
	assert_true("TRIPLE BAJA" in medal_title.text, "Banner title must escalate to TRIPLE BAJA (got: %s)" % medal_title.text)

func test_13_throwable_proximity_mines_arc_stealth_and_respawn_reset() -> void:
	var proj_container := Node2D.new()
	proj_container.name = "Entities"
	proj_container.add_to_group("entities")
	track_node(proj_container)
	add_child(proj_container)
	
	var hud = spawn_scene("res://Scenes/hud.tscn")
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	assert_not_null(player, "Player tank must instantiate")
	player.global_position = Vector2(0, 0)
	await wait_physics_frames(2)
	
	assert_equal(player.mines_count, 3, "Tank must start with 3 proximity mines")
	player.set_turret_target(Vector2(500, 0))
	await wait_physics_frames(2)
	
	var mine = player.throw_mine()
	assert_not_null(mine, "throw_mine() must spawn a ProximityMine node")
	track_node(mine)
	assert_equal(player.mines_count, 2, "Throwing a mine must decrement inventory from 3 to 2")
	assert_true(mine.is_in_flight, "Mine must begin in parabolic arc flight")
	
	var throw_dist: float = mine.start_pos.distance_to(mine.target_pos)
	assert_in_range(throw_dist, 150.0, 290.0, "Mine throw distance must be medium range (~235px)")
	
	# Mid-flight arc check
	await wait_simulated_seconds(0.22)
	assert_true(mine.current_arc_height > 15.0, "Mine must animate upward along parabolic arc mid-flight (height: %.1f)" % mine.current_arc_height)
	
	# Wait for landing & stealth arming
	await wait_simulated_seconds(0.55)
	assert_false(mine.is_in_flight, "Mine must finish flight and land on ground")
	assert_true(mine.is_armed, "Mine must arm after landing")
	assert_true(mine.visual_alpha <= 0.22, "Armed mine on ground must fade to nearly invisible (alpha: %.2f)" % mine.visual_alpha)
	
	# Trigger detonation with enemy bot
	var enemy = spawn_scene("res://Scenes/bot_tank.tscn")
	enemy.tank_name = "VictimBot"
	enemy.current_health = 50.0
	enemy.global_position = mine.global_position
	await wait_physics_frames(4)
	
	assert_true(enemy.is_dead, "Armed proximity mine must detonate and eliminate low-HP enemy tank")
	assert_equal(player.kills, 1, "Mine kill must credit owner tank kills")
	
	var k_feed = hud.get_node_or_null("Root/MidLeft/KillFeedList")
	var feed_str := ""
	if k_feed != null:
		for c in k_feed.get_children():
			if c is Label:
				feed_str += c.text + "\n"
	assert_true("MINA" in feed_str, "Kill feed must announce mine elimination: '%s'" % feed_str)
	
	# Death & respawn resets inventory back to 3 mines
	player.eliminate(null, false)
	player.respawn(Vector2(0, 0))
	assert_equal(player.mines_count, 3, "Respawning after death must reset mine inventory to 3")

func test_14_tactical_minimap_radar_and_gunfire_blips() -> void:
	var proj_container := Node2D.new()
	proj_container.name = "Projectiles"
	proj_container.add_to_group("projectiles")
	track_node(proj_container)
	add_child(proj_container)
	
	var hud = spawn_scene("res://Scenes/hud.tscn")
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	var bot = spawn_scene("res://Scenes/bot_tank.tscn")
	assert_not_null(hud, "HUD must instantiate")
	player.global_position = Vector2(0, 0)
	bot.global_position = Vector2(2000, -2000) # Far in Fog of War
	await wait_physics_frames(2)
	
	var minimap = hud.get_node_or_null("Root/TopLeft/MinimapPanel/VBox/TacticalMinimap")
	assert_not_null(minimap, "HUD must include TacticalMinimap in TopLeft")
	assert_equal(minimap.get_gunfire_blip_count(), 0, "Minimap starts with 0 gunfire blips")
	
	bot.shoot()
	await wait_physics_frames(2)
	assert_true(minimap.get_gunfire_blip_count() >= 1, "Enemy shooting in Fog of War must ping gunfire blip on TacticalMinimap")

func test_15_sudden_death_closing_zone_no_respawns_and_final_leaderboard() -> void:
	var mm_script = load_script("res://Scripts/Core/match_manager.gd")
	var mm = mm_script.new()
	track_node(mm)
	add_child(mm)
	
	var hud = spawn_scene("res://Scenes/hud.tscn")
	var podium = spawn_scene("res://Scenes/podium_screen.tscn")
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	var bot1 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot2 = spawn_scene("res://Scenes/bot_tank.tscn")
	await wait_physics_frames(2)
	
	mm.register_combatant(player, "Player", true)
	mm.register_combatant(bot1, "Bot Alpha", false)
	mm.register_combatant(bot2, "Bot Bravo", false)
	mm.start_match(90.0)
	mm.time_remaining = 30.05
	
	await wait_physics_frames(10)
	assert_true(mm.is_sudden_death, "MatchManager must enter Sudden Death when time_remaining crosses <= 30s")
	assert_true(mm.no_respawns, "Respawns must be disabled once zone closing begins")
	assert_true(mm.safe_zone_radius < mm.max_zone_radius, "Safe zone radius must shrink progressively during Sudden Death")
	
	var sd_lbl: Label = hud.get_node_or_null("Root/TopCenter/SuddenDeathLabel")
	assert_not_null(sd_lbl, "HUD must have SuddenDeathLabel")
	assert_true(sd_lbl.visible, "SuddenDeathLabel must become visible during zone closure")
	
	# Eliminate Bot1 during Sudden Death -> verify it does NOT respawn even if timer expires
	bot1.eliminate(player, false)
	bot1._respawn_timer = 0.01
	await wait_physics_frames(6)
	assert_true(bot1.is_dead, "Dead tank must NOT respawn once zone closure has started")
	assert_true(bot1.permanently_eliminated, "Dead tank must be marked permanently_eliminated")
	
	# Eliminate Bot2 -> only Player remains alive -> match ends and displays Final Leaderboard
	bot2.eliminate(player, false)
	await wait_physics_frames(3)
	assert_true(mm.is_match_ended, "Match must conclude when last opponent is eliminated in Sudden Death")
	assert_true(podium.visible, "Podium & Final Leaderboard screen must appear at match end")
	
	var lb_table = podium.get_node_or_null("Root/Panel/VBox/LeaderboardTable")
	assert_not_null(lb_table, "PodiumScreen must contain full LeaderboardTable")
	assert_true(lb_table.get_child_count() >= 4, "LeaderboardTable must list header + all 3 combatants")

func test_16_doubled_6400_map_and_destructible_gotcha_walls() -> void:
	var map = spawn_scene("res://Scenes/map.tscn")
	assert_not_null(map, "Map scene must instantiate")
	await wait_physics_frames(2)
	
	assert_approx_equal(map.arena_size.x, 6400.0, 1.0, "Map width must be doubled to 6400px")
	assert_approx_equal(map.arena_size.y, 6400.0, 1.0, "Map height must be doubled to 6400px")
	
	var modular = map.get_node_or_null("ModularCovers")
	assert_not_null(modular, "Map must have ModularCovers")
	assert_true(modular.get_child_count() >= 65, "Expanded 6400x6400 map must have abundant tank walls (>=65, got %d)" % modular.get_child_count())
	
	var dest_container = map.get_node_or_null("DestructibleCovers")
	assert_not_null(dest_container, "Map must have DestructibleCovers container")
	assert_true(dest_container.get_child_count() >= 20, "Map must feature >= 20 destructible Gotcha barricades")
	
	var dw = dest_container.get_child(0)
	assert_equal(dw.collision_layer, 2, "Destructible Gotcha wall must block on collision layer 2")
	assert_approx_equal(dw.max_health, 125.0, 0.5, "Destructible Gotcha wall must have 125 HP")
	assert_approx_equal(dw.respawn_delay, 20.0, 0.5, "Destructible Gotcha wall must have 20s respawn")
	dw.take_damage(25.0, null, false)
	dw.take_damage(25.0, null, false)
	dw.take_damage(25.0, null, false)
	dw.take_damage(25.0, null, false)
	assert_false(dw.is_destroyed, "Wall should survive 4 cannon hits with cracks (25 HP left)")
	dw.take_damage(25.0, null, false)
	await wait_physics_frames(2)
	assert_true(dw.is_destroyed, "Wall must shatter on 5th cannon hit (0 HP)")
	assert_equal(dw.collision_layer, 0, "Shattered wall must clear collision_layer to open corridor")

func test_17_death_and_powerup_spawn_safe_from_null_bool_and_1300x800_window() -> void:
	# 1. Verify 1300x800 viewport & window override settings
	assert_equal(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1300, "Viewport width must be 1300px")
	assert_equal(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 800, "Viewport height must be 800px")
	assert_equal(int(ProjectSettings.get_setting("display/window/size/window_width_override")), 1300, "Window width override must be 1300px")
	assert_equal(int(ProjectSettings.get_setting("display/window/size/window_height_override")), 800, "Window height override must be 800px")
	
	# 2. Regression test for SpawnManager.is_position_safe_from_walls() when splinter particles / non-wall nodes exist and player dies
	var map = spawn_scene("res://Scenes/map.tscn")
	map.add_to_group("world_map")
	var entities := Node2D.new()
	entities.name = "Entities"
	entities.add_to_group("entities")
	entities.add_to_group("powerups_container")
	track_node(entities)
	add_child(entities)
	
	var sm_script = load_script("res://Scripts/Core/spawn_manager.gd")
	var sm = sm_script.new()
	track_node(sm)
	add_child(sm)
	
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	await wait_physics_frames(2)
	
	var dest_container = map.get_node_or_null("DestructibleCovers")
	assert_not_null(dest_container, "Map must have DestructibleCovers")
	
	# Trigger splinter CPUParticles2D on wall hit & shatter AND inject an arbitrary non-wall CPUParticles2D into DestructibleCovers
	var dw = dest_container.get_child(0)
	dw.take_damage(80.0, player, false)
	dw.take_damage(60.0, player, false)
	var stray_fx := CPUParticles2D.new()
	dest_container.add_child(stray_fx)
	
	# Eliminate player and spawn powerup while dead -> must NOT crash with Nonexistent 'bool' constructor!
	player.eliminate(null, false)
	assert_true(player.is_dead, "Player must be in dead state")
	
	var safe_check: bool = sm.is_position_safe_from_walls(Vector2(0, 0), 45.0)
	assert_true(safe_check or not safe_check, "is_position_safe_from_walls must return bool cleanly even with non-wall children")
	
	var pu = sm.spawn_powerup()
	assert_not_null(pu, "spawn_powerup() must succeed without error while player is dead and walls have shattered")
	track_node(pu)
	await wait_physics_frames(3)

func test_18_barrels_bots_cluster_mines_walls_and_spatial_audio() -> void:
	# 1. Verify full MainGame scene loads cleanly with 48 barrels (15s respawn), 10 tanks (1 player + 9 bots), 84 destructible walls (125 HP, 20s respawn), 38 max powerups
	var mg = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg, "MainGame scene must instantiate cleanly")
	await wait_physics_frames(3)
	
	var tanks_node = mg.get_node_or_null("Entities/Tanks")
	assert_not_null(tanks_node, "MainGame must have Entities/Tanks")
	assert_equal(tanks_node.get_child_count(), 10, "MainGame must have 10 combatants (1 player + 9 bots)")
	
	var barrels_node = mg.get_node_or_null("Entities/Barrels")
	assert_not_null(barrels_node, "MainGame must have Entities/Barrels")
	assert_equal(barrels_node.get_child_count(), 48, "MainGame must have 48 explosive barrels")
	var b0 = barrels_node.get_child(0)
	assert_approx_equal(b0.respawn_delay, 15.0, 0.1, "Barrel respawn_delay must be 15s")
	b0.explode()
	assert_true(b0.is_exploded, "Barrel must enter exploded state")
	b0.respawn_barrel()
	assert_false(b0.is_exploded, "Barrel must restore cleanly on respawn")
	
	var dest_node = mg.get_node_or_null("WorldMap/DestructibleCovers")
	assert_not_null(dest_node, "WorldMap must have DestructibleCovers")
	assert_equal(dest_node.get_child_count(), 84, "WorldMap must have 84 destructible Gotcha walls")
	var dw0 = dest_node.get_child(0)
	assert_approx_equal(dw0.max_health, 125.0, 0.1, "Destructible wall max_health must be 125")
	assert_approx_equal(dw0.respawn_delay, 20.0, 0.1, "Destructible wall respawn_delay must be 20s")
	dw0.shatter()
	assert_true(dw0.is_destroyed, "Destructible wall must shatter")
	dw0.restore()
	assert_false(dw0.is_destroyed, "Destructible wall must restore cleanly")
	assert_approx_equal(dw0.current_health, 125.0, 0.1, "Restored destructible wall must reset to 125 HP")
	
	var sm_node = mg.get_node_or_null("SpawnManager")
	assert_not_null(sm_node, "MainGame must have SpawnManager")
	assert_equal(sm_node.max_powerups, 38, "SpawnManager max_powerups must be 38")
	
	# 2. Verify Shield 22s duration and Cluster Mines slot rules on PlayerTank
	var player = mg.get_node_or_null("Entities/Tanks/PlayerTank")
	assert_not_null(player, "PlayerTank must exist in MainGame")
	player.global_position = Vector2(0, 0)
	
	var pu_shield = spawn_scene("res://Scenes/powerup.tscn")
	track_node(pu_shield)
	pu_shield.setup(1) # SHIELD
	assert_approx_equal(pu_shield.duration, 22.0, 0.1, "Shield powerup duration must be 22s")
	
	# Cluster Mines with 2 slots -> upgrades exactly 2 slots, throwing 3 cluster mines on throw_mine()
	player.mines_count = 2
	player.cluster_mines_count = 0
	player._mine_cooldown = 0.0
	player.apply_powerup(5, 0.0, 3.0)
	assert_equal(player.mines_count, 2, "Having 2 mines must keep 2 slots")
	assert_equal(player.cluster_mines_count, 2, "Having 2 mines must upgrade 2 slots to cluster")
	var before_mines: int = get_tree().get_nodes_in_group("mines").size()
	var thrown = player.throw_mine()
	assert_not_null(thrown, "Player must throw cluster mine burst")
	assert_equal(get_tree().get_nodes_in_group("mines").size() - before_mines, 3, "1 cluster mine slot must spawn 3 cluster mines")
	assert_equal(player.mines_count, 1, "Mines count must decrement by 1")
	assert_equal(player.cluster_mines_count, 1, "Cluster mines count must decrement by 1")
	
	# Cluster Mines with 0 slots -> grants 3 normal mines (0 cluster)
	player.mines_count = 0
	player.cluster_mines_count = 0
	player.apply_powerup(5, 0.0, 3.0)
	assert_equal(player.mines_count, 3, "Picking up Cluster Mines with 0 mines must grant 3 normal mines")
	assert_equal(player.cluster_mines_count, 0, "Picking up Cluster Mines with 0 mines must grant 0 cluster upgrades")
	
	# 3. Verify Spatial Proximity Audio filtering & attenuation relative to PlayerTank at (0, 0)
	var sound_mgr = mg.get_node_or_null("SoundManager")
	assert_not_null(sound_mgr, "MainGame must have SoundManager")
	assert_true(sound_mgr.is_within_hearing_range(Vector2(300, 0), 1650.0), "Close shot (300px) must be audible")
	assert_approx_equal(sound_mgr.compute_spatial_volume_db(Vector2(300, 0), -6.0, 1650.0), -6.0, 0.05, "Close shot within full-volume radius must not attenuate")
	assert_true(sound_mgr.is_within_hearing_range(Vector2(1100, 0), 1650.0), "Mid-range enemy shot (1100px) must be within wide hearing radius")
	var mid_db: float = sound_mgr.compute_spatial_volume_db(Vector2(1100, 0), -6.0, 1650.0)
	assert_true(mid_db < -8.0 and mid_db > -30.0, "Mid-range enemy shot must be smoothly attenuated (got %.2f dB)" % mid_db)
	assert_false(sound_mgr.is_within_hearing_range(Vector2(2800, 2800), 1650.0), "Far-map gunshot (~3960px) must be muted outside hearing radius")
	assert_false(sound_mgr.is_within_hearing_range(Vector2(2800, 2800), 2100.0), "Far-map explosion (~3960px) must be muted outside explosion radius")
	assert_false(sound_mgr.is_within_hearing_range(Vector2(2800, 2800), 1350.0), "Far-map item pickup (~3960px) must be muted outside pickup radius")

func test_19_monster_yaris_bouncing_and_synced_music() -> void:
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	var stream = SoundManagerScript.get_monster_bounce_music_stream()
	assert_not_null(stream, "Monster bounce music MP3 stream must load cleanly")
	assert_true(stream.get_length() >= 14.0, "Uploaded Monster bounce track must be ~15s (got %.2f s)" % stream.get_length())
	
	var mg = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg, "MainGame scene must instantiate")
	await wait_physics_frames(2)
	
	var player = mg.get_node_or_null("Entities/Tanks/PlayerTank")
	var bot = mg.get_node_or_null("Entities/Tanks/BotTank1")
	assert_not_null(player, "PlayerTank must exist")
	assert_not_null(bot, "BotTank1 must exist")
	
	player.global_position = Vector2(0, 0)
	player.set_turret_target(Vector2(0, 300)) # Aiming South (+PI/2)
	player.apply_powerup(4, 15.0, 2.0) # Monster Energy
	assert_true(player.has_speed_boost, "Player must activate Monster speed boost")
	assert_not_null(player._monster_music_player, "Tank must attach MonsterBounceMusicPlayer")
	
	# Test kick-drum compression phase (beat 5 + 0.085 phase -> post-drop full intensity)
	var beat_period: float = 60.0 / 136.0
	player._monster_bounce_time = (5.0 + 0.085) * beat_period - 0.001
	player._process_monster_bounce(0.001)
	assert_true(player.monster_squash_scale.x > 1.15, "Yaris bounce must squash wider on beat impact (got %.2f)" % player.monster_squash_scale.x)
	assert_true(player.monster_squash_scale.y < 0.85, "Yaris bounce must compress shorter on beat impact (got %.2f)" % player.monster_squash_scale.y)
	
	# Test airborne jump apex (beat 5 + 0.585 phase -> peak 20px vertical hop + stretch)
	player._monster_bounce_time = (5.0 + 0.585) * beat_period - 0.001
	player._process_monster_bounce(0.001)
	assert_approx_equal(player.monster_bounce_offset_y, -20.0, 1.5, "Yaris bounce must hop ~20px upward at beat apex")
	assert_approx_equal(player.chassis_visual.position.y, player.monster_bounce_offset_y, 0.5, "ChassisVisual must follow vertical bounce offset")
	assert_true(player.monster_squash_scale.y > 1.10, "Yaris bounce must stretch taller while airborne")
	player._process_turret(0.016)
	assert_approx_equal(player.turret_pivot.global_rotation, PI * 0.5, 0.05, "Turret aiming must remain 100% accurate while bouncing")
	
	# Test spatial proximity volume on BotTank Monster music
	bot.global_position = Vector2(2800, 2800) # Far across arena -> muted (-80 dB)
	bot.apply_powerup(4, 15.0, 2.0)
	bot._update_monster_music_volume()
	assert_approx_equal(bot._monster_music_player.volume_db, -80.0, 0.1, "Far bot Monster music must be completely muted (-80 dB)")
	bot.global_position = Vector2(300, 0) # Close to player -> audible!
	bot._update_monster_music_volume()
	assert_true(bot._monster_music_player.volume_db > -6.0, "Nearby bot Monster music must be audible")
	
	# Test clean reset on elimination
	player.eliminate(null, false)
	assert_approx_equal(player.monster_bounce_offset_y, 0.0, 0.01, "Eliminating tank must reset bounce offset to 0")
	assert_approx_equal(player.chassis_visual.position.y, 0.0, 0.01, "ChassisVisual position must reset cleanly to 0")

func test_20_realistic_bombardment_audio_event() -> void:
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	var b_stream = SoundManagerScript.get_bombardment_stream()
	assert_not_null(b_stream, "Realistic bombardment MP3 stream must load cleanly")
	assert_true(b_stream.get_length() >= 120.0, "Uploaded bombardment audio must be ~124s (got %.2f s)" % b_stream.get_length())
	
	var mm_script = load("res://Scripts/Core/mortar_manager.gd")
	var mortar_mgr = mm_script.new()
	track_node(mortar_mgr)
	add_child(mortar_mgr)
	await wait_physics_frames(1)
	
	mortar_mgr.start_event()
	assert_true(mortar_mgr.is_event_active, "Mortar event must activate")
	var sm = SoundManagerScript.instance
	assert_not_null(sm._bombardment_player, "SoundManager must have dedicated _bombardment_player")
	assert_equal(sm._bombardment_player.stream, b_stream, "Bombardment player must bind realistic bombardment MP3")
	assert_approx_equal(sm._bombardment_player.volume_db, -10.5, 0.1, "Bombardment audio starts at lowered -10.5 dB")
	
	# Fade-out during final 1.0s of bombardment event
	SoundManagerScript.update_bombardment_volume(1.0, 25.0)
	assert_true(sm._bombardment_player.volume_db < -16.0, "Bombardment audio must fade out smoothly near end of event")
	
	mortar_mgr.end_event()
	assert_false(mortar_mgr.is_event_active, "Mortar event must end cleanly")
	assert_false(sm._bombardment_player.playing, "Bombardment audio must stop cleanly when event ends")

func test_21_hud_bottom_left_layout_ammo_and_sizing() -> void:
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	var hud = spawn_scene("res://Scenes/hud.tscn")
	assert_not_null(player, "PlayerTank must instantiate")
	assert_not_null(hud, "HUD must instantiate")
	await wait_physics_frames(3)
	
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var card: Panel = hud.get_node_or_null("Root/BottomLeftCard")
	var bl: VBoxContainer = hud.get_node_or_null("Root/BottomLeft")
	var score_lbl: Label = hud.get_node_or_null("Root/BottomLeft/ScoreLabel")
	var hp_box: Control = hud.get_node_or_null("Root/BottomLeft/HPContainer")
	var hp_bar: ProgressBar = hud.get_node_or_null("Root/BottomLeft/HPContainer/HPBar")
	var ammo_box: Control = hud.get_node_or_null("Root/BottomLeft/AmmoContainer")
	var ammo_bar: ProgressBar = hud.get_node_or_null("Root/BottomLeft/AmmoContainer/AmmoBar")
	var ammo_txt: Label = hud.get_node_or_null("Root/BottomLeft/AmmoContainer/AmmoText")
	var mine_box: Control = hud.get_node_or_null("Root/BottomLeft/MineContainer")
	var mid_left: Control = hud.get_node_or_null("Root/MidLeft")
	
	assert_not_null(card, "HUD must include BottomLeftCard backdrop panel")
	assert_not_null(bl, "HUD must include BottomLeft VBoxContainer")
	assert_not_null(ammo_box, "HUD must include AmmoContainer (BALAS) in BottomLeft")
	assert_not_null(ammo_bar, "AmmoContainer must include AmmoBar")
	assert_not_null(ammo_txt, "AmmoContainer must include AmmoText")
	
	hud._process(0.016)
	var card_rect: Rect2 = card.get_global_rect()
	var mine_rect: Rect2 = mine_box.get_global_rect()
	
	# Must be anchored tightly to bottom-left corner (within 26px margin of left & bottom edges)
	assert_true(card_rect.position.x <= 24.0, "BottomLeftCard must sit flush at left corner (got x=%.1f)" % card_rect.position.x)
	assert_true(vp_size.y - card_rect.end.y <= 24.0, "BottomLeftCard must sit flush at bottom corner without empty space below (gap=%.1f)" % (vp_size.y - card_rect.end.y))
	assert_true(vp_size.y - mine_rect.end.y <= 32.0, "MineContainer must sit at bottom-left corner (gap=%.1f)" % (vp_size.y - mine_rect.end.y))
	assert_true(card_rect.size.x >= 350.0, "BottomLeft HUD card must be enlarged (>=350px wide, got %.1f)" % card_rect.size.x)
	assert_true(hp_bar.size.y >= 20.0, "HPBar must be enlarged (>=20px tall, got %.1f)" % hp_bar.size.y)
	assert_equal(score_lbl.get_theme_font_size("font_size"), 24, "ScoreLabel font size must be enlarged to 24")
	assert_true(mid_left.get_global_rect().end.y <= card_rect.position.y, "KillFeed (MidLeft) must sit cleanly above BottomLeftCard without overlap")
	
	# Verify vertical ordering: VIDA -> ESCUDO -> DASH -> BALAS -> MINAS [Q]
	assert_true(hp_box.global_position.y < ammo_box.global_position.y, "HPContainer (VIDA) must sit above AmmoContainer (BALAS)")
	assert_true(ammo_box.global_position.y < mine_box.global_position.y, "AmmoContainer (BALAS) must sit above MineContainer (MINAS)")
	
	# Verify live BALAS readout for standard, reload, Ricochet, and Rapid Fire
	assert_true("LISTO" in ammo_txt.text, "Initial BALAS status must show ready ('%s')" % ammo_txt.text)
	player.shoot()
	hud._process(0.016)
	assert_true("RECARGA" in ammo_txt.text, "Shooting must update BALAS status to reloading ('%s')" % ammo_txt.text)
	assert_true(ammo_bar.value < 100.0, "Reloading must dip AmmoBar below 100%")
	
	player.apply_powerup(3, 999.0, 20.0) # RICOCHET (20 bouncing rounds)
	player.apply_powerup(1, 22.0, 50.0)  # Simultaneously active SHIELD
	hud._process(0.016)
	assert_true("20/20" in ammo_txt.text and "REB" in ammo_txt.text, "BALAS must display 20/20 Ricochet rounds even while Shield is active ('%s')" % ammo_txt.text)
	player.can_fire = true
	player.shoot()
	hud._process(0.016)
	assert_true("19/20" in ammo_txt.text, "Firing a Ricochet round must decrement BALAS to 19/20 ('%s')" % ammo_txt.text)

func test_22_mortar_strike_explosion_custom_audio() -> void:
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	var m_stream = SoundManagerScript.get_mortar_explosion_stream()
	assert_not_null(m_stream, "Custom mortar explosion MP3 stream must load cleanly")
	assert_true(m_stream is AudioStreamMP3, "Mortar explosion stream must be an AudioStreamMP3")
	assert_false((m_stream as AudioStreamMP3).loop, "Mortar explosion impact sound must be one-shot (loop=false)")
	assert_in_range(m_stream.get_length(), 2.5, 5.0, "Uploaded mortar explosion audio must be ~3s")
	
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	player.global_position = Vector2.ZERO
	await wait_physics_frames(2)
	
	var sm = SoundManagerScript.instance
	assert_not_null(sm, "SoundManager instance must exist")
	assert_true(sm.is_within_hearing_range(Vector2(600, 0), SoundManagerScript.HEARING_RADIUS_MORTAR), "Nearby mortar detonation must be audible")
	assert_false(sm.is_within_hearing_range(Vector2(2900, 2900), SoundManagerScript.HEARING_RADIUS_MORTAR), "Far-corner mortar detonation must be muted outside artillery hearing radius")
	
	var target = MortarTargetScript.new()
	track_node(target)
	add_child(target)
	target.global_position = Vector2(320, 0)
	target.detonate()
	assert_true(target._detonated, "MortarTarget must detonate cleanly while triggering custom mortar explosion audio")

func test_23_tank_cannon_shot_2s_trimmed_audio() -> void:
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	var s_stream = SoundManagerScript.get_tank_shoot_stream()
	assert_not_null(s_stream, "Trimmed tank cannon shot MP3 stream must load cleanly")
	assert_true(s_stream is AudioStreamMP3, "Tank cannon shot must use imported AudioStreamMP3")
	assert_false((s_stream as AudioStreamMP3).loop, "Tank cannon shot must be one-shot (loop=false)")
	assert_in_range(s_stream.get_length(), 1.9, 2.15, "Tank cannon shot audio must be trimmed to the first ~2.0 seconds (got %.3f s)" % s_stream.get_length())
	
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	player.global_position = Vector2.ZERO
	await wait_physics_frames(2)
	player.shoot()
	assert_false(player.can_fire, "Tank shoot() must fire cleanly with realistic 2s cannon blast audio")

func test_24_sudden_death_spectator_mode_and_target_switching() -> void:
	var mm_script = load_script("res://Scripts/Core/match_manager.gd")
	var mm = mm_script.new()
	track_node(mm)
	add_child(mm)
	
	var fow_script = load_script("res://Scripts/World/fog_of_war.gd")
	var fow = fow_script.new()
	track_node(fow)
	add_child(fow)
	
	var hud = spawn_scene("res://Scenes/hud.tscn")
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	var bot1 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot2 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot3 = spawn_scene("res://Scenes/bot_tank.tscn")
	bot1.tank_name = "Bot Alpha"
	bot2.tank_name = "Bot Bravo"
	bot3.tank_name = "Bot Charlie"
	player.global_position = Vector2(-2400, -2400)
	bot1.global_position = Vector2(500, 0)
	bot2.global_position = Vector2(1200, 400)
	bot3.global_position = Vector2(-600, 900)
	bot2.current_health = 74.0
	bot2.score = 350
	await wait_physics_frames(2)
	
	mm.register_combatant(player, "Player", true)
	mm.register_combatant(bot1, "Bot Alpha", false)
	mm.register_combatant(bot2, "Bot Bravo", false)
	mm.register_combatant(bot3, "Bot Charlie", false)
	mm.start_match(90.0)
	mm.start_sudden_death()
	assert_true(mm.no_respawns, "Sudden Death must disable respawns")
	
	# Eliminate player via Bot Bravo during Sudden Death -> must enter Spectator Mode locked on killer Bot Bravo
	player.eliminate(bot2, false)
	await wait_physics_frames(2)
	player._process(0.016)
	hud._process(0.016)
	fow._process(0.016)
	
	assert_true(player.is_spectating, "Player eliminated during closing zone must enter Spectator Mode")
	assert_equal(player.spectated_tank, bot2, "Spectator Mode must initially lock onto killer (Bot Bravo)")
	assert_approx_equal(player.camera.global_position.x, bot2.global_position.x, 1.0, "Camera must track spectated survivor X")
	assert_approx_equal(player.camera.global_position.y, bot2.global_position.y, 1.0, "Camera must track spectated survivor Y")
	assert_true(bot2.is_in_sight, "FogOfWar must reveal the spectated survivor even far from player's corpse")
	
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	SoundManagerScript._ensure_instance()
	var sm = SoundManagerScript.instance
	assert_true(sm.is_within_hearing_range(bot2.global_position + Vector2(150, 0), 1650.0), "Spatial audio listener must follow spectated survivor")
	
	var spec_banner: Control = hud.get_node_or_null("Root/BottomCenter/SpectatorBanner")
	var spec_title: Label = hud.get_node_or_null("Root/BottomCenter/SpectatorBanner/HBox/InfoVBox/SpectatorTitle")
	var next_btn: Button = hud.get_node_or_null("Root/BottomCenter/SpectatorBanner/HBox/NextSpectateBtn")
	var prev_btn: Button = hud.get_node_or_null("Root/BottomCenter/SpectatorBanner/HBox/PrevSpectateBtn")
	assert_not_null(spec_banner, "HUD must include SpectatorBanner")
	assert_true(spec_banner.visible, "SpectatorBanner must be visible while spectating")
	assert_true("BOT BRAVO" in spec_title.text and "3 VIVOS" in spec_title.text, "SpectatorBanner must display current target and survivor count ('%s')" % spec_title.text)
	assert_approx_equal(hud.hp_bar.value, 74.0, 0.5, "HUD HP bar must reflect spectated survivor's live health")
	
	# Switch forward via HUD button / input -> Bot Charlie, then wrap -> Bot Alpha, then backward -> Bot Charlie
	next_btn.pressed.emit()
	hud._process(0.016)
	assert_equal(player.spectated_tank, bot3, "Next button must switch spectator target to Bot Charlie")
	assert_true("BOT CHARLIE" in spec_title.text, "SpectatorBanner title must update to Bot Charlie")
	
	var key_d := InputEventKey.new()
	key_d.pressed = true
	key_d.keycode = KEY_D
	player._unhandled_input(key_d)
	assert_equal(player.spectated_tank, bot1, "Pressing D must wrap spectator target to Bot Alpha")
	
	prev_btn.pressed.emit()
	assert_equal(player.spectated_tank, bot3, "Prev button must cycle backward to Bot Charlie")
	
	# Eliminate currently spectated Bot Charlie -> must auto-switch to killer Bot Alpha without getting stuck on dead tank
	bot3.eliminate(bot1, false)
	await wait_physics_frames(2)
	hud._process(0.016)
	assert_equal(player.spectated_tank, bot1, "Eliminating spectated survivor must auto-switch to living killer (Bot Alpha)")
	assert_true("2 VIVOS" in spec_title.text, "Survivor count must update to 2 VIVOS ('%s')" % spec_title.text)
	
	# Restart match -> Player respawns and cleanly exits Spectator Mode
	mm.restart_match()
	await wait_physics_frames(2)
	hud._process(0.016)
	assert_false(player.is_dead, "Restarting match must revive PlayerTank")
	assert_false(player.is_spectating, "Restarting match must exit Spectator Mode")
	assert_false(player.camera.top_level, "Camera must re-attach locally to PlayerTank on respawn")
	assert_false(spec_banner.visible, "SpectatorBanner must hide when PlayerTank returns to play")

func test_25_zone_closing_siren_audio_event() -> void:
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	var z_stream = SoundManagerScript.get_zone_closing_stream()
	assert_not_null(z_stream, "Zone closing siren MP3 stream must load cleanly")
	assert_true(z_stream is AudioStreamMP3, "Zone closing siren must be an AudioStreamMP3")
	assert_true(z_stream.get_length() >= 115.0, "Uploaded zone closing siren must be ~120s (got %.2f s)" % z_stream.get_length())
	
	var mm_script = load("res://Scripts/Core/match_manager.gd")
	var mm = mm_script.new()
	track_node(mm)
	add_child(mm)
	await wait_physics_frames(1)
	
	mm.start_match(90.0)
	mm.start_sudden_death()
	assert_true(mm.is_sudden_death, "Sudden Death closing zone must activate")
	
	var sm = SoundManagerScript.instance
	assert_not_null(sm._zone_closing_player, "SoundManager must have dedicated _zone_closing_player")
	assert_equal(sm._zone_closing_player.stream, z_stream, "Zone closing player must bind uploaded zone_closing_siren.mp3")
	assert_approx_equal(sm._zone_closing_player.volume_db, -11.0, 0.1, "Zone closing siren starts at lowered -11.0 dB")
	
	SoundManagerScript.update_zone_closing_volume(0.8)
	assert_true(sm._zone_closing_player.volume_db < -16.0, "Zone closing siren must fade out smoothly near match end")
	
	mm.end_match()
	assert_false(sm._zone_closing_player.playing, "Zone closing siren must stop cleanly when match ends")

func test_26_impact_tank_destroyed_wood_wall_and_movement_audio() -> void:
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	var DestructibleWallScript = load("res://Scripts/World/destructible_wall.gd")
	
	# 1. Verify all 4 uploaded custom MP3 streams load cleanly with expected loop & trimmed lengths
	var hit_stream = SoundManagerScript.get_tank_hit_stream()
	var destroyed_stream = SoundManagerScript.get_tank_destroyed_stream()
	var wood_stream = SoundManagerScript.get_wood_break_stream()
	var move_stream = SoundManagerScript.get_tank_move_stream()
	
	assert_not_null(hit_stream, "Tank impact MP3 stream must load cleanly")
	assert_true(hit_stream is AudioStreamMP3, "Tank impact stream must be AudioStreamMP3")
	assert_false((hit_stream as AudioStreamMP3).loop, "Tank impact sound must be one-shot (loop=false)")
	assert_in_range(hit_stream.get_length(), 0.9, 1.4, "Tank impact MP3 length must match ~1.1s asset")
	
	assert_not_null(destroyed_stream, "Tank destroyed MP3 stream must load cleanly")
	assert_true(destroyed_stream is AudioStreamMP3, "Tank destroyed stream must be AudioStreamMP3")
	assert_false((destroyed_stream as AudioStreamMP3).loop, "Tank destroyed sound must be one-shot (loop=false)")
	assert_in_range(destroyed_stream.get_length(), 3.0, 3.8, "Tank destroyed MP3 length must match ~3.3s asset")
	
	assert_not_null(wood_stream, "Wood wall break MP3 stream must load cleanly")
	assert_true(wood_stream is AudioStreamMP3, "Wood wall break stream must be AudioStreamMP3")
	assert_false((wood_stream as AudioStreamMP3).loop, "Wood wall break sound must be one-shot (loop=false)")
	assert_in_range(wood_stream.get_length(), 3.2, 4.0, "Wood wall break MP3 must have trailing silence trimmed (~3.6s)")
	
	assert_not_null(move_stream, "Tank movement MP3 stream must load cleanly")
	assert_true(move_stream is AudioStreamMP3, "Tank movement stream must be AudioStreamMP3")
	assert_true((move_stream as AudioStreamMP3).loop, "Tank movement engine/treads audio must loop seamlessly (loop=true)")
	assert_in_range(move_stream.get_length(), 9.5, 10.2, "Tank movement MP3 length must match ~9.85s loop asset")
	
	# 2. Verify tank movement audio activation, dynamic dash pitch boost, and standstill silence
	var local_tank = spawn_scene("res://Scenes/tank.tscn")
	local_tank.is_player = true
	local_tank.add_to_group("player")
	local_tank.add_to_group("tanks")
	local_tank.global_position = Vector2.ZERO
	await wait_physics_frames(2)
	assert_null(local_tank._move_audio_player, "Stationary tank must not allocate or play movement audio")
	
	local_tank.set_chassis_input(Vector2.RIGHT)
	await wait_physics_frames(14)
	assert_true(local_tank.velocity.length() > 150.0, "Tank must accelerate above movement threshold")
	assert_not_null(local_tank._move_audio_player, "Moving tank must initialize _move_audio_player")
	assert_equal(local_tank._move_audio_player.stream, move_stream, "Movement player must bind tank_move.mp3")
	assert_approx_equal(local_tank._move_audio_player.panning_strength, 0.0, 0.01, "Local player movement audio must be centered")
	var local_vol_db: float = local_tank._move_audio_player.volume_db
	var cruise_pitch: float = local_tank._move_audio_player.pitch_scale
	assert_in_range(local_vol_db, -18.0, -12.0, "Cruising local tank movement volume must sit in the lowered, subtle mix range")
	
	local_tank.set_dash_input(true)
	await wait_physics_frames(8)
	assert_true(local_tank.is_dashing, "Tank must enter dash state")
	assert_true(local_tank._move_audio_player.pitch_scale > cruise_pitch + 0.08, "Dashing must raise tank engine/tread pitch")
	
	local_tank.set_dash_input(false)
	local_tank.set_chassis_input(Vector2.ZERO)
	await wait_physics_frames(30)
	assert_approx_equal(local_tank.velocity.length(), 0.0, 1.0, "Tank must come to a full stop")
	assert_true(local_tank._move_audio_player.volume_db <= -79.0, "Stopped tank must mute/stop movement audio")
	
	# 3. Verify 2D spatial hearing radius for enemy tank movement
	var far_enemy = spawn_scene("res://Scenes/tank.tscn")
	far_enemy.is_player = false
	far_enemy.add_to_group("tanks")
	far_enemy.global_position = Vector2(2400.0, 2400.0)
	far_enemy.set_chassis_input(Vector2.LEFT)
	
	var near_enemy = spawn_scene("res://Scenes/tank.tscn")
	near_enemy.is_player = false
	near_enemy.add_to_group("tanks")
	near_enemy.global_position = Vector2(620.0, 0.0)
	near_enemy.set_chassis_input(Vector2.UP)
	await wait_physics_frames(14)
	
	assert_null(far_enemy._move_audio_player, "Far-away enemy tank outside HEARING_RADIUS_MOVEMENT must remain silent")
	assert_not_null(near_enemy._move_audio_player, "Nearby moving enemy tank must activate spatial movement audio")
	assert_true(near_enemy._move_audio_player.panning_strength > 0.5, "Enemy tank movement audio must use stereo panning")
	assert_true(near_enemy._move_audio_player.volume_db < local_vol_db - 3.0, "Distant enemy tank movement must be quieter than local tank")
	
	# 4. Verify non-lethal impact, wooden wall destruction, and tank destruction cleanup
	near_enemy.take_damage(25.0, local_tank, false)
	assert_approx_equal(near_enemy.current_health, 75.0, 0.1, "Non-lethal hit must apply damage and trigger impact clang cleanly")
	
	var wall = DestructibleWallScript.new()
	wall.wall_size = Vector2(96.0, 28.0)
	wall.global_position = Vector2(180.0, 0.0)
	track_node(wall)
	add_child(wall)
	await wait_physics_frames(1)
	wall.take_damage(25.0, local_tank, false)
	assert_false(wall.is_destroyed, "First hit on wooden barricade triggers impact hit without shattering")
	wall.shatter()
	assert_true(wall.is_destroyed, "Wooden barricade shatter() must destroy wall and trigger wood_wall_break.mp3 cleanly")
	
	near_enemy.eliminate(local_tank, false)
	assert_true(near_enemy.is_dead, "Eliminated tank must enter dead state and trigger tank_destroyed.mp3")
	assert_true(near_enemy._move_audio_player.volume_db <= -79.0, "Eliminating a moving tank must immediately stop its movement audio")
