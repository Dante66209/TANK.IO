# res://Scripts/Core/network_manager.gd
extends Node

## WebSocket Multiplayer Manager for TANK.IO (Godot 4.6).
## Supports Dedicated Headless Server (--server / --port=7777) and Web/Desktop Clients
## over WebSocketMultiplayerPeer (ws:// locally or wss:// via tunnel/proxy for itch.io).

signal connection_state_changed(state: String, detail: String)
signal lobby_state_updated(room_name: String, max_players: int, roster: Array, leader_peer_id: int, autofill_bots: bool, match_in_progress: bool)
signal match_launch_requested(room_name: String, max_players: int, roster: Array)
signal server_error(message: String)

const DEFAULT_PORT: int = 7777
const MIN_PLAYERS: int = 5
const MAX_PLAYERS: int = 30
const CONNECT_TIMEOUT_SEC: float = 10.0
const CLOUD_CONNECT_BUDGET_SEC: float = 75.0
const CLOUD_RETRY_INTERVAL_SEC: float = 3.0
const AUTOFILL_INTERVAL_SEC: float = 0.55

const MAIN_GAME_SCENE_PATH: String = "res://Scenes/main_game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://Scenes/main_menu.tscn"

@export var enable_cli_autostart: bool = true
@export var auto_manage_server_scene: bool = true
@export var online_countdown_seconds: int = 5

var active_match_sync: Node = null

var role: String = "offline" # "offline", "server", "client"
var connection_state: String = "offline" # "offline", "connecting", "connected", "hosting", "error"
var server_port: int = DEFAULT_PORT
var target_server_url: String = "ws://127.0.0.1:7777"

# Shared / Synchronized Lobby State
var room_name: String = "Arena Online TANK.IO"
var max_players: int = 10
var autofill_bots: bool = false
var auto_start_when_full: bool = false
var match_in_progress: bool = false
var leader_peer_id: int = 0
var current_roster: Array[Dictionary] = []

# Server-only internal registries
var _human_peers: Dictionary = {} # peer_id -> Dictionary
var _human_order: Array[int] = []
var _bot_count: int = 0
var _autofill_timer: float = 0.0

# Client-only pending state
var _pending_player_name: String = "Player"
var _pending_player_color: Color = Color(0.2, 0.45, 0.75, 1.0)
var _connect_elapsed: float = 0.0
var _total_connect_elapsed: float = 0.0
var _retry_wait_remaining: float = -1.0
var _connect_attempt: int = 0
var _allow_cloud_retry: bool = false
var _signals_bound: bool = false

func _ready() -> void:
	if enable_cli_autostart:
		_check_cli_autostart()

func _process(delta: float) -> void:
	if role == "client" and connection_state == "connecting":
		_total_connect_elapsed += delta
		if _retry_wait_remaining >= 0.0:
			_retry_wait_remaining -= delta
			if _retry_wait_remaining <= 0.0:
				_retry_wait_remaining = -1.0
				_connect_attempt += 1
				_set_state("connecting", "Despertando servidor en la nube... intento %d (%ds)" % [_connect_attempt, int(_total_connect_elapsed)])
				var retry_err := _open_client_peer()
				if retry_err != OK:
					_handle_connect_failure(
						"URL o socket inválido (%s, error %d)" % [target_server_url, retry_err],
						"No se pudo conectar con %s (error %d)." % [target_server_url, retry_err]
					)
			return

		_connect_elapsed += delta
		if _connect_elapsed >= CONNECT_TIMEOUT_SEC:
			_handle_connect_failure(
				"Tiempo de espera agotado al conectar con %s" % target_server_url,
				"No se pudo conectar con %s (tiempo agotado). Verifica que el servidor esté en línea." % target_server_url
			)
		return

	if role == "server" and is_server_active():
		_process_server_lobby(delta)

func _check_cli_autostart() -> void:
	var all_args: Array[String] = []
	all_args.append_array(OS.get_cmdline_user_args())
	all_args.append_array(OS.get_cmdline_args())

	var wants_server: bool = OS.has_feature("dedicated_server") or OS.get_environment("DEDICATED_SERVER").to_lower() in ["1", "true", "yes"]
	var cli_port: int = DEFAULT_PORT
	var env_port := OS.get_environment("PORT").strip_edges()
	if not env_port.is_empty() and env_port.is_valid_int():
		cli_port = clampi(int(env_port), 1024, 65535)

	var cli_bind: String = "*"
	var env_bind := OS.get_environment("BIND_ADDRESS").strip_edges()
	if not env_bind.is_empty():
		cli_bind = env_bind

	var cli_room: String = "Arena Online TANK.IO"
	var env_room := OS.get_environment("ROOM_NAME").strip_edges()
	if not env_room.is_empty():
		cli_room = env_room.substr(0, 28)

	var cli_max_players: int = 10
	var env_max := OS.get_environment("MAX_PLAYERS").strip_edges()
	if not env_max.is_empty() and env_max.is_valid_int():
		cli_max_players = clampi(int(env_max), MIN_PLAYERS, MAX_PLAYERS)

	var cli_autofill: bool = OS.get_environment("AUTOFILL_BOTS").to_lower() in ["1", "true", "yes"]
	var cli_autostart: bool = OS.get_environment("AUTO_START").to_lower() in ["1", "true", "yes"]

	for arg in all_args:
		if arg == "--server":
			wants_server = true
		elif arg.begins_with("--port="):
			cli_port = clampi(int(arg.trim_prefix("--port=")), 1024, 65535)
		elif arg.begins_with("--bind="):
			var parsed_bind := arg.trim_prefix("--bind=").strip_edges()
			if not parsed_bind.is_empty():
				cli_bind = parsed_bind
		elif arg.begins_with("--room="):
			var parsed_room := arg.trim_prefix("--room=").strip_edges()
			if not parsed_room.is_empty():
				cli_room = parsed_room.substr(0, 28)
		elif arg.begins_with("--max-players="):
			cli_max_players = clampi(int(arg.trim_prefix("--max-players=")), MIN_PLAYERS, MAX_PLAYERS)
		elif arg == "--autofill":
			cli_autofill = true
		elif arg == "--auto-start":
			cli_autostart = true

	if wants_server:
		autofill_bots = cli_autofill
		auto_start_when_full = cli_autostart
		start_dedicated_server(cli_port, cli_room, cli_max_players, cli_bind)

func is_online() -> bool:
	return role != "offline" and multiplayer != null and multiplayer.multiplayer_peer != null

func is_server_active() -> bool:
	return role == "server" and multiplayer != null and multiplayer.multiplayer_peer != null and multiplayer.is_server()

func is_local_leader() -> bool:
	if role != "client" or connection_state != "connected" or multiplayer == null:
		return false
	return leader_peer_id != 0 and leader_peer_id == multiplayer.get_unique_id()

func get_local_peer_id() -> int:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

static func normalize_ws_url(raw_url: String) -> String:
	var cleaned := raw_url.strip_edges()
	while cleaned.ends_with("/"):
		cleaned = cleaned.substr(0, cleaned.length() - 1)

	if cleaned.is_empty():
		return "ws://127.0.0.1:%d" % DEFAULT_PORT

	if cleaned.begins_with("https://"):
		cleaned = "wss://" + cleaned.trim_prefix("https://")
	elif cleaned.begins_with("http://"):
		cleaned = "ws://" + cleaned.trim_prefix("http://")

	if not cleaned.begins_with("ws://") and not cleaned.begins_with("wss://"):
		var host_only := _extract_host(cleaned)
		if _is_local_or_lan_host(host_only):
			cleaned = "ws://" + cleaned
			if ":" not in _strip_scheme(cleaned):
				cleaned += ":%d" % DEFAULT_PORT
		else:
			cleaned = "wss://" + cleaned

	return cleaned

static func _strip_scheme(url: String) -> String:
	if url.begins_with("wss://"):
		return url.trim_prefix("wss://")
	if url.begins_with("ws://"):
		return url.trim_prefix("ws://")
	return url

static func _extract_host(url_or_host: String) -> String:
	var no_scheme := _strip_scheme(url_or_host)
	var slash_idx := no_scheme.find("/")
	if slash_idx != -1:
		no_scheme = no_scheme.substr(0, slash_idx)
	var colon_idx := no_scheme.rfind(":")
	if colon_idx != -1 and not no_scheme.begins_with("["):
		no_scheme = no_scheme.substr(0, colon_idx)
	return no_scheme.to_lower()

static func _is_local_or_lan_host(host: String) -> bool:
	if host in ["127.0.0.1", "localhost", "::1", "[::1]"]:
		return true
	if host.begins_with("192.168.") or host.begins_with("10."):
		return true
	if host.begins_with("172."):
		var parts := host.split(".")
		if parts.size() >= 2:
			var second := int(parts[1])
			return second >= 16 and second <= 31
	return false

static func is_insecure_ws_on_https_web(url: String) -> bool:
	if not OS.has_feature("web") or not url.begins_with("ws://"):
		return false
	var host := _extract_host(url)
	if host in ["127.0.0.1", "localhost", "::1", "[::1]"]:
		return false
	if Engine.has_singleton("JavaScriptBridge"):
		var js := Engine.get_singleton("JavaScriptBridge")
		if js != null:
			var proto := str(js.call("eval", "window.location.protocol"))
			return proto == "https:"
	return true

func start_dedicated_server(port: int = DEFAULT_PORT, p_room_name: String = "Arena Online TANK.IO", p_max_players: int = 10, bind_address: String = "*") -> Error:
	disconnect_network()

	server_port = clampi(port, 1024, 65535)
	room_name = p_room_name.strip_edges()
	if room_name.is_empty():
		room_name = "Arena Online TANK.IO"
	max_players = clampi(p_max_players, MIN_PLAYERS, MAX_PLAYERS)
	match_in_progress = false
	leader_peer_id = 0
	_human_peers.clear()
	_human_order.clear()
	_bot_count = 0
	_autofill_timer = 0.0

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(server_port, bind_address)
	if err != OK:
		_set_state("error", "No se pudo iniciar el servidor WebSocket en puerto %d (error %d)" % [server_port, err])
		server_error.emit("No se pudo abrir el puerto %d (error %d)." % [server_port, err])
		return err

	_connect_multiplayer_signals()
	multiplayer.multiplayer_peer = peer
	role = "server"
	_rebuild_server_roster()
	_set_state("hosting", "Servidor WebSocket activo en puerto %d" % server_port)

	print("==============================================================")
	print("[SERVER] TANK.IO Dedicated WebSocket Server iniciado")
	print("[SERVER] Sala     : %s" % room_name)
	print("[SERVER] Puerto   : %d (bind: %s)" % [server_port, bind_address])
	print("[SERVER] Capacidad: %d jugadores (mínimo %d)" % [max_players, MIN_PLAYERS])
	print("[SERVER] Autofill : %s" % ("ON" if autofill_bots else "OFF"))
	print("[SERVER] Local WS : ws://127.0.0.1:%d" % server_port)
	print("==============================================================")
	return OK

func _close_multiplayer_peer() -> void:
	_disconnect_multiplayer_signals()
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _open_client_peer() -> Error:
	_close_multiplayer_peer()
	_connect_elapsed = 0.0
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(target_server_url)
	if err != OK:
		return err
	_connect_multiplayer_signals()
	multiplayer.multiplayer_peer = peer
	role = "client"
	return OK

func _handle_connect_failure(detail_msg: String, error_msg: String) -> void:
	if _allow_cloud_retry and role == "client" and connection_state == "connecting" and (_total_connect_elapsed + CLOUD_RETRY_INTERVAL_SEC) < CLOUD_CONNECT_BUDGET_SEC:
		_close_multiplayer_peer()
		_retry_wait_remaining = CLOUD_RETRY_INTERVAL_SEC
		_set_state("connecting", "Despertando servidor en la nube... reintento en %.0fs (%ds/%ds)" % [
			CLOUD_RETRY_INTERVAL_SEC,
			int(_total_connect_elapsed),
			int(CLOUD_CONNECT_BUDGET_SEC)
		])
		return
	_allow_cloud_retry = false
	_retry_wait_remaining = -1.0
	disconnect_network("error", detail_msg)
	server_error.emit(error_msg)

func connect_to_server(raw_url: String, p_name: String = "", p_color: Color = Color(0.2, 0.45, 0.75, 1.0)) -> Error:
	var normalized := normalize_ws_url(raw_url)
	if is_insecure_ws_on_https_web(normalized):
		var msg := "En itch.io (HTTPS) el navegador bloquea 'ws://'. Usa la URL segura 'wss://' de tu servidor (ej. wss://tu-app.onrender.com)."
		_set_state("error", msg)
		server_error.emit(msg)
		return ERR_INVALID_PARAMETER

	disconnect_network()

	target_server_url = normalized
	_pending_player_name = _sanitize_name(p_name)
	_pending_player_color = Color(p_color.r, p_color.g, p_color.b, 1.0)
	_total_connect_elapsed = 0.0
	_retry_wait_remaining = -1.0
	_connect_attempt = 1
	_allow_cloud_retry = target_server_url.begins_with("wss://")

	var err := _open_client_peer()
	if err != OK:
		_allow_cloud_retry = false
		var msg := "URL o socket inválido (%s, error %d)" % [target_server_url, err]
		_set_state("error", msg)
		server_error.emit(msg)
		return err

	_set_state("connecting", "Conectando a %s..." % target_server_url)
	return OK

func disconnect_network(final_state: String = "offline", detail: String = "") -> void:
	_close_multiplayer_peer()

	role = "offline"
	match_in_progress = false
	leader_peer_id = 0
	_human_peers.clear()
	_human_order.clear()
	_bot_count = 0
	current_roster.clear()
	_connect_elapsed = 0.0
	_total_connect_elapsed = 0.0
	_retry_wait_remaining = -1.0
	_connect_attempt = 0
	_allow_cloud_retry = false
	_set_state(final_state, detail)

# ------------------------------------------------------------------------------
# Client -> Server Lobby Action Requests
# ------------------------------------------------------------------------------

func register_match_sync(sync_node: Node) -> void:
	active_match_sync = sync_node

func unregister_match_sync(sync_node: Node) -> void:
	if active_match_sync == sync_node:
		active_match_sync = null

func get_connected_human_peer_ids() -> Array[int]:
	return _human_order.duplicate()

func request_restart_match() -> void:
	if is_local_leader():
		_rpc_request_restart_match.rpc_id(1)

func notify_match_scene_ready() -> void:
	if role == "client" and connection_state == "connected":
		_rpc_client_scene_ready.rpc_id(1)

func send_player_input(move_dir: Vector2, aim_angle: float, wants_shoot: bool, wants_dash: bool) -> void:
	if role == "client" and connection_state == "connected":
		_rpc_send_player_input.rpc_id(1, move_dir.x, move_dir.y, aim_angle, wants_shoot, wants_dash)

func send_player_throw_mine(aim_angle: float) -> void:
	if role == "client" and connection_state == "connected":
		_rpc_player_throw_mine.rpc_id(1, aim_angle)

# Server -> Client Gameplay Broadcast Helpers
func broadcast_initial_world_to(peer_id: int, payload: Dictionary) -> void:
	if is_server_active() and _human_peers.has(peer_id):
		_rpc_sync_initial_world.rpc_id(peer_id, payload)

func broadcast_start_countdown(step_dur: float, total_sec: int) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_start_match_countdown.rpc_id(pid, step_dur, total_sec)

func broadcast_tank_snapshots(snapshots: Array) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_sync_tank_snapshots.rpc_id(pid, snapshots)

func broadcast_match_state(state_dict: Dictionary, reliable_change: bool = false) -> void:
	if is_server_active():
		for pid in _human_order:
			if reliable_change:
				_rpc_sync_match_state_reliable.rpc_id(pid, state_dict)
			else:
				_rpc_sync_match_tick.rpc_id(pid, state_dict)

func broadcast_leaderboard(entries: Array) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_sync_leaderboard.rpc_id(pid, entries)

func broadcast_spawn_projectile(proj_id: int, shooter_slot: int, pos: Vector2, dir: Vector2, spd: float, dmg: float, is_ric: bool, bounces: int) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_spawn_projectile.rpc_id(pid, proj_id, shooter_slot, pos, dir, spd, dmg, is_ric, bounces)

func broadcast_destroy_projectile(proj_id: int, hit_pos: Vector2) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_destroy_projectile.rpc_id(pid, proj_id, hit_pos)

func broadcast_spawn_mine(mine_id: int, owner_slot: int, start_pos: Vector2, target_pos: Vector2, is_cluster: bool, play_sound: bool) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_spawn_mine.rpc_id(pid, mine_id, owner_slot, start_pos, target_pos, is_cluster, play_sound)

func broadcast_detonate_mine(mine_id: int) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_detonate_mine.rpc_id(pid, mine_id)

func broadcast_tank_damaged(victim_slot: int, amount: float, kind: int) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_tank_damaged.rpc_id(pid, victim_slot, amount, kind)

func broadcast_tank_eliminated(victim_slot: int, killer_slot: int, is_barrel: bool, is_mine: bool, is_storm: bool, is_mortar: bool) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_tank_eliminated.rpc_id(pid, victim_slot, killer_slot, is_barrel, is_mine, is_storm, is_mortar)

func broadcast_tank_respawned(slot: int, pos: Vector2) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_tank_respawned.rpc_id(pid, slot, pos)

func broadcast_tank_powerup(slot: int, p_type: int, duration: float, value: float, expired: bool) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_tank_powerup.rpc_id(pid, slot, p_type, duration, value, expired)

func broadcast_killstreak_banner(slot: int, title: String, subtitle: String, color: Color, tier: int) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_killstreak_banner.rpc_id(pid, slot, title, subtitle, color, tier)

func broadcast_spawn_powerup(net_id: int, p_type: int, pos: Vector2) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_spawn_powerup.rpc_id(pid, net_id, p_type, pos)

func broadcast_collect_powerup(net_id: int, collector_slot: int) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_collect_powerup.rpc_id(pid, net_id, collector_slot)

func broadcast_barrel_event(barrel_slot: int, kind: int, val: float) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_barrel_event.rpc_id(pid, barrel_slot, kind, val)

func broadcast_wall_event(wall_slot: int, kind: int, val: float) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_wall_event.rpc_id(pid, wall_slot, kind, val)

func broadcast_mortar_state(active: bool, duration: float) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_mortar_state.rpc_id(pid, active, duration)

func broadcast_mortar_strike(pos: Vector2) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_mortar_strike.rpc_id(pid, pos)

func broadcast_restart_match(spawn_positions: Array) -> void:
	if is_server_active():
		for pid in _human_order:
			_rpc_restart_match.rpc_id(pid, spawn_positions)

func request_add_bot() -> void:
	if is_local_leader():
		_rpc_request_add_bot.rpc_id(1)

func request_remove_bot() -> void:
	if is_local_leader():
		_rpc_request_remove_bot.rpc_id(1)

func request_fill_bots() -> void:
	if is_local_leader():
		_rpc_request_fill_bots.rpc_id(1)

func request_set_capacity(new_cap: int) -> void:
	if is_local_leader():
		_rpc_request_set_capacity.rpc_id(1, clampi(new_cap, MIN_PLAYERS, MAX_PLAYERS))

func request_set_autofill(enabled: bool) -> void:
	if is_local_leader():
		_rpc_request_set_autofill.rpc_id(1, enabled)

func request_start_match() -> void:
	if is_local_leader():
		_rpc_request_start_match.rpc_id(1)

# ------------------------------------------------------------------------------
# Multiplayer Signal Handlers
# ------------------------------------------------------------------------------

func _connect_multiplayer_signals() -> void:
	if multiplayer == null or _signals_bound:
		return
	_signals_bound = true
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _disconnect_multiplayer_signals() -> void:
	if multiplayer == null or not _signals_bound:
		return
	_signals_bound = false
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if role != "server":
		return
	print("[SERVER] Peer conectado: #%d (esperando registro de perfil)" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if role != "server":
		return
	var had_peer := _human_peers.has(peer_id)
	var old_name := str(_human_peers[peer_id].get("name", "Player")) if had_peer else str(peer_id)
	_human_peers.erase(peer_id)
	_human_order.erase(peer_id)

	if leader_peer_id == peer_id:
		leader_peer_id = _human_order[0] if not _human_order.is_empty() else 0

	if _human_peers.is_empty():
		var was_in_match := match_in_progress
		match_in_progress = false
		_bot_count = 0
		leader_peer_id = 0
		print("[SERVER] Todos los jugadores salieron. Sala '%s' reiniciada y lista." % room_name)
		if was_in_match and auto_manage_server_scene and get_tree() != null and ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
			get_tree().call_deferred("change_scene_to_file", MAIN_MENU_SCENE_PATH)
	elif had_peer:
		print("[SERVER] '%s' (#%d) desconectado. Líder actual: #%d" % [old_name, peer_id, leader_peer_id])
		if active_match_sync != null and active_match_sync.has_method("on_peer_disconnected"):
			active_match_sync.on_peer_disconnected(peer_id)

	_rebuild_and_broadcast_lobby_state()

func _on_connected_to_server() -> void:
	_connect_elapsed = 0.0
	_total_connect_elapsed = 0.0
	_retry_wait_remaining = -1.0
	_allow_cloud_retry = false
	_set_state("connected", "Conectado a %s (ID #%d)" % [target_server_url, multiplayer.get_unique_id()])
	_rpc_register_player.rpc_id(1, _pending_player_name, _pending_player_color.to_html(false))

func _on_connection_failed() -> void:
	var url := target_server_url
	_handle_connect_failure(
		"No se pudo conectar a %s" % url,
		"Conexión fallida con %s. Revisa la URL o si el servidor está en línea." % url
	)

func _on_server_disconnected() -> void:
	disconnect_network("error", "El servidor cerró la conexión")
	server_error.emit("Se perdió la conexión con el servidor dedicado.")

# ------------------------------------------------------------------------------
# Server Authoritative Lobby Simulation
# ------------------------------------------------------------------------------

func _process_server_lobby(delta: float) -> void:
	if match_in_progress or _human_peers.is_empty():
		_autofill_timer = 0.0
		return

	if autofill_bots:
		if _get_total_combatants() < max_players:
			_autofill_timer += delta
			if _autofill_timer >= AUTOFILL_INTERVAL_SEC:
				_autofill_timer = 0.0
				_bot_count += 1
				_rebuild_and_broadcast_lobby_state()
				_maybe_server_autostart()
	else:
		_autofill_timer = 0.0

func _maybe_server_autostart() -> void:
	if auto_start_when_full and not match_in_progress and _get_total_combatants() >= max_players and _get_total_combatants() >= MIN_PLAYERS:
		_server_launch_match()

func _get_total_combatants() -> int:
	return _human_peers.size() + _bot_count

func _sanitize_name(raw_name: String) -> String:
	var trimmed := raw_name.strip_edges()
	if trimmed.is_empty():
		return "Player"
	return trimmed.substr(0, 18)

func _deduplicate_name(desired: String, exclude_peer_id: int = -1) -> String:
	var base := _sanitize_name(desired)
	var candidate := base
	var suffix := 2
	while _name_in_use(candidate, exclude_peer_id):
		var tag := " (%d)" % suffix
		candidate = base.substr(0, maxi(1, 18 - tag.length())) + tag
		suffix += 1
	return candidate

func _name_in_use(candidate: String, exclude_peer_id: int) -> bool:
	for pid in _human_peers.keys():
		if int(pid) == exclude_peer_id:
			continue
		if str(_human_peers[pid].get("name", "")).to_lower() == candidate.to_lower():
			return true
	return false

func _rebuild_server_roster() -> void:
	var max_bots := maxi(0, max_players - _human_peers.size())
	_bot_count = clampi(_bot_count, 0, max_bots)

	current_roster.clear()
	for pid in _human_order:
		if not _human_peers.has(pid):
			continue
		var p: Dictionary = _human_peers[pid]
		current_roster.append({
			"peer_id": pid,
			"name": str(p.get("name", "Player")),
			"color": str(p.get("color", "3373bf")),
			"is_player": false,
			"is_human": true,
			"is_bot": false,
			"is_leader": (pid == leader_peer_id),
			"ready": true
		})

	var gs := get_node_or_null("/root/GameSettings")
	for i in range(_bot_count):
		var bot_name := "Bot #%d" % (i + 1)
		if gs != null and gs.has_method("get_bot_name_for_index"):
			bot_name = str(gs.get_bot_name_for_index(i))
		current_roster.append({
			"peer_id": 0,
			"name": bot_name,
			"color": "",
			"is_player": false,
			"is_human": false,
			"is_bot": true,
			"is_leader": false,
			"ready": true
		})

func _build_client_localized_roster(raw_roster: Array, local_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in raw_roster:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = (item as Dictionary).duplicate(true)
		var pid := int(entry.get("peer_id", 0))
		var is_human := bool(entry.get("is_human", pid > 0))
		entry["is_human"] = is_human
		entry["is_player"] = is_human and local_id > 0 and pid == local_id
		out.append(entry)
	return out

func _rebuild_and_broadcast_lobby_state() -> void:
	_rebuild_server_roster()
	var payload := {
		"room_name": room_name,
		"max_players": max_players,
		"roster": current_roster,
		"leader_peer_id": leader_peer_id,
		"autofill_bots": autofill_bots,
		"match_in_progress": match_in_progress
	}
	lobby_state_updated.emit(room_name, max_players, current_roster, leader_peer_id, autofill_bots, match_in_progress)
	for pid in _human_order:
		_rpc_sync_lobby_state.rpc_id(pid, payload)

func _server_launch_match() -> void:
	if not is_server_active() or match_in_progress:
		return
	if _get_total_combatants() < MIN_PLAYERS:
		return

	match_in_progress = true
	_rebuild_server_roster()

	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("configure_lobby_match"):
		gs.configure_lobby_match(current_roster, max_players, "server", room_name)

	var payload := {
		"room_name": room_name,
		"max_players": max_players,
		"roster": current_roster
	}
	print("[SERVER] Iniciando partida '%s' con %d combatientes (%d humanos + %d bots)" % [
		room_name, current_roster.size(), _human_peers.size(), _bot_count
	])
	match_launch_requested.emit(room_name, max_players, current_roster)
	for pid in _human_order:
		_rpc_launch_match.rpc_id(pid, payload)
	if auto_manage_server_scene and get_tree() != null and ResourceLoader.exists(MAIN_GAME_SCENE_PATH):
		get_tree().call_deferred("change_scene_to_file", MAIN_GAME_SCENE_PATH)

func _set_state(new_state: String, detail: String) -> void:
	connection_state = new_state
	connection_state_changed.emit(new_state, detail)

# ------------------------------------------------------------------------------
# RPC Endpoints
# ------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_player(p_name: String, color_hex: String) -> void:
	if not is_server_active():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return

	if _human_peers.size() >= MAX_PLAYERS and not _human_peers.has(sender_id):
		_rpc_reject_connection.rpc_id(sender_id, "La sala está llena (%d/%d)." % [_human_peers.size(), MAX_PLAYERS])
		return

	var unique_name := _deduplicate_name(p_name, sender_id)
	var clean_color := color_hex.strip_edges()
	if clean_color.is_empty():
		clean_color = "3373bf"

	_human_peers[sender_id] = {
		"peer_id": sender_id,
		"name": unique_name,
		"color": clean_color,
		"ready": true
	}
	if not _human_order.has(sender_id):
		_human_order.append(sender_id)

	if leader_peer_id == 0 or not _human_peers.has(leader_peer_id):
		leader_peer_id = sender_id

	print("[SERVER] Jugador registrado: '%s' (#%d) | Humanos: %d | Líder: #%d" % [
		unique_name, sender_id, _human_peers.size(), leader_peer_id
	])
	_rebuild_and_broadcast_lobby_state()
	_maybe_server_autostart()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_add_bot() -> void:
	if not is_server_active() or match_in_progress:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	if _get_total_combatants() < max_players:
		_bot_count += 1
		_rebuild_and_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_remove_bot() -> void:
	if not is_server_active() or match_in_progress:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	if _bot_count > 0:
		_bot_count -= 1
		_rebuild_and_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_fill_bots() -> void:
	if not is_server_active() or match_in_progress:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	_bot_count = maxi(0, max_players - _human_peers.size())
	_rebuild_and_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_set_capacity(new_cap: int) -> void:
	if not is_server_active() or match_in_progress:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	max_players = clampi(new_cap, maxi(MIN_PLAYERS, _human_peers.size()), MAX_PLAYERS)
	_rebuild_and_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_set_autofill(enabled: bool) -> void:
	if not is_server_active() or match_in_progress:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	autofill_bots = enabled
	_rebuild_and_broadcast_lobby_state()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_start_match() -> void:
	if not is_server_active() or match_in_progress:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	_server_launch_match()

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_lobby_state(payload: Dictionary) -> void:
	if role != "client":
		return
	room_name = str(payload.get("room_name", "Arena Online TANK.IO"))
	max_players = clampi(int(payload.get("max_players", 10)), MIN_PLAYERS, MAX_PLAYERS)
	leader_peer_id = int(payload.get("leader_peer_id", 0))
	autofill_bots = bool(payload.get("autofill_bots", false))
	match_in_progress = bool(payload.get("match_in_progress", false))

	var raw_roster: Array = payload.get("roster", [])
	current_roster = _build_client_localized_roster(raw_roster, get_local_peer_id())
	lobby_state_updated.emit(room_name, max_players, current_roster, leader_peer_id, autofill_bots, match_in_progress)

@rpc("authority", "call_remote", "reliable")
func _rpc_launch_match(payload: Dictionary) -> void:
	if role != "client":
		return
	var r_name := str(payload.get("room_name", room_name))
	var cap := clampi(int(payload.get("max_players", max_players)), MIN_PLAYERS, MAX_PLAYERS)
	var raw_roster: Array = payload.get("roster", [])
	var localized := _build_client_localized_roster(raw_roster, get_local_peer_id())
	current_roster = localized
	match_in_progress = true

	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("configure_lobby_match"):
		gs.configure_lobby_match(localized, cap, "server", r_name)

	match_launch_requested.emit(r_name, cap, localized)

@rpc("authority", "call_remote", "reliable")
func _rpc_reject_connection(reason: String) -> void:
	disconnect_network("error", reason)
	server_error.emit(reason)

# ------------------------------------------------------------------------------
# Phase 2 Gameplay RPC Endpoints (delegated to active_match_sync)
# ------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_scene_ready() -> void:
	if not is_server_active():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if active_match_sync != null and active_match_sync.has_method("on_client_scene_ready"):
		active_match_sync.on_client_scene_ready(sender_id)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_send_player_input(move_x: float, move_y: float, aim_angle: float, wants_shoot: bool, wants_dash: bool) -> void:
	if not is_server_active():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if active_match_sync != null and active_match_sync.has_method("on_client_input"):
		active_match_sync.on_client_input(sender_id, Vector2(move_x, move_y), aim_angle, wants_shoot, wants_dash)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_player_throw_mine(aim_angle: float) -> void:
	if not is_server_active():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if active_match_sync != null and active_match_sync.has_method("on_client_throw_mine"):
		active_match_sync.on_client_throw_mine(sender_id, aim_angle)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_restart_match() -> void:
	if not is_server_active():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != leader_peer_id:
		return
	if active_match_sync != null and active_match_sync.has_method("on_leader_restart_requested"):
		active_match_sync.on_leader_restart_requested()

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_initial_world(payload: Dictionary) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_initial_world"):
		active_match_sync.apply_initial_world(payload)

@rpc("authority", "call_remote", "reliable")
func _rpc_start_match_countdown(step_dur: float, total_sec: int) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_start_countdown"):
		active_match_sync.apply_start_countdown(step_dur, total_sec)

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_tank_snapshots(snapshots: Array) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_tank_snapshots"):
		active_match_sync.apply_tank_snapshots(snapshots)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_match_state_reliable(state_dict: Dictionary) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_match_state"):
		active_match_sync.apply_match_state(state_dict)

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_match_tick(state_dict: Dictionary) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_match_state"):
		active_match_sync.apply_match_state(state_dict)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_leaderboard(entries: Array) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_leaderboard"):
		active_match_sync.apply_leaderboard(entries)

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_projectile(proj_id: int, shooter_slot: int, pos: Vector2, dir: Vector2, spd: float, dmg: float, is_ric: bool, bounces: int) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_spawn_projectile"):
		active_match_sync.apply_spawn_projectile(proj_id, shooter_slot, pos, dir, spd, dmg, is_ric, bounces)

@rpc("authority", "call_remote", "reliable")
func _rpc_destroy_projectile(proj_id: int, hit_pos: Vector2) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_destroy_projectile"):
		active_match_sync.apply_destroy_projectile(proj_id, hit_pos)

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_mine(mine_id: int, owner_slot: int, start_pos: Vector2, target_pos: Vector2, is_cluster: bool, play_sound: bool) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_spawn_mine"):
		active_match_sync.apply_spawn_mine(mine_id, owner_slot, start_pos, target_pos, is_cluster, play_sound)

@rpc("authority", "call_remote", "reliable")
func _rpc_detonate_mine(mine_id: int) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_detonate_mine"):
		active_match_sync.apply_detonate_mine(mine_id)

@rpc("authority", "call_remote", "reliable")
func _rpc_tank_damaged(victim_slot: int, amount: float, kind: int) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_tank_damaged"):
		active_match_sync.apply_tank_damaged(victim_slot, amount, kind)

@rpc("authority", "call_remote", "reliable")
func _rpc_tank_eliminated(victim_slot: int, killer_slot: int, is_barrel: bool, is_mine: bool, is_storm: bool, is_mortar: bool) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_tank_eliminated"):
		active_match_sync.apply_tank_eliminated(victim_slot, killer_slot, is_barrel, is_mine, is_storm, is_mortar)

@rpc("authority", "call_remote", "reliable")
func _rpc_tank_respawned(slot: int, pos: Vector2) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_tank_respawned"):
		active_match_sync.apply_tank_respawned(slot, pos)

@rpc("authority", "call_remote", "reliable")
func _rpc_tank_powerup(slot: int, p_type: int, duration: float, value: float, expired: bool) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_tank_powerup"):
		active_match_sync.apply_tank_powerup(slot, p_type, duration, value, expired)

@rpc("authority", "call_remote", "reliable")
func _rpc_killstreak_banner(slot: int, title: String, subtitle: String, color: Color, tier: int) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_killstreak_banner"):
		active_match_sync.apply_killstreak_banner(slot, title, subtitle, color, tier)

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_powerup(net_id: int, p_type: int, pos: Vector2) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_spawn_powerup"):
		active_match_sync.apply_spawn_powerup(net_id, p_type, pos)

@rpc("authority", "call_remote", "reliable")
func _rpc_collect_powerup(net_id: int, collector_slot: int) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_collect_powerup"):
		active_match_sync.apply_collect_powerup(net_id, collector_slot)

@rpc("authority", "call_remote", "reliable")
func _rpc_barrel_event(barrel_slot: int, kind: int, val: float) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_barrel_event"):
		active_match_sync.apply_barrel_event(barrel_slot, kind, val)

@rpc("authority", "call_remote", "reliable")
func _rpc_wall_event(wall_slot: int, kind: int, val: float) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_wall_event"):
		active_match_sync.apply_wall_event(wall_slot, kind, val)

@rpc("authority", "call_remote", "reliable")
func _rpc_mortar_state(active: bool, duration: float) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_mortar_state"):
		active_match_sync.apply_mortar_state(active, duration)

@rpc("authority", "call_remote", "reliable")
func _rpc_mortar_strike(pos: Vector2) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_mortar_strike"):
		active_match_sync.apply_mortar_strike(pos)

@rpc("authority", "call_remote", "reliable")
func _rpc_restart_match(spawn_positions: Array) -> void:
	if role == "client" and active_match_sync != null and active_match_sync.has_method("apply_restart_match"):
		active_match_sync.apply_restart_match(spawn_positions)
