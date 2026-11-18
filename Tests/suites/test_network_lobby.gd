# res://Tests/suites/test_network_lobby.gd
extends TestBase

## Verification suite for Phase 1 Dedicated WebSocket Server & Online Lobby Sync.
## Tests URL normalization, real WebSocketMultiplayerPeer loopback server + 2 clients,
## name deduplication, leader permissions, bot controls, UI lobby sync, and match launch.

const NetworkManagerScript = preload("res://Scripts/Core/network_manager.gd")

func teardown() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("clear_lobby_match"):
		gs.clear_lobby_match()
	super.teardown()

func _create_isolated_network_branch(branch_name: String) -> Dictionary:
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
	branch.add_child(nm)

	return {"branch": branch, "mp": mp, "nm": nm}

func _cleanup_isolated_branch(info: Dictionary) -> void:
	var nm: Node = info.get("nm")
	if nm != null and is_instance_valid(nm) and nm.has_method("disconnect_network"):
		nm.disconnect_network()
	var branch: Node = info.get("branch")
	if branch != null and is_instance_valid(branch):
		get_tree().set_multiplayer(null, branch.get_path())

func test_01_websocket_url_normalization() -> void:
	assert_equal(NetworkManagerScript.normalize_ws_url(""), "ws://127.0.0.1:7777", "Empty URL defaults to local WS")
	assert_equal(NetworkManagerScript.normalize_ws_url("127.0.0.1:7777"), "ws://127.0.0.1:7777", "Bare loopback IP:port resolves to ws://")
	assert_equal(NetworkManagerScript.normalize_ws_url("localhost"), "ws://localhost:7777", "Bare localhost adds ws:// and default port")
	assert_equal(NetworkManagerScript.normalize_ws_url("192.168.1.40:8080/"), "ws://192.168.1.40:8080", "LAN IP keeps ws:// and trims trailing slash")
	assert_equal(NetworkManagerScript.normalize_ws_url("tank-demo.trycloudflare.com"), "wss://tank-demo.trycloudflare.com", "Public tunnel domain auto-selects wss://")
	assert_equal(NetworkManagerScript.normalize_ws_url("https://tank-demo.trycloudflare.com/"), "wss://tank-demo.trycloudflare.com", "https:// upgrades to wss://")
	assert_equal(NetworkManagerScript.normalize_ws_url("wss://custom.domain.com:8443"), "wss://custom.domain.com:8443", "Explicit wss:// is preserved")

func test_02_real_websocket_lobby_sync_leader_bots_and_launch() -> void:
	var test_port := 17845
	var srv_info := _create_isolated_network_branch("NetTestServer")
	var c1_info := _create_isolated_network_branch("NetTestClient1")
	var c2_info := _create_isolated_network_branch("NetTestClient2")

	var srv: Node = srv_info["nm"]
	var c1: Node = c1_info["nm"]
	var c2: Node = c2_info["nm"]

	# Attach MatchBrowserPanel to Client 1 using network_manager_override
	var browser = spawn_scene("res://Scenes/match_browser_panel.tscn")
	assert_not_null(browser, "MatchBrowserPanel must instantiate")
	browser.navigate_on_launch = false
	browser.network_manager_override = c1
	browser._connect_network_signals()

	# 1. Start Dedicated WebSocket Server
	var err_srv: int = srv.start_dedicated_server(test_port, "Sala Escolar Test", 10, "127.0.0.1")
	assert_equal(err_srv, OK, "Dedicated WebSocket server must bind loopback port cleanly")
	assert_true(srv.is_server_active(), "Server must report active")

	# 2. Connect Client 1 ("Ana") and Client 2 ("Ana" -> deduplicates to "Ana (2)")
	var err_c1: int = c1.connect_to_server("ws://127.0.0.1:%d" % test_port, "Ana", Color(0.2, 0.8, 0.4, 1.0))
	assert_equal(err_c1, OK, "Client 1 WebSocket connection must initiate")
	await wait_process_frames(15)

	var err_c2: int = c2.connect_to_server("127.0.0.1:%d" % test_port, "Ana", Color(0.9, 0.3, 0.3, 1.0))
	assert_equal(err_c2, OK, "Client 2 WebSocket connection must initiate")

	# Pump frames until both clients have registered and received the 2-player roster
	for _step in range(90):
		await wait_process_frames(1)
		if c1.current_roster.size() == 2 and c2.current_roster.size() == 2:
			break

	assert_equal(c1.connection_state, "connected", "Client 1 must reach connected state")
	assert_equal(c2.connection_state, "connected", "Client 2 must reach connected state")
	assert_equal(c1.current_roster.size(), 2, "Client 1 must observe 2 human players in lobby")
	assert_equal(c2.current_roster.size(), 2, "Client 2 must observe 2 human players in lobby")
	assert_true(c1.is_local_leader(), "First connected player (Client 1) must be room leader")
	assert_false(c2.is_local_leader(), "Second player (Client 2) must NOT be room leader")

	# Verify name deduplication and localized is_player flags
	assert_equal(str(c1.current_roster[0].get("name")), "Ana", "Client 1 keeps base name")
	assert_equal(str(c1.current_roster[1].get("name")), "Ana (2)", "Duplicate name is deduplicated cleanly")
	assert_true(c1.current_roster[0].get("is_player") == true and c1.current_roster[1].get("is_player") == false, "Client 1 marks only self as is_player")
	assert_true(c2.current_roster[1].get("is_player") == true and c2.current_roster[0].get("is_player") == false, "Client 2 marks only self as is_player")

	# Verify MatchBrowserPanel automatically entered server LobbyView
	assert_true(browser.in_lobby, "MatchBrowserPanel must enter LobbyView upon server sync")
	assert_equal(browser.lobby_mode, "server", "MatchBrowserPanel must enter server mode")
	assert_true(browser.start_match_btn.disabled, "Start button must stay disabled with 2/5 players")

	# 3. Non-leader cannot add bots; Leader CAN add bots and change capacity
	c2.request_add_bot()
	await wait_process_frames(10)
	assert_equal(srv.current_roster.size(), 2, "Non-leader bot request must be ignored by server")

	c1.request_set_capacity(12)
	c1.request_fill_bots()
	for _step in range(60):
		await wait_process_frames(1)
		if c2.current_roster.size() == 12 and c2.max_players == 12:
			break

	assert_equal(srv.current_roster.size(), 12, "Server roster fills to capacity 12")
	assert_equal(c1.current_roster.size(), 12, "Client 1 roster syncs to 12")
	assert_equal(c2.current_roster.size(), 12, "Client 2 roster syncs to 12")
	assert_false(browser.start_match_btn.disabled, "Start button unlocks once >= 5 combatants are synced")

	# 4. Leader launches match -> both clients receive match_launch_requested
	var c1_launches := [0]
	var c2_launches := [0]
	c1.match_launch_requested.connect(func(_r, _m, _ros): c1_launches[0] += 1)
	c2.match_launch_requested.connect(func(_r, _m, _ros): c2_launches[0] += 1)

	browser.start_configured_match()
	for _step in range(60):
		await wait_process_frames(1)
		if c1_launches[0] > 0 and c2_launches[0] > 0:
			break

	assert_equal(c1_launches[0], 1, "Client 1 must receive match launch signal")
	assert_equal(c2_launches[0], 1, "Client 2 must receive match launch signal")
	assert_true(srv.match_in_progress, "Server marks match in progress")

	# 5. Leader disconnects -> Client 2 promoted; when all leave, server resets cleanly
	_cleanup_isolated_branch(c1_info)
	for _step in range(60):
		await wait_process_frames(1)
		if c2.is_local_leader():
			break
	assert_true(c2.is_local_leader(), "Remaining player (Client 2) must be promoted to leader when leader leaves")

	_cleanup_isolated_branch(c2_info)
	for _step in range(60):
		await wait_process_frames(1)
		if not srv.match_in_progress and srv.leader_peer_id == 0:
			break
	assert_false(srv.match_in_progress, "Server resets match_in_progress when all human players leave")
	assert_equal(srv.leader_peer_id, 0, "Server clears leader_peer_id when empty")

	_cleanup_isolated_branch(srv_info)

func test_03_match_browser_preserve_active_server_on_boot() -> void:
	var test_port := 17846
	var srv_info := _create_isolated_network_branch("NetServerBoot")
	var c1_info := _create_isolated_network_branch("NetClientAfterBoot")
	var srv: Node = srv_info["nm"]
	var c1: Node = c1_info["nm"]

	var err_srv: int = srv.start_dedicated_server(test_port, "Sala Persistente", 10, "127.0.0.1")
	assert_equal(err_srv, OK, "Dedicated server starts on loopback")
	assert_true(srv.is_server_active(), "Server must be active before MainMenu/MatchBrowser mounts")

	# Simulates MainMenu + MatchBrowserPanel._ready() running after NetworkManager autoload started server
	var browser = spawn_scene("res://Scenes/match_browser_panel.tscn")
	assert_not_null(browser, "MatchBrowserPanel instantiates")
	browser.network_manager_override = srv
	browser.show_browse_view()
	await wait_process_frames(5)

	assert_true(srv.is_server_active(), "MatchBrowserPanel.show_browse_view() must NOT shut down an active server")
	assert_equal(srv.role, "server", "Server role must stay 'server'")

	var err_c1: int = c1.connect_to_server("ws://127.0.0.1:%d" % test_port, "WebPlayer", Color(0.2, 0.85, 0.95, 1.0))
	assert_equal(err_c1, OK, "Client must still be able to connect after MatchBrowserPanel mounted")
	for _step in range(90):
		await wait_process_frames(1)
		if c1.connection_state == "connected" and c1.current_roster.size() == 1:
			break

	assert_equal(c1.connection_state, "connected", "Client must connect cleanly to server after menu boot")
	assert_equal(c1.current_roster.size(), 1, "Client must receive lobby roster from live server")

	_cleanup_isolated_branch(c1_info)
	_cleanup_isolated_branch(srv_info)

func test_04_cloud_retry_mode_and_bind_address_support() -> void:
	var srv_info := _create_isolated_network_branch("NetBindServer")
	var srv: Node = srv_info["nm"]
	var err_srv: int = srv.start_dedicated_server(17847, "Render Cloud", 10, "127.0.0.1")
	assert_equal(err_srv, OK, "Dedicated server accepts explicit IPv4 bind address")
	assert_true(srv.is_server_active(), "Explicit bind server is active")

	var c_info := _create_isolated_network_branch("NetRetryClient")
	var cli: Node = c_info["nm"]
	cli.connect_to_server("ws://127.0.0.1:17847", "LocalP", Color.WHITE)
	assert_false(cli.get("_allow_cloud_retry"), "ws:// local connections fail fast without 75s cloud wake retry")
	cli.disconnect_network()

	# Check WSS cloud retry flag cleanly enabled without waiting 75s
	cli.connect_to_server("wss://127.0.0.1:17899", "CloudP", Color.CYAN)
	assert_true(cli.get("_allow_cloud_retry"), "wss:// cloud URLs enable automatic Render cold-start wake retry")
	cli.disconnect_network()
	assert_false(cli.get("_allow_cloud_retry"), "disconnect_network disables pending cloud wake retries cleanly")

	_cleanup_isolated_branch(c_info)
	_cleanup_isolated_branch(srv_info)
