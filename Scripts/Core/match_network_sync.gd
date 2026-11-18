# res://Scripts/Core/match_network_sync.gd
class_name MatchNetworkSync extends Node

## Authoritative Match Synchronizer for TANK.IO (Phase 2).
## Runs inside MainGame when GameSettings.lobby_mode == "server".
## - Server: runs MatchManager, SpawnManager, MortarManager, BotTank AI, physics & damage,
##   broadcasts 20 Hz tank snapshots and reliable combat/world events.
## - Client: sends local inputs (WASD, turret aim, shoot, dash, mines), predicts local
##   movement smoothly, interpolates remote entities, and renders authoritative state.

const PlayerTankScene: PackedScene = preload("res://Scenes/player_tank.tscn")
const BotTankScene: PackedScene = preload("res://Scenes/bot_tank.tscn")
const ProjectileScene: PackedScene = preload("res://Scenes/projectile.tscn")
const ProximityMineScript = preload("res://Scripts/Entities/mine.gd")
const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

const SNAPSHOT_INTERVAL: float = 0.05 # 20 Hz
const MATCH_TICK_INTERVAL: float = 0.20 # 5 Hz
const INPUT_SEND_INTERVAL: float = 0.033 # 30 Hz
const READY_GRACE_SECONDS: float = 1.8

var main_game: Node2D = null
var network_manager: Node = null
var is_server: bool = false
var local_peer_id: int = 0
var local_tank_slot: int = -1
var local_player_tank: Node2D = null

var _tanks_by_slot: Dictionary = {} # slot_idx -> Tank
var _tanks_by_peer: Dictionary = {} # peer_id -> Tank
var _barrels_by_slot: Dictionary = {} # slot_idx -> Barrel
var _walls_by_slot: Dictionary = {} # slot_idx -> DestructibleWall
var _projectiles_by_id: Dictionary = {} # proj_id -> Projectile
var _mines_by_id: Dictionary = {} # mine_id -> ProximityMine

var _next_proj_id: int = 1
var _next_mine_id: int = 1
var _initial_spawn_positions: Array[Vector2] = []

# Server loop state
var _ready_peers: Dictionary = {}
var _waiting_for_peers_ready: bool = false
var _ready_wait_elapsed: float = 0.0
var _countdown_active: bool = false
var _countdown_remaining: int = 0
var _snapshot_timer: float = 0.0
var _match_tick_timer: float = 0.0

# Client input tracking
var _input_timer: float = 0.0
var _last_sent_shoot: bool = false
var _last_sent_dash: bool = false
var _last_sent_move: Vector2 = Vector2.ZERO
var _last_sent_aim: float = 0.0

func _exit_tree() -> void:
	if network_manager != null and is_instance_valid(network_manager) and network_manager.has_method("unregister_match_sync"):
		network_manager.unregister_match_sync(self)
	if GameEvents != null:
		if GameEvents.powerup_spawned.is_connected(_on_server_powerup_spawned):
			GameEvents.powerup_spawned.disconnect(_on_server_powerup_spawned)
		if GameEvents.powerup_collected.is_connected(_on_server_powerup_collected):
			GameEvents.powerup_collected.disconnect(_on_server_powerup_collected)
		if GameEvents.killstreak_achieved.is_connected(_on_server_killstreak_achieved):
			GameEvents.killstreak_achieved.disconnect(_on_server_killstreak_achieved)

func setup(p_main_game: Node2D, p_nm: Node, roster: Array) -> void:
	main_game = p_main_game
	network_manager = p_nm
	is_server = p_nm.is_server_active() if p_nm.has_method("is_server_active") else false
	local_peer_id = p_nm.get_local_peer_id() if p_nm.has_method("get_local_peer_id") else 0

	if network_manager.has_method("register_match_sync"):
		network_manager.register_match_sync(self)

	_index_static_destructibles()
	_spawn_online_roster(roster)
	_lock_all_tanks(true)

	if is_server:
		_setup_server_authority()
	else:
		_setup_client_puppets()

func _index_static_destructibles() -> void:
	_barrels_by_slot.clear()
	var barrels_parent := main_game.get_node_or_null("Entities/Barrels")
	if barrels_parent != null:
		var b_idx := 0
		for child in barrels_parent.get_children():
			if child != null and child is Node2D:
				if "net_slot" in child:
					child.set("net_slot", b_idx)
				_barrels_by_slot[b_idx] = child
				b_idx += 1

	_walls_by_slot.clear()
	var wmap := main_game.get_node_or_null("WorldMap")
	var dest_container := wmap.get_node_or_null("DestructibleCovers") if wmap != null else null
	if dest_container != null:
		var w_idx := 0
		for child in dest_container.get_children():
			if child != null and child is Node2D:
				if "net_slot" in child:
					child.set("net_slot", w_idx)
				_walls_by_slot[w_idx] = child
				w_idx += 1

func _spawn_online_roster(roster: Array) -> void:
	var tanks_container := main_game.get_node_or_null("Entities/Tanks")
	if tanks_container == null:
		return

	# Remove default singleplayer placeholders cleanly
	for child in tanks_container.get_children():
		for grp in ["player", "tanks"]:
			if child.is_in_group(grp):
				child.remove_from_group(grp)
		tanks_container.remove_child(child)
		child.queue_free()

	_tanks_by_slot.clear()
	_tanks_by_peer.clear()
	local_player_tank = null
	local_tank_slot = -1

	for slot_idx in range(roster.size()):
		var raw_entry: Variant = roster[slot_idx]
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var pid := int(entry.get("peer_id", 0))
		var is_human := bool(entry.get("is_human", pid > 0))
		var t_name := str(entry.get("name", "Player" if is_human else "Bot"))
		var color_hex := str(entry.get("color", ""))

		var tank: Node2D = null
		if is_human:
			tank = PlayerTankScene.instantiate() as Node2D
			var is_local := (not is_server) and (local_peer_id > 0) and (pid == local_peer_id)
			if "is_local_controlled" in tank:
				tank.set("is_local_controlled", is_local)
			if "is_network_puppet" in tank:
				tank.set("is_network_puppet", (not is_server) and (not is_local))
			if "network_authoritative" in tank:
				tank.set("network_authoritative", is_server)
			if "is_human_remote" in tank:
				tank.set("is_human_remote", is_server)
			tank.name = "PlayerPeer_%d_%d" % [pid, slot_idx]
			if is_local:
				local_player_tank = tank
				local_tank_slot = slot_idx
		else:
			tank = BotTankScene.instantiate() as Node2D
			if "is_network_puppet" in tank:
				tank.set("is_network_puppet", not is_server)
			if "network_authoritative" in tank:
				tank.set("network_authoritative", is_server)
			tank.name = "BotSlot_%d" % slot_idx

		if "net_slot" in tank:
			tank.set("net_slot", slot_idx)
		if "owner_peer_id" in tank:
			tank.set("owner_peer_id", pid)
		if "tank_name" in tank:
			tank.set("tank_name", t_name)

		tanks_container.add_child(tank)
		if is_human and not color_hex.is_empty() and tank.has_method("apply_tank_color"):
			var parsed_col := Color.from_string(color_hex, Color(0.2, 0.45, 0.75, 1.0))
			tank.apply_tank_color(parsed_col)

		_tanks_by_slot[slot_idx] = tank
		if is_human and pid > 0:
			_tanks_by_peer[pid] = tank

	# Update MainGame and visual controllers with local player reference
	main_game.player_tank = local_player_tank
	if not is_server and local_player_tank != null:
		var hud := main_game.get_node_or_null("HUD")
		if hud != null and "player_tank" in hud:
			hud.set("player_tank", local_player_tank)
		var fow := main_game.get_node_or_null("FogOfWar")
		if fow != null and "player_tank" in fow:
			fow.set("player_tank", local_player_tank)
		var minimap := main_game.get_node_or_null("HUD/Root/TopLeft/MinimapPanel/VBox/TacticalMinimap")
		if minimap != null and "player_tank" in minimap:
			minimap.set("player_tank", local_player_tank)

func _setup_server_authority() -> void:
	var fow := main_game.get_node_or_null("FogOfWar")
	if fow != null:
		fow.set_process(false)
		fow.set("visible", false)
	_assign_initial_spawn_positions()

	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null:
		if mm.has_method("sync_scene_combatants"):
			mm.sync_scene_combatants()
		mm.set("is_match_active", false)
		if mm.has_signal("network_match_state_changed"):
			mm.network_match_state_changed.connect(_on_server_match_state_changed)
		if mm.has_signal("network_leaderboard_changed"):
			mm.network_leaderboard_changed.connect(_on_server_leaderboard_changed)

	var mortar_mgr := main_game.get_node_or_null("MortarManager")
	if mortar_mgr != null:
		if mortar_mgr.has_signal("network_mortar_state_changed"):
			mortar_mgr.network_mortar_state_changed.connect(_on_server_mortar_state_changed)
		if mortar_mgr.has_signal("network_mortar_strike_spawned"):
			mortar_mgr.network_mortar_strike_spawned.connect(_on_server_mortar_strike_spawned)

	for slot in _tanks_by_slot.keys():
		var t: Node = _tanks_by_slot[slot]
		if t.has_signal("network_projectile_spawned"):
			t.network_projectile_spawned.connect(_on_server_projectile_spawned)
		if t.has_signal("network_mine_spawned"):
			t.network_mine_spawned.connect(_on_server_mine_spawned)
		if t.has_signal("network_damaged_synced"):
			t.network_damaged_synced.connect(_on_server_tank_damaged)
		if t.has_signal("network_eliminated_synced"):
			t.network_eliminated_synced.connect(_on_server_tank_eliminated)
		if t.has_signal("network_respawned_synced"):
			t.network_respawned_synced.connect(_on_server_tank_respawned)
		if t.has_signal("network_powerup_synced"):
			t.network_powerup_synced.connect(_on_server_tank_powerup)

	for b_slot in _barrels_by_slot.keys():
		var b: Node = _barrels_by_slot[b_slot]
		if b.has_signal("network_barrel_damaged"):
			b.network_barrel_damaged.connect(_on_server_barrel_damaged)
		if b.has_signal("network_barrel_exploded"):
			b.network_barrel_exploded.connect(_on_server_barrel_exploded)
		if b.has_signal("network_barrel_respawned"):
			b.network_barrel_respawned.connect(_on_server_barrel_respawned)

	for w_slot in _walls_by_slot.keys():
		var w: Node = _walls_by_slot[w_slot]
		if w.has_signal("network_wall_damaged"):
			w.network_wall_damaged.connect(_on_server_wall_damaged)
		if w.has_signal("network_wall_shattered"):
			w.network_wall_shattered.connect(_on_server_wall_shattered)
		if w.has_signal("network_wall_restored"):
			w.network_wall_restored.connect(_on_server_wall_restored)

	if GameEvents != null:
		if not GameEvents.powerup_spawned.is_connected(_on_server_powerup_spawned):
			GameEvents.powerup_spawned.connect(_on_server_powerup_spawned)
		if not GameEvents.powerup_collected.is_connected(_on_server_powerup_collected):
			GameEvents.powerup_collected.connect(_on_server_powerup_collected)
		if not GameEvents.killstreak_achieved.is_connected(_on_server_killstreak_achieved):
			GameEvents.killstreak_achieved.connect(_on_server_killstreak_achieved)

	_ready_peers.clear()
	_waiting_for_peers_ready = true
	_ready_wait_elapsed = 0.0

func _setup_client_puppets() -> void:
	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null and mm.has_method("enter_network_puppet_mode"):
		mm.enter_network_puppet_mode()

	var sm := main_game.get_node_or_null("SpawnManager")
	if sm != null and sm.has_method("enter_network_puppet_mode"):
		sm.enter_network_puppet_mode()

	var mortar_mgr := main_game.get_node_or_null("MortarManager")
	if mortar_mgr != null and mortar_mgr.has_method("enter_network_puppet_mode"):
		mortar_mgr.enter_network_puppet_mode()

	for b_slot in _barrels_by_slot.keys():
		var b: Node = _barrels_by_slot[b_slot]
		if "is_network_puppet" in b:
			b.set("is_network_puppet", true)

	for w_slot in _walls_by_slot.keys():
		var w: Node = _walls_by_slot[w_slot]
		if "is_network_puppet" in w:
			w.set("is_network_puppet", true)

	if local_player_tank != null and local_player_tank.has_signal("local_mine_requested"):
		local_player_tank.local_mine_requested.connect(_on_local_mine_requested)

	if network_manager != null and network_manager.has_method("notify_match_scene_ready"):
		network_manager.notify_match_scene_ready()

func _assign_initial_spawn_positions() -> void:
	_initial_spawn_positions.clear()
	var wmap := main_game.get_node_or_null("WorldMap")
	var spawn_points: Array[Vector2] = []
	if wmap != null and wmap.has_method("get_spawn_positions"):
		spawn_points = wmap.get_spawn_positions()
	if spawn_points.is_empty():
		spawn_points = [Vector2(-600, -600), Vector2(600, -600), Vector2(-600, 600), Vector2(600, 600), Vector2.ZERO]

	var shuffled := spawn_points.duplicate()
	shuffled.shuffle()
	var slot_keys := _tanks_by_slot.keys()
	slot_keys.sort()
	for idx in range(slot_keys.size()):
		var slot: int = int(slot_keys[idx])
		var t: Node2D = _tanks_by_slot[slot] as Node2D
		var pos: Vector2 = shuffled[idx % shuffled.size()]
		_initial_spawn_positions.append(pos)
		if t.has_method("snap_network_position"):
			t.snap_network_position(pos)
		else:
			t.global_position = pos

func _lock_all_tanks(locked: bool) -> void:
	for slot in _tanks_by_slot.keys():
		var t: Node = _tanks_by_slot[slot]
		if is_instance_valid(t) and t.has_method("set_controls_locked"):
			t.set_controls_locked(locked)

func _physics_process(delta: float) -> void:
	if network_manager == null or not is_instance_valid(network_manager):
		return
	if is_server:
		_process_server(delta)
	else:
		_process_client_input(delta)

func _process_server(delta: float) -> void:
	if _waiting_for_peers_ready:
		_ready_wait_elapsed += delta
		var expected_peers: Array = network_manager.get_connected_human_peer_ids() if network_manager.has_method("get_connected_human_peer_ids") else _tanks_by_peer.keys()
		var all_ready := true
		for pid in expected_peers:
			if not _ready_peers.has(int(pid)):
				all_ready = false
				break
		if all_ready or _ready_wait_elapsed >= READY_GRACE_SECONDS:
			_waiting_for_peers_ready = false
			_begin_server_countdown()

	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = 0.0
		_broadcast_tank_snapshots()

	_match_tick_timer += delta
	if _match_tick_timer >= MATCH_TICK_INTERVAL:
		_match_tick_timer = 0.0
		var mm := main_game.get_node_or_null("MatchManager")
		if mm != null and mm.has_method("serialize_match_state"):
			network_manager.broadcast_match_state(mm.serialize_match_state(), false)

func _process_client_input(delta: float) -> void:
	if local_player_tank == null or not is_instance_valid(local_player_tank):
		return
	if local_player_tank.get("is_dead") == true or local_player_tank.get("controls_locked") == true:
		if _last_sent_shoot or _last_sent_dash or _last_sent_move != Vector2.ZERO:
			_last_sent_shoot = false
			_last_sent_dash = false
			_last_sent_move = Vector2.ZERO
			network_manager.send_player_input(Vector2.ZERO, _last_sent_aim, false, false)
		return

	var move_dir: Vector2 = local_player_tank.get("move_input")
	var turret_pivot := local_player_tank.get_node_or_null("TurretPivot") as Node2D
	var aim_ang: float = turret_pivot.global_rotation if turret_pivot != null else float(local_player_tank.get("target_aim_angle"))
	var wants_shoot: bool = bool(local_player_tank.get("local_wants_shoot"))
	var wants_dash: bool = bool(local_player_tank.get("dash_requested"))

	_input_timer += delta
	var important_change := (wants_shoot != _last_sent_shoot) or (wants_dash != _last_sent_dash) or ((move_dir == Vector2.ZERO) != (_last_sent_move == Vector2.ZERO))
	if important_change or _input_timer >= INPUT_SEND_INTERVAL:
		_input_timer = 0.0
		_last_sent_move = move_dir
		_last_sent_aim = aim_ang
		_last_sent_shoot = wants_shoot
		_last_sent_dash = wants_dash
		network_manager.send_player_input(move_dir, aim_ang, wants_shoot, wants_dash)

func _on_local_mine_requested(aim_angle: float) -> void:
	if not is_server and network_manager != null and network_manager.has_method("send_player_throw_mine"):
		network_manager.send_player_throw_mine(aim_angle)

# ------------------------------------------------------------------------------
# Server Countdown & Initial Sync
# ------------------------------------------------------------------------------

func _begin_server_countdown() -> void:
	var countdown_sec := 5
	if "online_countdown_seconds" in network_manager:
		countdown_sec = maxi(0, int(network_manager.get("online_countdown_seconds")))
	var overlay := main_game.get_node_or_null("CountdownOverlay")
	if countdown_sec <= 0 or overlay == null:
		_on_server_countdown_finished()
		return

	_countdown_active = true
	_countdown_remaining = countdown_sec
	_lock_all_tanks(true)
	overlay.set("countdown_seconds", countdown_sec)
	if overlay.has_signal("countdown_step") and not overlay.countdown_step.is_connected(_on_server_countdown_step):
		overlay.countdown_step.connect(_on_server_countdown_step)
	if not overlay.countdown_finished.is_connected(_on_server_countdown_finished):
		overlay.countdown_finished.connect(_on_server_countdown_finished, CONNECT_ONE_SHOT)
	overlay.start_countdown(1.0, countdown_sec)
	network_manager.broadcast_start_countdown(1.0, countdown_sec)

func _on_server_countdown_step(step_text: String) -> void:
	if step_text.is_valid_int():
		_countdown_remaining = maxi(1, int(step_text))

func _on_server_countdown_finished() -> void:
	_countdown_active = false
	_countdown_remaining = 0
	_lock_all_tanks(false)
	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null and mm.has_method("start_match"):
		mm.start_match(180.0)
	_broadcast_tank_snapshots()

func _build_initial_world_payload() -> Dictionary:
	var pus: Array[Dictionary] = []
	if get_tree() != null:
		for pu in get_tree().get_nodes_in_group("powerups"):
			if is_instance_valid(pu) and main_game.is_ancestor_of(pu) and pu.get("is_collected") != true and pu is Node2D:
				pus.append({
					"id": int(pu.get("net_id")),
					"type": int(pu.get("powerup_type")),
					"pos": (pu as Node2D).global_position
				})

	var broken_barrels: Array[int] = []
	for b_slot in _barrels_by_slot.keys():
		var b: Node = _barrels_by_slot[b_slot]
		if is_instance_valid(b) and b.get("is_exploded") == true:
			broken_barrels.append(int(b_slot))

	var wall_states: Array[Dictionary] = []
	for w_slot in _walls_by_slot.keys():
		var w: Node = _walls_by_slot[w_slot]
		if is_instance_valid(w):
			var destroyed: bool = w.get("is_destroyed") == true
			var hp_val: float = float(w.get("current_health"))
			var max_hp_val: float = float(w.get("max_health"))
			if destroyed or hp_val < max_hp_val:
				wall_states.append({"slot": int(w_slot), "hp": hp_val, "destroyed": destroyed})

	var mm := main_game.get_node_or_null("MatchManager")
	var m_state: Dictionary = mm.serialize_match_state() if (mm != null and mm.has_method("serialize_match_state")) else {}
	var lb: Array = mm.serialize_leaderboard() if (mm != null and mm.has_method("serialize_leaderboard")) else []

	return {
		"tank_positions": _initial_spawn_positions,
		"powerups": pus,
		"broken_barrels": broken_barrels,
		"wall_states": wall_states,
		"match_state": m_state,
		"leaderboard": lb,
		"countdown_left": _countdown_remaining if _countdown_active else 0
	}

func _broadcast_tank_snapshots() -> void:
	var snaps: Array = []
	var slot_keys := _tanks_by_slot.keys()
	slot_keys.sort()
	for slot in slot_keys:
		var t: Node2D = _tanks_by_slot[slot] as Node2D
		if not is_instance_valid(t):
			continue
		var tp := t.get_node_or_null("TurretPivot") as Node2D
		var tur_ang: float = tp.global_rotation if tp != null else float(t.get("target_aim_angle"))
		var ch_ang: float = float(t.get("_chassis_angle"))
		var flags: int = t.get_network_flags() if t.has_method("get_network_flags") else 0
		snaps.append([
			int(slot),
			t.global_position.x,
			t.global_position.y,
			ch_ang,
			tur_ang,
			float(t.get("current_health")),
			float(t.get("shield")),
			flags,
			float(t.get("dash_stamina")),
			int(t.get("mines_count")),
			int(t.get("ricochet_shots"))
		])
	network_manager.broadcast_tank_snapshots(snaps)

# ------------------------------------------------------------------------------
# Server Incoming Peer Handlers
# ------------------------------------------------------------------------------

func on_client_scene_ready(peer_id: int) -> void:
	if not is_server:
		return
	_ready_peers[peer_id] = true
	network_manager.broadcast_initial_world_to(peer_id, _build_initial_world_payload())

func on_client_input(peer_id: int, move_dir: Vector2, aim_angle: float, wants_shoot: bool, wants_dash: bool) -> void:
	if not is_server:
		return
	var tank: Node = _tanks_by_peer.get(peer_id, null)
	if tank != null and is_instance_valid(tank) and tank.has_method("apply_remote_input"):
		tank.apply_remote_input(move_dir, aim_angle, wants_shoot, wants_dash)

func on_client_throw_mine(peer_id: int, aim_angle: float) -> void:
	if not is_server:
		return
	var tank: Node = _tanks_by_peer.get(peer_id, null)
	if tank != null and is_instance_valid(tank):
		if tank.has_method("set_turret_aim_angle"):
			tank.set_turret_aim_angle(aim_angle)
		var tp := tank.get_node_or_null("TurretPivot") as Node2D
		if tp != null:
			tp.global_rotation = aim_angle
		if tank.has_method("throw_mine"):
			tank.throw_mine()

func on_peer_disconnected(peer_id: int) -> void:
	if not is_server:
		return
	_ready_peers.erase(peer_id)
	var tank: Node = _tanks_by_peer.get(peer_id, null)
	if tank != null and is_instance_valid(tank):
		if "is_human_remote" in tank:
			tank.set("is_human_remote", false)
		if tank.has_method("apply_remote_input"):
			tank.apply_remote_input(Vector2.ZERO, 0.0, false, false)
		if tank.get("is_dead") != true and tank.has_method("eliminate"):
			tank.set("permanently_eliminated", true)
			tank.eliminate(null, false)

func on_leader_restart_requested() -> void:
	if not is_server:
		return
	_assign_initial_spawn_positions()

	for b_slot in _barrels_by_slot.keys():
		var b: Node = _barrels_by_slot[b_slot]
		if is_instance_valid(b) and b.has_method("respawn_barrel"):
			b.respawn_barrel()

	for w_slot in _walls_by_slot.keys():
		var w: Node = _walls_by_slot[w_slot]
		if is_instance_valid(w) and w.has_method("restore"):
			w.restore()

	if get_tree() != null:
		for pu in get_tree().get_nodes_in_group("powerups"):
			if is_instance_valid(pu) and main_game.is_ancestor_of(pu):
				pu.queue_free()

	for slot in _tanks_by_slot.keys():
		var t: Node2D = _tanks_by_slot[slot] as Node2D
		if is_instance_valid(t) and slot < _initial_spawn_positions.size() and t.has_method("respawn"):
			t.respawn(_initial_spawn_positions[slot])

	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null and mm.has_method("restart_match"):
		mm.restart_match()

	var mortar_mgr := main_game.get_node_or_null("MortarManager")
	if mortar_mgr != null and mortar_mgr.has_method("reset"):
		mortar_mgr.reset()

	_lock_all_tanks(false)
	network_manager.broadcast_restart_match(_initial_spawn_positions)

	var sm := main_game.get_node_or_null("SpawnManager")
	if sm != null and sm.has_method("spawn_powerup"):
		for _i in range(min(24, int(sm.get("max_powerups")))):
			sm.spawn_powerup()
	_broadcast_tank_snapshots()

# ------------------------------------------------------------------------------
# Server Event Emitters -> Client RPCs
# ------------------------------------------------------------------------------

func _on_server_projectile_spawned(tank: Node2D, proj: Node2D, spawn_pos: Vector2, shoot_dir: Vector2, p_speed: float, p_damage: float, is_ric: bool, bounces: int) -> void:
	var pid := _next_proj_id
	_next_proj_id += 1
	if "net_id" in proj:
		proj.set("net_id", pid)
	_projectiles_by_id[pid] = proj
	if proj.has_signal("network_impacted"):
		proj.network_impacted.connect(_on_server_projectile_impacted.bind(pid))
	var shooter_slot := int(tank.get("net_slot")) if is_instance_valid(tank) else -1
	network_manager.broadcast_spawn_projectile(pid, shooter_slot, spawn_pos, shoot_dir, p_speed, p_damage, is_ric, bounces)

func _on_server_projectile_impacted(_proj: Node2D, hit_pos: Vector2, proj_id: int) -> void:
	_projectiles_by_id.erase(proj_id)
	network_manager.broadcast_destroy_projectile(proj_id, hit_pos)

func _on_server_mine_spawned(tank: Node2D, mine: Node2D, start_pos: Vector2, target_pos: Vector2, is_cluster: bool, play_sound: bool) -> void:
	var mid := _next_mine_id
	_next_mine_id += 1
	if "net_id" in mine:
		mine.set("net_id", mid)
	_mines_by_id[mid] = mine
	if mine.has_signal("network_mine_detonated"):
		mine.network_mine_detonated.connect(_on_server_mine_detonated.bind(mid))
	var owner_slot := int(tank.get("net_slot")) if is_instance_valid(tank) else -1
	network_manager.broadcast_spawn_mine(mid, owner_slot, start_pos, target_pos, is_cluster, play_sound)

func _on_server_mine_detonated(_mine: Node2D, mine_id: int) -> void:
	_mines_by_id.erase(mine_id)
	network_manager.broadcast_detonate_mine(mine_id)

func _on_server_tank_damaged(tank: Node2D, amount: float, kind: int) -> void:
	if is_instance_valid(tank):
		network_manager.broadcast_tank_damaged(int(tank.get("net_slot")), amount, kind)

func _on_server_tank_eliminated(tank: Node2D, killer_slot: int, is_barrel: bool, is_mine: bool, is_storm: bool, is_mortar: bool) -> void:
	if is_instance_valid(tank):
		network_manager.broadcast_tank_eliminated(int(tank.get("net_slot")), killer_slot, is_barrel, is_mine, is_storm, is_mortar)

func _on_server_tank_respawned(tank: Node2D, pos: Vector2) -> void:
	if is_instance_valid(tank):
		network_manager.broadcast_tank_respawned(int(tank.get("net_slot")), pos)

func _on_server_tank_powerup(tank: Node2D, p_type: int, duration: float, value: float, expired: bool) -> void:
	if is_instance_valid(tank):
		network_manager.broadcast_tank_powerup(int(tank.get("net_slot")), p_type, duration, value, expired)

func _on_server_killstreak_achieved(killer: Node2D, title: String, subtitle: String, color: Color, tier: int) -> void:
	if is_instance_valid(killer) and main_game.is_ancestor_of(killer) and "net_slot" in killer:
		network_manager.broadcast_killstreak_banner(int(killer.get("net_slot")), title, subtitle, color, tier)

func _on_server_powerup_spawned(pu: Node2D, p_type: int, pos: Vector2) -> void:
	if is_instance_valid(pu) and main_game.is_ancestor_of(pu):
		network_manager.broadcast_spawn_powerup(int(pu.get("net_id")), p_type, pos)

func _on_server_powerup_collected(pu: Node2D, collector: Node2D, _type: int) -> void:
	if is_instance_valid(pu) and main_game.is_ancestor_of(pu):
		var c_slot := int(collector.get("net_slot")) if (is_instance_valid(collector) and "net_slot" in collector) else -1
		network_manager.broadcast_collect_powerup(int(pu.get("net_id")), c_slot)

func _on_server_barrel_damaged(barrel: Node2D, new_hp: float) -> void:
	if is_instance_valid(barrel):
		network_manager.broadcast_barrel_event(int(barrel.get("net_slot")), 0, new_hp)

func _on_server_barrel_exploded(barrel: Node2D) -> void:
	if is_instance_valid(barrel):
		network_manager.broadcast_barrel_event(int(barrel.get("net_slot")), 1, 0.0)

func _on_server_barrel_respawned(barrel: Node2D) -> void:
	if is_instance_valid(barrel):
		network_manager.broadcast_barrel_event(int(barrel.get("net_slot")), 2, 0.0)

func _on_server_wall_damaged(wall: Node2D, new_hp: float) -> void:
	if is_instance_valid(wall):
		network_manager.broadcast_wall_event(int(wall.get("net_slot")), 0, new_hp)

func _on_server_wall_shattered(wall: Node2D) -> void:
	if is_instance_valid(wall):
		network_manager.broadcast_wall_event(int(wall.get("net_slot")), 1, 0.0)

func _on_server_wall_restored(wall: Node2D) -> void:
	if is_instance_valid(wall):
		network_manager.broadcast_wall_event(int(wall.get("net_slot")), 2, 0.0)

func _on_server_match_state_changed(state_dict: Dictionary) -> void:
	network_manager.broadcast_match_state(state_dict, true)

func _on_server_leaderboard_changed(entries: Array) -> void:
	network_manager.broadcast_leaderboard(entries)

func _on_server_mortar_state_changed(active: bool, duration: float) -> void:
	network_manager.broadcast_mortar_state(active, duration)

func _on_server_mortar_strike_spawned(pos: Vector2) -> void:
	network_manager.broadcast_mortar_strike(pos)

# ------------------------------------------------------------------------------
# Client Incoming RPC Appliers
# ------------------------------------------------------------------------------

func apply_initial_world(payload: Dictionary) -> void:
	var positions: Array = payload.get("tank_positions", [])
	for i in range(positions.size()):
		if _tanks_by_slot.has(i) and positions[i] is Vector2:
			var t: Node2D = _tanks_by_slot[i] as Node2D
			if is_instance_valid(t):
				if t.has_method("snap_network_position"):
					t.snap_network_position(positions[i])
				else:
					t.global_position = positions[i]
	if local_player_tank != null and "camera" in local_player_tank and local_player_tank.camera != null:
		local_player_tank.camera.reset_smoothing()
		local_player_tank.camera.force_update_scroll()

	var sm := main_game.get_node_or_null("SpawnManager")
	if sm != null and sm.has_method("spawn_network_powerup"):
		for pu in payload.get("powerups", []):
			if pu is Dictionary:
				sm.spawn_network_powerup(int(pu.get("id", 0)), int(pu.get("type", 0)), pu.get("pos", Vector2.ZERO))

	for b_slot in payload.get("broken_barrels", []):
		var b: Node = _barrels_by_slot.get(int(b_slot), null)
		if b != null and is_instance_valid(b) and b.has_method("apply_network_explode_fx"):
			b.apply_network_explode_fx()

	for ws in payload.get("wall_states", []):
		if ws is Dictionary:
			var w: Node = _walls_by_slot.get(int(ws.get("slot", -1)), null)
			if w != null and is_instance_valid(w):
				if bool(ws.get("destroyed", false)) and w.has_method("apply_network_shatter_fx"):
					w.apply_network_shatter_fx()
				elif w.has_method("apply_network_damage_fx"):
					w.apply_network_damage_fx(float(ws.get("hp", 125.0)))

	var m_state: Dictionary = payload.get("match_state", {})
	if not m_state.is_empty():
		apply_match_state(m_state)
		var is_active_now := bool(m_state.get("act", false))
		var is_ended_now := bool(m_state.get("end", false))
		if is_active_now and not is_ended_now:
			_lock_all_tanks(false)

	var lb: Array = payload.get("leaderboard", [])
	if not lb.is_empty():
		apply_leaderboard(lb)

	var cd_left: int = int(payload.get("countdown_left", 0))
	if cd_left > 0:
		apply_start_countdown(1.0, cd_left)

func apply_start_countdown(step_dur: float, total_sec: int) -> void:
	_lock_all_tanks(true)
	var overlay := main_game.get_node_or_null("CountdownOverlay")
	if overlay == null or total_sec <= 0:
		_lock_all_tanks(false)
		return
	if not overlay.countdown_finished.is_connected(_on_client_countdown_finished):
		overlay.countdown_finished.connect(_on_client_countdown_finished, CONNECT_ONE_SHOT)
	overlay.start_countdown(step_dur, total_sec)

func _on_client_countdown_finished() -> void:
	_lock_all_tanks(false)

func apply_tank_snapshots(snapshots: Array) -> void:
	for raw in snapshots:
		if not (raw is Array) or raw.size() < 8:
			continue
		var slot: int = int(raw[0])
		var tank: Node = _tanks_by_slot.get(slot, null)
		if tank == null or not is_instance_valid(tank) or not tank.has_method("apply_network_snapshot"):
			continue
		var pos := Vector2(float(raw[1]), float(raw[2]))
		var ch_ang := float(raw[3])
		var tur_ang := float(raw[4])
		var hp_val := float(raw[5])
		var sh_val := float(raw[6])
		var flags := int(raw[7])
		var dash_val := float(raw[8]) if raw.size() > 8 else -1.0
		var mines_val := int(raw[9]) if raw.size() > 9 else -1
		var ric_val := int(raw[10]) if raw.size() > 10 else -1
		tank.apply_network_snapshot(pos, ch_ang, tur_ang, hp_val, sh_val, flags, dash_val, mines_val, ric_val)

func apply_match_state(state_dict: Dictionary) -> void:
	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null and mm.has_method("apply_network_state"):
		mm.apply_network_state(state_dict)
	if bool(state_dict.get("act", false)) and not bool(state_dict.get("end", false)):
		_lock_all_tanks(false)

func apply_leaderboard(entries: Array) -> void:
	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null and mm.has_method("apply_network_leaderboard"):
		mm.apply_network_leaderboard(entries, local_tank_slot, _tanks_by_slot)

func apply_spawn_projectile(proj_id: int, shooter_slot: int, pos: Vector2, dir: Vector2, spd: float, dmg: float, is_ric: bool, bounces: int) -> void:
	if ProjectileScene == null:
		return
	var proj := ProjectileScene.instantiate() as Node2D
	if proj == null:
		return
	var shooter_tank: Node2D = _tanks_by_slot.get(shooter_slot, null) as Node2D
	proj.global_position = pos
	if "net_id" in proj:
		proj.set("net_id", proj_id)
	if "is_network_puppet" in proj:
		proj.set("is_network_puppet", true)
	if "is_ricochet" in proj:
		proj.set("is_ricochet", is_ric)
	if "bounces_remaining" in proj:
		proj.set("bounces_remaining", bounces)
	if proj.has_method("setup"):
		proj.setup(shooter_tank, dir, spd, dmg)

	var container := main_game.get_node_or_null("Entities/Projectiles")
	if container == null:
		container = main_game.get_node_or_null("Entities")
	if container != null:
		container.add_child(proj)
	_projectiles_by_id[proj_id] = proj

	if SoundManagerScript != null:
		SoundManagerScript.play_shoot(pos)
	if GameEvents != null:
		GameEvents.weapon_fired.emit(shooter_tank, pos)
		if shooter_slot == local_tank_slot:
			GameEvents.screen_shake_requested.emit(0.08)

func apply_destroy_projectile(proj_id: int, hit_pos: Vector2) -> void:
	var proj: Node = _projectiles_by_id.get(proj_id, null)
	_projectiles_by_id.erase(proj_id)
	if proj != null and is_instance_valid(proj) and proj.has_method("network_destroy"):
		proj.network_destroy(hit_pos)

func apply_spawn_mine(mine_id: int, owner_slot: int, start_pos: Vector2, target_pos: Vector2, is_cluster: bool, play_sound: bool) -> void:
	var mine := ProximityMineScript.new() as Node2D
	if mine == null:
		return
	var owner_tank: Node2D = _tanks_by_slot.get(owner_slot, null) as Node2D
	if "net_id" in mine:
		mine.set("net_id", mine_id)
	if "is_network_puppet" in mine:
		mine.set("is_network_puppet", true)
	var container := main_game.get_node_or_null("Entities")
	if container != null:
		container.add_child(mine)
	if mine.has_method("setup"):
		mine.setup(owner_tank, start_pos, target_pos, is_cluster, play_sound)
	_mines_by_id[mine_id] = mine

func apply_detonate_mine(mine_id: int) -> void:
	var mine: Node = _mines_by_id.get(mine_id, null)
	_mines_by_id.erase(mine_id)
	if mine != null and is_instance_valid(mine) and mine.has_method("apply_network_detonate_fx"):
		mine.apply_network_detonate_fx()

func apply_tank_damaged(victim_slot: int, amount: float, kind: int) -> void:
	var t: Node = _tanks_by_slot.get(victim_slot, null)
	if t != null and is_instance_valid(t) and t.has_method("apply_network_damage_fx"):
		t.apply_network_damage_fx(amount, kind)

func apply_tank_eliminated(victim_slot: int, killer_slot: int, is_barrel: bool, is_mine: bool, is_storm: bool, is_mortar: bool) -> void:
	var t: Node = _tanks_by_slot.get(victim_slot, null)
	if t != null and is_instance_valid(t) and t.has_method("apply_network_eliminate_fx"):
		t.apply_network_eliminate_fx(killer_slot, is_barrel, is_mine, is_storm, is_mortar, true)

func apply_tank_respawned(slot: int, pos: Vector2) -> void:
	var t: Node = _tanks_by_slot.get(slot, null)
	if t != null and is_instance_valid(t) and t.has_method("apply_network_respawn_fx"):
		t.apply_network_respawn_fx(pos)
		if GameEvents != null:
			GameEvents.tank_respawned.emit(t, pos)

func apply_tank_powerup(slot: int, p_type: int, duration: float, value: float, expired: bool) -> void:
	var t: Node = _tanks_by_slot.get(slot, null)
	if t == null or not is_instance_valid(t):
		return
	if expired:
		if "_active_powerups" in t:
			var active_dict: Dictionary = t.get("_active_powerups")
			active_dict.erase(p_type)
		if p_type == 1 and "shield" in t:
			t.set("shield", 0.0)
		elif p_type == 4 and t.has_method("_reset_monster_bounce"):
			t.call("_reset_monster_bounce")
		if GameEvents != null and slot == local_tank_slot:
			GameEvents.powerup_expired.emit(t, p_type)
	elif t.has_method("apply_network_powerup"):
		t.apply_network_powerup(p_type, duration, value, true)

func apply_killstreak_banner(slot: int, title: String, subtitle: String, color: Color, tier: int) -> void:
	var t: Node2D = _tanks_by_slot.get(slot, null) as Node2D
	if t == null or not is_instance_valid(t):
		return
	var is_local := (slot == local_tank_slot)
	if SoundManagerScript != null and (is_local or tier >= 2):
		SoundManagerScript.play_killstreak(tier, t.global_position, is_local)
	if GameEvents != null:
		GameEvents.killstreak_achieved.emit(t, title, subtitle, color, tier)
		GameEvents.kill_feed_announced.emit("RACHA • %s: %s" % [str(t.get("tank_name")), title], color)

func apply_spawn_powerup(net_id: int, p_type: int, pos: Vector2) -> void:
	var sm := main_game.get_node_or_null("SpawnManager")
	if sm != null and sm.has_method("spawn_network_powerup"):
		sm.spawn_network_powerup(net_id, p_type, pos)

func apply_collect_powerup(net_id: int, collector_slot: int) -> void:
	var sm := main_game.get_node_or_null("SpawnManager")
	var collector: Node2D = _tanks_by_slot.get(collector_slot, null) as Node2D
	if sm != null and sm.has_method("collect_network_powerup"):
		sm.collect_network_powerup(net_id, collector)

func apply_barrel_event(barrel_slot: int, kind: int, val: float) -> void:
	var b: Node = _barrels_by_slot.get(barrel_slot, null)
	if b == null or not is_instance_valid(b):
		return
	if kind == 0 and b.has_method("apply_network_damage_fx"):
		b.apply_network_damage_fx(val)
	elif kind == 1 and b.has_method("apply_network_explode_fx"):
		b.apply_network_explode_fx()
	elif kind == 2 and b.has_method("apply_network_respawn_fx"):
		b.apply_network_respawn_fx()

func apply_wall_event(wall_slot: int, kind: int, val: float) -> void:
	var w: Node = _walls_by_slot.get(wall_slot, null)
	if w == null or not is_instance_valid(w):
		return
	if kind == 0 and w.has_method("apply_network_damage_fx"):
		w.apply_network_damage_fx(val)
	elif kind == 1 and w.has_method("apply_network_shatter_fx"):
		w.apply_network_shatter_fx()
	elif kind == 2 and w.has_method("apply_network_restore_fx"):
		w.apply_network_restore_fx()

func apply_mortar_state(active: bool, duration: float) -> void:
	var mortar_mgr := main_game.get_node_or_null("MortarManager")
	if mortar_mgr != null and mortar_mgr.has_method("apply_network_mortar_state"):
		mortar_mgr.apply_network_mortar_state(active, duration)

func apply_mortar_strike(pos: Vector2) -> void:
	var mortar_mgr := main_game.get_node_or_null("MortarManager")
	if mortar_mgr != null and mortar_mgr.has_method("spawn_network_mortar_strike"):
		mortar_mgr.spawn_network_mortar_strike(pos)

func apply_restart_match(spawn_positions: Array) -> void:
	for b_slot in _barrels_by_slot.keys():
		var b: Node = _barrels_by_slot[b_slot]
		if is_instance_valid(b) and b.has_method("apply_network_respawn_fx"):
			b.apply_network_respawn_fx()

	for w_slot in _walls_by_slot.keys():
		var w: Node = _walls_by_slot[w_slot]
		if is_instance_valid(w) and w.has_method("apply_network_restore_fx"):
			w.apply_network_restore_fx()

	if get_tree() != null:
		for m in get_tree().get_nodes_in_group("mines"):
			if is_instance_valid(m) and main_game.is_ancestor_of(m):
				m.queue_free()
		for pu in get_tree().get_nodes_in_group("powerups"):
			if is_instance_valid(pu) and main_game.is_ancestor_of(pu):
				pu.queue_free()
	_mines_by_id.clear()
	_projectiles_by_id.clear()

	for i in range(spawn_positions.size()):
		if _tanks_by_slot.has(i) and spawn_positions[i] is Vector2:
			var t: Node2D = _tanks_by_slot[i] as Node2D
			if is_instance_valid(t) and t.has_method("apply_network_respawn_fx"):
				t.apply_network_respawn_fx(spawn_positions[i])

	var mm := main_game.get_node_or_null("MatchManager")
	if mm != null:
		mm.set("is_match_ended", false)
		mm.set("is_sudden_death", false)
		mm.set("no_respawns", false)
		mm.set("is_match_active", true)
		mm.set("time_remaining", float(mm.get("match_duration")))
		mm.set("safe_zone_radius", float(mm.get("max_zone_radius")))

	var mortar_mgr := main_game.get_node_or_null("MortarManager")
	if mortar_mgr != null and mortar_mgr.has_method("reset"):
		mortar_mgr.reset()

	_lock_all_tanks(false)
	if GameEvents != null:
		GameEvents.match_started.emit(float(mm.get("match_duration")) if mm != null else 180.0)
