# res://Tests/suites/test_pre_server_menus_and_flow.gd
extends TestBase

## Verification suite for Pre-Server Menus, Match Browser & Lobby (5-30),
## Pre-Match Gray Screen Countdown & Controls Guide, Audio Settings, Credits,
## and In-Game ESC Pause Menu.

func teardown() -> void:
	if get_tree() != null:
		get_tree().paused = false
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		if gs.has_method("clear_lobby_match"):
			gs.clear_lobby_match()
		if gs.has_method("reset_defaults"):
			gs.reset_defaults(false)
	super.teardown()

func test_01_main_menu_boot_and_navigation() -> void:
	assert_equal(str(ProjectSettings.get_setting("application/run/main_scene")), "res://Scenes/main_menu.tscn", "Main scene must boot into MainMenu")
	var menu = spawn_scene("res://Scenes/main_menu.tscn")
	assert_not_null(menu, "MainMenu scene must instantiate cleanly")
	await wait_physics_frames(2)

	var home: Control = menu.get_node_or_null("HomeCenter")
	var browser: Control = menu.get_node_or_null("MatchBrowserPanel")
	var settings: Control = menu.get_node_or_null("SettingsPanel")
	var credits: Control = menu.get_node_or_null("CreditsPanel")
	assert_not_null(home, "MainMenu must have HomeCenter")
	assert_not_null(browser, "MainMenu must embed MatchBrowserPanel")
	assert_not_null(settings, "MainMenu must embed SettingsPanel")
	assert_not_null(credits, "MainMenu must embed CreditsPanel")
	assert_true(home.visible, "Home card must be visible on launch")
	assert_false(browser.visible, "MatchBrowserPanel starts hidden")

	# Navigate to Buscar Partida
	menu.find_match_btn.pressed.emit()
	await wait_process_frames(1)
	assert_false(home.visible, "Home hides when Buscar Partida opens")
	assert_true(browser.visible, "MatchBrowserPanel becomes visible")

	# ESC returns to Home
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	menu._unhandled_input(esc)
	await wait_process_frames(1)
	assert_true(home.visible, "Pressing ESC returns from MatchBrowserPanel to Home")
	assert_false(browser.visible, "MatchBrowserPanel hides on ESC")

	# Navigate to Configuracion & back
	menu.settings_btn.pressed.emit()
	await wait_process_frames(1)
	assert_true(settings.visible, "SettingsPanel becomes visible")
	settings.back_btn.pressed.emit()
	await wait_process_frames(1)
	assert_true(home.visible, "Back button returns from SettingsPanel to Home")

	# Navigate to Creditos & back
	menu.credits_btn.pressed.emit()
	await wait_process_frames(1)
	assert_true(credits.visible, "CreditsPanel becomes visible")
	var dev_list = credits.get_node_or_null("Center/Panel/VBox/Scroll/ContentVBox/DevelopersList")
	assert_not_null(dev_list, "CreditsPanel must include DevelopersList")
	assert_true(dev_list.get_child_count() >= 3, "CreditsPanel must render developer info cards")
	credits.back_btn.pressed.emit()
	await wait_process_frames(1)
	assert_true(home.visible, "Back button returns from CreditsPanel to Home")

func test_02_match_browser_min_5_wait_and_max_30_capacity() -> void:
	var browser = spawn_scene("res://Scenes/match_browser_panel.tscn")
	assert_not_null(browser, "MatchBrowserPanel must instantiate")
	browser.navigate_on_launch = false
	await wait_physics_frames(2)

	# Verify simplified room browser (IP/Port server connector bar removed cleanly)
	assert_true(browser.rooms_catalog.size() >= 3, "MatchBrowserPanel must list available local rooms")
	assert_null(browser.get_node_or_null("Center/Panel/VBox/BrowseView/Columns/ServerColumn/ConnectBar"), "ConnectBar (IP/Port) must be removed per simplified server flow")
	assert_null(browser.get_node_or_null("Center/Panel/VBox/BrowseView/Columns/ServerColumn/ServerHeader"), "ENCONTRAR PARTIDAS / SERVIDOR header must be removed")
	assert_not_null(browser.rooms_list, "RoomsList must remain present")
	assert_true(browser.rooms_list.get_child_count() >= 3, "RoomsList must render available rooms")

	# Enter local lobby with 1 player (auto-fill OFF to inspect <5 wait gate deterministically)
	browser.enter_local_lobby("Sala Prueba", 10, 0, false)
	await wait_process_frames(1)
	assert_true(browser.in_lobby, "Must enter Waiting Lobby view")
	assert_equal(browser.lobby_roster.size(), 1, "Starts with 1 connected human player")
	assert_equal(browser.connected_count_label.text, "CONECTADOS: 1 / 10", "Connected count label must show 1 / 10")
	assert_false(browser.can_start_match(), "Must NOT allow match start with only 1 player (< 5)")
	assert_true(browser.start_match_btn.disabled, "Start button must be disabled when < 5 connected")
	assert_true("ESPERANDO" in browser.min_status_label.text, "Status must indicate waiting for minimum 5 players")

	# Add bots 2, 3, 4 -> still waiting!
	browser.add_bot_to_lobby()
	browser.add_bot_to_lobby()
	browser.add_bot_to_lobby()
	assert_equal(browser.lobby_roster.size(), 4, "Must show 4 connected players after adding 3 bots")
	assert_false(browser.can_start_match(), "Must still wait at 4/5 players")
	assert_true(browser.start_match_btn.disabled, "Start button remains disabled at 4/5")

	# Add 5th combatant -> minimum 5 reached!
	browser.add_bot_to_lobby()
	assert_equal(browser.lobby_roster.size(), 5, "Must show 5 connected players")
	assert_true(browser.can_start_match(), "Minimum 5 reached -> can_start_match() must be true")
	assert_false(browser.start_match_btn.disabled, "Start button must unlock at >= 5 players")

	# Remove 1 bot -> drops to 4 -> locks again!
	browser.remove_bot_from_lobby()
	assert_equal(browser.lobby_roster.size(), 4, "Removing bot drops count to 4")
	assert_false(browser.can_start_match(), "Dropping below 5 re-enforces wait gate")
	assert_true(browser.start_match_btn.disabled, "Start button must re-disable below 5")

	# Modify room capacity up to 30 players and fill to 30/30
	browser.set_lobby_max_players(30)
	assert_equal(browser.lobby_max_players, 30, "Lobby max capacity must scale up to 30")
	browser.fill_lobby_with_bots()
	assert_equal(browser.lobby_roster.size(), 30, "Lobby must fill up to 30 connected combatants")
	assert_equal(browser.connected_count_label.text, "CONECTADOS: 30 / 30", "Connected readout must display 30 / 30")
	assert_true(browser.can_start_match(), "30/30 lobby must be ready to launch")

	# Lower capacity from 30 down to 12 -> excess bots trim cleanly
	browser.set_lobby_max_players(12)
	assert_equal(browser.lobby_max_players, 12, "Lobby max capacity must adjust down to 12")
	assert_equal(browser.lobby_roster.size(), 12, "Excess bots must trim cleanly to match new capacity 12")

	# Launch configured match -> GameSettings receives exact 12-player configuration
	browser.start_configured_match()
	var gs := get_node_or_null("/root/GameSettings")
	assert_not_null(gs, "GameSettings autoload must exist")
	assert_true(gs.match_configured_from_lobby, "GameSettings must record lobby launch state")
	assert_true(gs.use_prematch_countdown, "GameSettings must enable pre-match countdown on lobby launch")
	assert_equal(gs.get_effective_combatant_count(), 12, "GameSettings must store configured 12 combatants")

func test_03_arena_spawn_points_and_30_player_scaling() -> void:
	# 1. Verify WorldMap provides >= 30 wall-free spawn points
	var map = spawn_scene("res://Scenes/map.tscn")
	assert_not_null(map, "WorldMap must instantiate")
	var sm_script = load_script("res://Scripts/Core/spawn_manager.gd")
	var sm = sm_script.new()
	track_node(sm)
	add_child(sm)
	await wait_physics_frames(2)

	var spawns: Array[Vector2] = map.get_spawn_positions()
	assert_true(spawns.size() >= 30, "WorldMap must provide >= 30 unique spawn positions for 30-player matches (got %d)" % spawns.size())
	for i in range(spawns.size()):
		assert_true(sm.is_position_safe_from_walls(spawns[i], 32.0), "Spawn position %d at %s must be clear of walls" % [i, str(spawns[i])])

	# 2. Verify MainGame spawns 5 players when configured for 5
	var gs := get_node_or_null("/root/GameSettings")
	var roster5: Array[Dictionary] = [{"name": "PilotTest", "is_player": true, "is_bot": false, "ready": true}]
	for i in range(4):
		roster5.append({"name": gs.get_bot_name_for_index(i), "is_player": false, "is_bot": true, "ready": true})
	gs.configure_lobby_match(roster5, 5, "local", "Sala 5")
	gs.use_prematch_countdown = false

	var mg5 = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg5, "MainGame (5 players) must instantiate")
	await wait_physics_frames(2)
	var tanks5 = mg5.get_node_or_null("Entities/Tanks")
	assert_equal(tanks5.get_child_count(), 5, "MainGame must have exactly 5 tanks when lobby launched with 5")
	assert_equal(mg5.player_tank.tank_name, "PilotTest", "PlayerTank must adopt customized pilot name")
	assert_equal(mg5.match_manager.get_leaderboard().size(), 5, "MatchManager leaderboard must track 5 combatants")
	mg5.queue_free()
	await wait_physics_frames(2)

	# 3. Verify MainGame spawns 30 players when configured for 30
	var roster30: Array[Dictionary] = [{"name": "Pilot30", "is_player": true, "is_bot": false, "ready": true}]
	for i in range(29):
		roster30.append({"name": gs.get_bot_name_for_index(i), "is_player": false, "is_bot": true, "ready": true})
	gs.configure_lobby_match(roster30, 30, "local", "Sala 30")
	gs.use_prematch_countdown = false

	var mg30 = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg30, "MainGame (30 players) must instantiate")
	await wait_physics_frames(3)
	var tanks30 = mg30.get_node_or_null("Entities/Tanks")
	assert_equal(tanks30.get_child_count(), 30, "MainGame must scale up to 30 tanks (1 player + 29 bots)")
	var lb30: Array[Dictionary] = mg30.match_manager.get_leaderboard()
	assert_equal(lb30.size(), 30, "MatchManager leaderboard must track all 30 combatants")

	# Verify PodiumScreen handles 30 combatants cleanly without errors or excessive rows
	mg30.podium_screen.display_results(lb30)
	assert_true(mg30.podium_screen.visible, "PodiumScreen must display cleanly for 30-player match")
	var lb_table = mg30.podium_screen.get_node_or_null("Root/Panel/VBox/LeaderboardTable")
	assert_true(lb_table.get_child_count() >= 11 and lb_table.get_child_count() <= 13, "PodiumScreen LeaderboardTable must cap overflow rows cleanly for 30 players")

func test_04_prematch_gray_screen_countdown_controls_and_freeze() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	gs.clear_lobby_match()
	gs.use_prematch_countdown = true

	var mg = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg, "MainGame must instantiate")
	var overlay = mg.countdown_overlay
	assert_not_null(overlay, "MainGame must include CountdownOverlay")

	assert_equal(overlay.countdown_seconds, 15, "CountdownOverlay default must be 15 seconds")
	assert_equal(overlay.current_step_text, "15", "MainGame pre-match countdown must start at '15'")

	# Track countdown progression from 15 -> ... -> 3 -> 2 -> 1 -> ¡A JUGAR!
	var steps_seen: Array[String] = []
	overlay.countdown_step.connect(func(step_txt: String) -> void:
		steps_seen.append(step_txt)
	)

	# Restart countdown with reliable test step duration (15 steps * 0.08s = 1.20s)
	mg.start_prematch_countdown(0.08)
	assert_equal(overlay.current_step_text, "15", "Countdown must start at '15'")
	await wait_physics_frames(2)

	assert_true(mg.is_prematch_countdown_active, "Pre-match countdown must be active")
	assert_true(overlay.visible, "CountdownOverlay must be visible on gray screen")
	assert_not_null(overlay.gray_rect, "GrayScreen ColorRect must exist")
	assert_true(overlay.gray_rect.visible, "GrayScreen must be visible during countdown")
	assert_not_null(overlay.controls_card, "ControlsCard guide must exist")
	assert_true(overlay.controls_card.visible, "Movement/controls guide card must be visible during countdown")
	assert_true(overlay.controls_card.custom_minimum_size.x >= 900.0, "ControlsCard must be large (>=900px wide)")
	var card_style: StyleBoxFlat = overlay.controls_card.get_theme_stylebox("panel")
	assert_not_null(card_style, "ControlsCard must define translucent panel style")
	assert_true(card_style.bg_color.a < 0.85, "ControlsCard background must be semi-transparent (alpha: %.2f)" % card_style.bg_color.a)
	assert_not_null(overlay.controls_diagram, "Illustrated ControlsDiagramCanvas must exist")
	assert_false(mg.match_manager.is_match_active, "Match timer must NOT start until countdown finishes")

	# Verify players & bots are immobilized while countdown runs
	var player = mg.player_tank
	var bot = mg.bot1
	assert_true(player.controls_locked, "PlayerTank controls_locked must be true during countdown")
	assert_true(bot.controls_locked, "BotTank controls_locked must be true during countdown")

	var start_pos: Vector2 = player.global_position
	var bot_start_pos: Vector2 = bot.global_position
	var initial_mines: int = player.mines_count
	var initial_proj_count: int = mg.projectiles_container.get_child_count()

	Input.action_press("move_right")
	Input.action_press("shoot")
	player.shoot()
	player.throw_mine()
	await wait_physics_frames(3)
	Input.action_release("move_right")
	Input.action_release("shoot")

	assert_vector_approx(player.global_position, start_pos, 0.1, "PlayerTank must remain immobilized during 15s countdown")
	assert_vector_approx(player.velocity, Vector2.ZERO, 0.1, "PlayerTank velocity must remain zero during countdown")
	assert_vector_approx(bot.global_position, bot_start_pos, 0.1, "BotTank must remain immobilized during 15s countdown")
	assert_equal(mg.projectiles_container.get_child_count(), initial_proj_count, "Shooting must be blocked during countdown")
	assert_equal(player.mines_count, initial_mines, "Mine throwing must be blocked during countdown")

	# Wait cleanly until countdown finishes (up to 3.0s safety budget)
	for _tick in range(90):
		if not mg.is_prematch_countdown_active:
			break
		await wait_physics_frames(2)

	assert_true(steps_seen.has("15"), "Countdown must display '15' (seen: %s)" % str(steps_seen))
	assert_true(steps_seen.has("10"), "Countdown must display '10' (seen: %s)" % str(steps_seen))
	assert_true(steps_seen.has("3"), "Countdown must display '3' (seen: %s)" % str(steps_seen))
	assert_true(steps_seen.has("2"), "Countdown must display '2' (seen: %s)" % str(steps_seen))
	assert_true(steps_seen.has("1"), "Countdown must display '1' (seen: %s)" % str(steps_seen))
	assert_true(steps_seen.has("¡A JUGAR!"), "Countdown must display '¡A JUGAR!' (seen: %s)" % str(steps_seen))
	assert_false(mg.is_prematch_countdown_active, "Countdown state must clear once ¡A JUGAR! starts")
	assert_false(player.controls_locked, "PlayerTank must unlock when match begins")
	assert_false(bot.controls_locked, "BotTank must unlock when match begins")
	assert_true(mg.match_manager.is_match_active, "MatchManager must start match once countdown completes")

	# Verify player can now move & shoot after countdown
	Input.action_press("move_right")
	Input.action_press("shoot")
	await wait_physics_frames(5)
	Input.action_release("move_right")
	Input.action_release("shoot")
	assert_true(player.velocity.length() > 10.0, "PlayerTank must move freely after countdown finishes")
	assert_true(mg.projectiles_container.get_child_count() > initial_proj_count, "PlayerTank must fire normally after countdown finishes")

func test_05_audio_buses_settings_panel_and_esc_pause_menu() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	assert_not_null(gs, "GameSettings autoload must exist")
	gs.ensure_audio_buses()
	assert_true(AudioServer.get_bus_index("Master") != -1, "Master audio bus must exist")
	assert_true(AudioServer.get_bus_index("SFX") != -1, "SFX audio bus must exist")
	assert_true(AudioServer.get_bus_index("Music") != -1, "Music audio bus must exist")

	# 1. Verify SettingsPanel updates GameSettings & AudioServer buses (and no longer shows pilot name)
	var settings = spawn_scene("res://Scenes/settings_panel.tscn")
	assert_not_null(settings, "SettingsPanel must instantiate")
	await wait_physics_frames(2)

	assert_null(settings.get_node_or_null("Center/Panel/VBox/FormGrid/NameInput"), "Pilot NameInput must be removed from SettingsPanel")
	assert_null(settings.get_node_or_null("Center/Panel/VBox/FormGrid/NameLabel"), "Pilot NameLabel must be removed from SettingsPanel")

	settings.master_slider.value = 50.0
	settings.sfx_slider.value = 30.0
	settings.music_slider.value = 20.0
	gs.set_player_name("Comandante", false)
	await wait_process_frames(1)

	assert_approx_equal(gs.master_volume, 0.50, 0.02, "Master slider must update GameSettings.master_volume")
	assert_approx_equal(gs.sfx_volume, 0.30, 0.02, "SFX slider must update GameSettings.sfx_volume")
	assert_approx_equal(gs.music_volume, 0.20, 0.02, "Music slider must update GameSettings.music_volume")
	assert_approx_equal(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.30, 0.03, "SFX AudioServer bus volume must update live")

	# Verify settings save/load roundtrip with temporary config path
	var tmp_cfg := "user://test_settings_roundtrip.cfg"
	gs.save_settings(tmp_cfg)
	gs.reset_defaults(false)
	assert_equal(gs.player_name, "Player", "Reset defaults restores Player name")
	gs.load_settings(tmp_cfg)
	assert_equal(gs.player_name, "Comandante", "Loading settings restores saved player name")
	assert_approx_equal(gs.sfx_volume, 0.30, 0.02, "Loading settings restores saved SFX volume")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_cfg))

	# 2. Verify In-Game ESC PauseMenu inside MainGame
	gs.use_prematch_countdown = false
	var mg = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg, "MainGame must instantiate")
	await wait_physics_frames(2)

	var pm = mg.pause_menu
	assert_not_null(pm, "MainGame must include PauseMenu")
	pm.navigate_on_exit = false
	assert_false(pm.is_open, "PauseMenu starts closed")
	assert_false(get_tree().paused, "Tree starts unpaused")

	# Press ESC to open PauseMenu
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	pm._unhandled_input(esc)
	await wait_process_frames(1)

	assert_true(pm.is_open, "Pressing ESC must open PauseMenu")
	assert_true(pm.visible, "PauseMenu must become visible on ESC")
	assert_true(get_tree().paused, "Game tree must pause when PauseMenu opens")

	# Adjust volume inside PauseMenu while paused
	pm.master_slider.value = 70.0
	pm.sfx_slider.value = 45.0
	assert_approx_equal(gs.master_volume, 0.70, 0.02, "PauseMenu slider must adjust Master volume live")
	assert_approx_equal(gs.sfx_volume, 0.45, 0.02, "PauseMenu slider must adjust SFX volume live")

	# Press ESC again to close PauseMenu
	pm._unhandled_input(esc)
	await wait_process_frames(1)
	assert_false(pm.is_open, "Pressing ESC again must close PauseMenu")
	assert_false(get_tree().paused, "Game tree must unpause when PauseMenu closes")

	# Open and click Salir al Menu Principal -> must unpause and emit exit signal
	pm.open_menu()
	assert_true(get_tree().paused, "PauseMenu re-pauses tree")
	var exit_state := {"emitted": false}
	pm.exit_to_menu_requested.connect(func() -> void:
		exit_state["emitted"] = true
	)
	pm.menu_btn.pressed.emit()
	assert_false(get_tree().paused, "Exiting to menu must unpause tree cleanly")
	assert_true(exit_state["emitted"], "MainMenuButton must trigger exit_to_menu_requested")

func test_06_main_menu_tank_customizer_bouncy_preview_and_persistent_powerups() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	assert_not_null(gs, "GameSettings autoload must exist")

	# 1. Right-side Tank Customizer on MainMenu (Name, Color swatches, Bouncy small tank preview without music)
	var menu = spawn_scene("res://Scenes/main_menu.tscn")
	assert_not_null(menu, "MainMenu must instantiate")
	await wait_physics_frames(2)

	var name_input: LineEdit = menu.tank_name_input
	var color_grid: GridContainer = menu.color_grid
	var preview = menu.tank_preview
	assert_not_null(name_input, "MainMenu must have right-side TankNameInput")
	assert_not_null(color_grid, "MainMenu must have right-side ColorSwatchesGrid")
	assert_not_null(preview, "MainMenu must have right-side TankPreview widget")
	assert_true(menu.color_buttons.size() >= 8, "Color swatches grid must provide multiple tank colors")

	# Change tank name and verify live preview & GameSettings sync
	name_input.text = "TigerX"
	name_input.text_changed.emit("TigerX")
	await wait_process_frames(1)
	assert_equal(gs.player_name, "TigerX", "TankNameInput must update GameSettings.player_name")
	assert_equal(preview.tank_name, "TigerX", "TankPreview must display updated tank name")
	var preview_lbl: Label = preview.get_node_or_null("PreviewNameLabel")
	assert_not_null(preview_lbl, "TankPreview must show PreviewNameLabel above tank")
	assert_equal(preview_lbl.text, "TigerX", "PreviewNameLabel must show TigerX")

	# Select a distinct tank color (index 1 -> Rojo Carmesi)
	menu.select_tank_color(1)
	var expected_col: Color = gs.TANK_COLOR_PRESETS[1]["color"]
	assert_true(gs.player_color.is_equal_approx(expected_col), "Selecting color swatch must update GameSettings.player_color")
	assert_true(preview.tank_color.is_equal_approx(expected_col), "TankPreview must adopt selected tank color")

	# Verify Monster bouncy animation runs on TankPreview (squash & hop) without playing music
	var beat_period: float = 60.0 / 136.0
	preview._bounce_time = 0.085 * beat_period
	preview.step_animation(0.001)
	assert_true(preview.current_squash_scale.x > 1.10, "Preview tank must squash wider on beat impact (got %.2f)" % preview.current_squash_scale.x)
	assert_true(preview.current_squash_scale.y < 0.90, "Preview tank must compress shorter on beat impact (got %.2f)" % preview.current_squash_scale.y)

	preview._bounce_time = 0.585 * beat_period
	preview.step_animation(0.001)
	assert_true(preview.current_hop_offset_y < -10.0, "Preview tank must bounce upward mid-beat (got %.2f)" % preview.current_hop_offset_y)
	assert_null(preview.get_node_or_null("MonsterBounceMusicPlayer"), "TankPreview must NOT play or attach Monster music")

	# 2. Verify selected tank name & color carry into MainGame PlayerTank
	gs.use_prematch_countdown = false
	var mg = spawn_scene("res://Scenes/main_game.tscn")
	assert_not_null(mg, "MainGame must instantiate")
	await wait_physics_frames(2)
	assert_equal(mg.player_tank.tank_name, "TigerX", "In-game PlayerTank must use customized name")
	assert_true(mg.player_tank.chassis_visual.body_color.is_equal_approx(expected_col), "In-game PlayerTank chassis must use customized color")
	var expected_turret_col: Color = expected_col.darkened(0.18)
	assert_true(mg.player_tank.turret_visual.turret_color.is_equal_approx(expected_turret_col), "In-game PlayerTank turret dome must use customized color")
	assert_true(mg.player_tank.turret_visual.get_hatch_color().is_equal_approx(expected_turret_col.darkened(0.25)), "In-game PlayerTank turret hatch must match customized turret color (not hardcoded blue)")

	# 3. Verify PowerUps stay on the map permanently (do NOT auto-despawn) & SpawnManager replenishes
	var pu = spawn_scene("res://Scenes/powerup.tscn")
	assert_not_null(pu, "PowerUp must instantiate")
	assert_false(pu.auto_despawn, "PowerUp auto_despawn must be disabled by default")
	for _step in range(50):
		pu._process(1.0) # Simulate 50 seconds (> old 38s MAX_LIFETIME)
	assert_true(is_instance_valid(pu) and not pu.is_queued_for_deletion(), "PowerUp must remain on map even after 50s")
	assert_approx_equal(pu.modulate.a, 1.0, 0.01, "Persistent PowerUp must remain opaque without blinking out")

func test_07_spectator_freed_killer_and_lowered_event_audio() -> void:
	# 1. Verify lowered mortar bombardment & closing-zone audio levels and Music bus routing
	var SoundManagerScript = load("res://Scripts/Core/sound_manager.gd")
	assert_approx_equal(SoundManagerScript.BOMBARDMENT_BASE_DB, -10.5, 0.05, "Mortar bombardment base volume must be lowered (-10.5 dB)")
	assert_approx_equal(SoundManagerScript.ZONE_CLOSING_BASE_DB, -11.0, 0.05, "Zone closing siren base volume must be lowered (-11.0 dB)")
	SoundManagerScript._ensure_instance()
	var sm = SoundManagerScript.instance
	SoundManagerScript.play_bombardment()
	SoundManagerScript.play_zone_closing()
	assert_approx_equal(sm._bombardment_player.volume_db, -10.5, 0.1, "Active bombardment player must start at -10.5 dB")
	assert_approx_equal(sm._zone_closing_player.volume_db, -11.0, 0.1, "Active zone-closing player must start at -11.0 dB")
	if AudioServer.get_bus_index(&"Music") != -1:
		assert_equal(sm._bombardment_player.bus, &"Music", "Bombardment player must route via Music bus")
		assert_equal(sm._zone_closing_player.bus, &"Music", "Zone closing player must route via Music bus")
	SoundManagerScript.stop_bombardment()
	SoundManagerScript.stop_zone_closing()

	# 2. Regression test: Spectator Mode must never crash on <Freed Object> last_killer (MortarTarget / Mine)
	var mm_script = load("res://Scripts/Core/match_manager.gd")
	var mm = mm_script.new()
	track_node(mm)
	add_child(mm)
	var player = spawn_scene("res://Scenes/player_tank.tscn")
	var bot1 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot2 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot3 = spawn_scene("res://Scenes/bot_tank.tscn")
	var bot4 = spawn_scene("res://Scenes/bot_tank.tscn")
	bot1.tank_name = "Survivor 1"
	bot2.tank_name = "Survivor 2"
	bot3.tank_name = "Survivor 3"
	bot4.tank_name = "Survivor 4"
	player.global_position = Vector2(-1500, -1500)
	bot1.global_position = Vector2(300, 0)
	bot2.global_position = Vector2(900, 0)
	bot3.global_position = Vector2(1500, 0)
	bot4.global_position = Vector2(2100, 0)
	await wait_physics_frames(2)

	mm.register_combatant(player, "Player", true)
	mm.register_combatant(bot1, "Survivor 1", false)
	mm.register_combatant(bot2, "Survivor 2", false)
	mm.register_combatant(bot3, "Survivor 3", false)
	mm.register_combatant(bot4, "Survivor 4", false)
	mm.start_match(90.0)
	mm.start_sudden_death()

	# 2a. Player killed with freed Node2D as last_killer -> enter_spectator_mode safely ignores freed instance
	var doomed_killer := Node2D.new()
	add_child(doomed_killer)
	player.eliminate(null, false)
	player.last_killer = doomed_killer
	doomed_killer.free()
	player.is_spectating = false
	player.enter_spectator_mode()
	assert_true(player.is_spectating, "Player must safely enter Spectator Mode even if last_killer was freed")
	assert_true(is_instance_valid(player.spectated_tank), "Spectator must lock onto a valid survivor")

	# 2b. Spectated bot eliminated with freed Node2D as last_killer -> _process_spectator safely falls back
	player.set_spectate_target(bot1)
	assert_equal(player.spectated_tank, bot1, "Spectator locked onto Survivor 1")
	var doomed_spec_killer := Node2D.new()
	add_child(doomed_spec_killer)
	bot1.last_killer = doomed_spec_killer
	doomed_spec_killer.free()
	bot1.is_dead = true
	player._physics_process(0.016)
	player._process_spectator()
	assert_true(is_instance_valid(player.spectated_tank) and player.spectated_tank != bot1, "Spectator must switch away from dead Survivor 1 despite freed last_killer")

	# 2c. MortarTarget kills Survivor 2 -> queue_free'd MortarTarget must not poison last_killer or crash _process_spectator
	player.set_spectate_target(bot2)
	var MortarScript = load("res://Scripts/Entities/mortar_target.gd")
	var mortar = MortarScript.new()
	track_node(mortar)
	add_child(mortar)
	mortar.global_position = bot2.global_position
	bot2.current_health = 10.0
	mortar.detonate()
	await wait_physics_frames(2)
	assert_true(bot2.is_dead, "Mortar detonation must eliminate low-HP Survivor 2")
	assert_null(bot2.last_killer, "eliminate() must not store doomed MortarTarget in last_killer")
	player._process_spectator()
	assert_true(player.spectated_tank == bot3 or player.spectated_tank == bot4, "Spectator must advance cleanly to a remaining survivor after Mortar kill")

	# 2d. Freed spectated_tank directly -> _process_spectator must recover onto Survivor 4 without crashing
	player.set_spectate_target(bot3)
	bot3.free()
	player._process_spectator()
	player._physics_process(0.016)
	assert_equal(player.spectated_tank, bot4, "Spectator must recover onto Survivor 4 if spectated_tank itself was freed")
