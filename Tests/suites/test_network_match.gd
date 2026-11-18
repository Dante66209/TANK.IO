# res://Tests/suites/test_network_match.gd
extends TestBase

## Verification suite for Phase 2 Authoritative Multiplayer Match Sync.
## Tests:
## 1) Real WebSocket loop between Server MainGame + 2 Clients (initial world, input->move,
##    projectiles, mines, damage, elimination, leaderboard, and leader restart).
## 2) Client MainGame puppet mode isolation (local camera/input vs remote puppets, HUD, FogOfWar, Podium).

const NetworkManagerScript = preload("res://Scripts/Core/network_manager.gd")

class ClientSyncSpy extends Node:
	var initial_world_count: int = 0
	var last_initial_world: Dictionary = {}
	var snapshot_batches: int = 0
	var last_snapshots: Array = []
	var spawned_projectiles: Array[Dictionary] = []
	var spawned_mines: Array[Dictionary] = []
	var tank_damages: Array[Dictionary] = []
	var tank_eliminations: Array[Dictionary] = []
	var leaderboards: Array = []
	var restarts: int = 0
	var last_restart_positions: Array = []

	func apply_initial_world(payload: Dictionary) -> void:
		initial_world_count += 1
		last_initial_world = payload

	func apply_start_countdown(_step_dur: float, _total_sec: int) -> void:
		pass

	func apply_tank_snapshots(snapshots: Array) -> void:
		snapshot_batches += 1
		last_snapshots = snapshots

	func apply_match_state(_state_dict: Dictionary) -> void:
		pass

	func apply_leaderboard(entries: Array) -> void:
		leaderboards.append(entries)

	func apply_spawn_projectile(proj_id: int, shooter_slot: int, pos: Vector2, dir: Vector2, spd: float, dmg: float, is_ric: bool, bounces: int) -> void:
		spawned_projectiles.append({
			"id": proj_id, "slot": shooter_slot, "pos": pos, "dir": dir,
			"speed": spd, "damage": dmg, "ricochet": is_ric, "bounces": bounces
		})

	func apply_destroy_projectile(_proj_id: int, _hit_pos: Vector2) -> void:
		pass

	func apply_spawn_mine(mine_id: int, owner_slot: int, start_pos: Vector2, target_pos: Vector2, is_cluster: bool, _play_sound: bool) -> void:
		spawned_mines.append({
			"id": mine_id, "slot": owner_slot, "start": start_pos, "target": target_pos, "cluster": is_cluster
		})

	func apply_detonate_mine(_mine_id: int) -> void:
		pass

	func apply_tank_damaged(victim_slot: int, amount: float, kind: int) -> void:
		tank_damages.append({"slot": victim_slot, "amount": amount, "kind": kind})

	func apply_tank_eliminated(victim_slot: int, killer_slot: int, is_barrel: bool, is_mine: bool, is_storm: bool, is_mortar: bool) -> void:
		tank_eliminations.append({"victim": victim_slot, "killer": killer_slot, "barrel": is_barrel, "mine": is_mine, "storm": is_storm, "mortar": is_mortar})

	func apply_tank_respawned(_slot: int, _pos: Vector2) -> void:
		pass

	func apply_tank_powerup(_slot: int, _p_type: int, _duration: float, _value: float, _expired: bool) -> void:
		pass

	func apply_killstreak_banner(_slot: int, _title: String, _subtitle: String, _color: Color, _tier: int) -> void:
		pass

	func apply_spawn_powerup(_net_id: int, _p_type: int, _pos: Vector2) -> void:
		pass

	func apply_collect_powerup(_net_id: int, _collector_slot: int) -> void:
		pass

	func apply_barrel_event(_barrel_slot: int, _kind: int, _val: float) -> void:
		pass

	func apply_wall_event(_wall_slot: int, _kind: int, _val: float) -> void:
		pass

	func apply_mortar_state(_active: bool, _duration: float) -> void:
		pass

	func apply_mortar_strike(_pos: Vector2) -> void:
		pass

	func apply_restart_match(spawn_positions: Array) -> void:
		restarts += 1
		last_restart_positions = spawn_positions

func teardown() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("clear_lobby_match"):
		gs.clear_lobby_match()
	super.teardown()

func _create_branch(branch_name: String) -> Dictionary:
	var branch := Node.new()
	branch.name = branch_name
	track_node(branch)
	add_child(branch)

	var mp := SceneMultiplayer.new()
	mp.root_path = branch.get_path()
	get_tree().set_multiplayer(mp, branch.get_path())

	var nm: Node = NetworkManagerScript.new()
	nm.name = "NetworkManager"
	nm.enable_cli_autostart = false
	nm.auto_manage_server_scene = false
	nm.online_countdown_seconds = 0
	branch.add_child(nm)

	return {"branch": branch, "mp": mp, "nm": nm}

func _cleanup_branch(info: Dictionary) -> void:
	var nm: Node = info.get("nm")
	if nm != null and is_instance_valid(nm) and nm.has_method("disconnect_network"):
		nm.disconnect_network()
	var branch: Node = info.get("branch")
	if branch != null and is_instance_valid(branch):
		get_tree().set_multiplayer(null, branch.get_path())

func test_01_server_main_game_and_client_sync_over_websocket() -> void:
	var test_port := 17899
	var srv_info := _create_branch("MatchTestSrv")
	var c1_info := _create_branch("MatchTestC1")
	var c2_info := _create_branch("MatchTestC2")

	var srv: Node = srv_info["nm"]
	var c1: Node = c1_info["nm"]
	var c2: Node = c2_info["nm"]

	var spy1 := ClientSyncSpy.new()
	var spy2 := ClientSyncSpy.new()
	track_node(spy1)
	track_node(spy2)
	add_child(spy1)
	add_child(spy2)
	c1.register_match_sync(spy1)
	c2.register_match_sync(spy2)

	assert_equal(srv.start_dedicated_server(test_port, "Arena Sync Test", 5, "127.0.0.1"), OK, "Server binds loopback test port")
	assert_equal(c1.connect_to_server("ws://127.0.0.1:%d" % test_port, "Carlos", Color(0.2, 0.7, 1.0, 1.0)), OK, "Client 1 connects")
	assert_equal(c2.connect_to_server("ws://127.0.0.1:%d" % test_port, "Lucia", Color(1.0, 0.3, 0.3, 1.0)), OK, "Client 2 connects")

	for _i in range(90):
		await wait_process_frames(1)
		if c1.current_roster.size() == 2 and c2.current_roster.size() == 2:
			break
	assert_equal(c1.current_roster.size(), 2, "Both human players registered")

	c1.request_fill_bots()
	for _i in range(60):
		await wait_process_frames(1)
		if c1.current_roster.size() == 5 and c2.current_roster.size() == 5:
			break
	c1.request_start_match()
	for _i in range(60):
		await wait_process_frames(1)
		if srv.match_in_progress:
			break
	assert_true(srv.match_in_progress, "Match launched on server")

	# Instantiate authoritative Server MainGame inside srv branch
	var mg_scene: PackedScene = load("res://Scenes/main_game.tscn")
	var srv_mg: Node2D = mg_scene.instantiate() as Node2D
	srv_mg.network_manager_override = srv
	srv_mg.online_roster_override = srv.current_roster
	srv_info["branch"].add_child(srv_mg)

	# Simulate clients notifying ready after MainGame loads
	await wait_physics_frames(2)
	c1.notify_match_scene_ready()
	c2.notify_match_scene_ready()

	for _i in range(60):
		await wait_physics_frames(1)
		if spy1.initial_world_count >= 1 and spy2.initial_world_count >= 1:
			break

	assert_equal(spy1.initial_world_count, 1, "Client 1 receives initial world state")
	assert_equal(spy2.initial_world_count, 1, "Client 2 receives initial world state")
	assert_equal((spy1.last_initial_world.get("tank_positions", []) as Array).size(), 5, "Initial world syncs all 5 spawn positions")
	assert_true((spy1.last_initial_world.get("powerups", []) as Array).size() > 0, "Initial world syncs spawned powerups")

	# Client 1 sends movement + shoot input -> Server moves tank & spawns projectile -> Client 2 observes!
	var sync_srv: Node = srv_mg.match_network_sync
	var p1_tank: Node2D = sync_srv._tanks_by_slot[0] as Node2D
	var start_pos: Vector2 = p1_tank.global_position
	# Ensure safe clear area by zeroing move only after checking delta or moving unobstructed
	c1.send_player_input(Vector2(1.0, 0.0), 0.0, true, false)

	for _i in range(45):
		await wait_physics_frames(1)
		if spy2.spawned_projectiles.size() >= 1 and spy2.snapshot_batches >= 2:
			break

	assert_true(spy2.spawned_projectiles.size() >= 1, "Client 2 observes Client 1's projectile fired via Server")
	assert_equal(int(spy2.spawned_projectiles[0]["slot"]), 0, "Projectile attributes to Client 1 slot 0")
	assert_true(spy2.snapshot_batches >= 2, "Clients receive 20 Hz tank snapshot batches")
	assert_equal(spy2.last_snapshots.size(), 5, "Snapshots include all 5 combatants")

	# Client 1 throws a stealth proximity mine -> Server spawns mine and syncs to Client 2
	c1.send_player_throw_mine(0.35)
	for _i in range(30):
		await wait_physics_frames(1)
		if spy2.spawned_mines.size() >= 1:
			break
	assert_true(spy2.spawned_mines.size() >= 1, "Client 2 observes Client 1's thrown mine via Server")
	assert_equal(int(spy2.spawned_mines[0]["slot"]), 0, "Mine attributes to Client 1 slot 0")

	# Server eliminates slot 1 via slot 0 -> both clients receive damage, elimination & leaderboard update
	var p2_tank: Node2D = sync_srv._tanks_by_slot[1] as Node2D
	p2_tank.set("is_invulnerable", false)
	p2_tank.take_damage(150.0, p1_tank, false)
	for _i in range(30):
		await wait_physics_frames(1)
		if spy1.tank_eliminations.size() >= 1 and spy2.tank_eliminations.size() >= 1 and spy2.leaderboards.size() >= 1:
			break
	assert_true(spy1.tank_damages.size() >= 1, "Client 1 receives tank damage event")
	assert_true(spy2.tank_eliminations.size() >= 1, "Client 2 receives tank elimination event")
	assert_equal(int(spy2.tank_eliminations[0]["victim"]), 1, "Elimination identifies victim slot 1")
	assert_equal(int(spy2.tank_eliminations[0]["killer"]), 0, "Elimination identifies killer slot 0")
	assert_true(spy2.leaderboards.size() >= 1, "Clients receive synced leaderboard update")

	# Leader requests restart -> Server resets match and notifies both clients
	c1.request_restart_match()
	for _i in range(30):
		await wait_physics_frames(1)
		if spy1.restarts >= 1 and spy2.restarts >= 1:
			break
	assert_equal(spy1.restarts, 1, "Client 1 receives restart match broadcast")
	assert_equal(spy2.restarts, 1, "Client 2 receives restart match broadcast")
	assert_equal(spy2.last_restart_positions.size(), 5, "Restart broadcast includes fresh spawn positions")

	srv_mg.queue_free()
	await wait_physics_frames(2)
	_cleanup_branch(c1_info)
	_cleanup_branch(c2_info)
	_cleanup_branch(srv_info)

func test_02_client_main_game_puppet_mode_applies_snapshots_and_fx() -> void:
	var c_info := _create_branch("ClientPuppetTest")
	var nm: Node = c_info["nm"]

	# Put client NetworkManager into active client role without touching global tree
	nm.role = "client"
	nm.connection_state = "connected"
	var dummy_peer := WebSocketMultiplayerPeer.new()
	# Note: creating local server/client or mocking multiplayer unique_id via isolated Server+Client
	var srv_info := _create_branch("ClientPuppetSrv")
	var srv: Node = srv_info["nm"]
	assert_equal(srv.start_dedicated_server(17901, "Puppet Test", 5, "127.0.0.1"), OK, "Temp server starts")
	assert_equal(nm.connect_to_server("ws://127.0.0.1:17901", "LocalHero", Color(0.1, 0.9, 0.5, 1.0)), OK, "Client connects")

	for _i in range(60):
		await wait_process_frames(1)
		if nm.current_roster.size() == 1:
			break
	nm.request_fill_bots()
	for _i in range(60):
		await wait_process_frames(1)
		if nm.current_roster.size() == 5:
			break

	var gs := get_node_or_null("/root/GameSettings")
	gs.configure_lobby_match(nm.current_roster, 5, "server", "Puppet Test")

	var mg_scene: PackedScene = load("res://Scenes/main_game.tscn")
	var client_mg: Node2D = mg_scene.instantiate() as Node2D
	client_mg.network_manager_override = nm
	client_mg.online_roster_override = nm.current_roster
	c_info["branch"].add_child(client_mg)

	await wait_physics_frames(2)

	var sync: Node = client_mg.match_network_sync
	assert_not_null(sync, "Client MainGame creates MatchNetworkSync")
	assert_false(sync.is_server, "Client MatchNetworkSync runs in client mode")
	assert_not_null(client_mg.player_tank, "Client assigns local player_tank")
	assert_true(client_mg.player_tank.is_player, "Local player tank has is_player = true")
	assert_false(client_mg.player_tank.is_network_puppet, "Local player tank allows local movement prediction")
	assert_false(client_mg.player_tank.network_authoritative, "Local player tank defers damage/scoring authority to server")

	var bot_tank: Node2D = sync._tanks_by_slot[1] as Node2D
	assert_true(bot_tank.is_network_puppet, "Bot tank on client runs in puppet mode")
	assert_true(client_mg.match_manager.is_network_puppet, "Client MatchManager runs in puppet mode")
	assert_true(client_mg.get_node("SpawnManager").is_network_puppet, "Client SpawnManager runs in puppet mode")
	assert_true(client_mg.get_node("MortarManager").is_network_puppet, "Client MortarManager runs in puppet mode")

	# Apply snapshot & leaderboard directly -> HUD and tank positions update cleanly
	sync.apply_initial_world({
		"tank_positions": [Vector2(100, 100), Vector2(400, 250), Vector2(-300, 200), Vector2(200, -300), Vector2(-400, -400)],
		"powerups": [{"id": 99, "type": 1, "pos": Vector2(180, 100)}],
		"broken_barrels": [],
		"wall_states": [],
		"match_state": {"t": 175.0, "dur": 180.0, "act": true, "end": false, "sd": false, "nr": false, "zc": Vector2.ZERO, "zr": 4550.0},
		"leaderboard": [
			{"slot": 0, "name": "LocalHero", "score": 250, "kills": 2, "deaths": 0, "streak": 2, "barrel_kills": 0, "alive": true},
			{"slot": 1, "name": "Bot Alpha", "score": 100, "kills": 1, "deaths": 1, "streak": 0, "barrel_kills": 0, "alive": true}
		],
		"countdown_left": 0
	})
	await wait_physics_frames(2)

	assert_vector_approx(client_mg.player_tank.global_position, Vector2(100, 100), 1.0, "Local player placed at synced spawn")
	assert_vector_approx(bot_tank.global_position, Vector2(400, 250), 1.0, "Remote bot placed at synced spawn")
	assert_equal(client_mg.player_tank.score, 250, "Synced leaderboard updates local player score")

	# Apply remote snapshot moving bot_tank -> puppet interpolates smoothly toward target
	sync.apply_tank_snapshots([[1, 520.0, 250.0, 0.0, 0.0, 80.0, 0.0, 0, 100.0, 3, 0]])
	await wait_physics_frames(8)
	assert_true(bot_tank.global_position.x > 410.0, "Puppet tank interpolates toward server snapshot")
	assert_approx_equal(bot_tank.current_health, 80.0, 0.1, "Puppet tank updates synced health")

	client_mg.queue_free()
	await wait_physics_frames(2)
	_cleanup_branch(c_info)
	_cleanup_branch(srv_info)
