# res://Scripts/UI/match_browser_panel.gd
class_name MatchBrowserPanel extends Control

## Pre-Server Match Browser, Server Connector & Local Bot Lobby (5–30 Players).
## Supports:
## - Finding pre-server / local bot rooms or attempting direct IP:Port server connection.
## - Creating a local bot match with capacity configurable from 5 to 30 players.
## - Live Waiting Room displaying connected combatants, enforcing minimum 5 to start,
##   and allowing dynamic capacity scaling up to 30 before launch.

signal closed()
signal match_launching(player_count: int, max_capacity: int)

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const MAIN_GAME_SCENE_PATH: String = "res://Scenes/main_game.tscn"

const ICON_CHECK: Texture2D = preload("res://Assets/Icons/check.svg")
const ICON_STAR: Texture2D = preload("res://Assets/Icons/star.svg")
const ICON_HOURGLASS: Texture2D = preload("res://Assets/Icons/hourglass.svg")
const ICON_ALERT: Texture2D = preload("res://Assets/Icons/alert.svg")
const ICON_BOLT: Texture2D = preload("res://Assets/Icons/bolt.svg")

const MIN_PLAYERS: int = 5
const MAX_PLAYERS: int = 30

# Sub-views
@onready var browse_view: Control = $Center/Panel/VBox/BrowseView
@onready var lobby_view: Control = $Center/Panel/VBox/LobbyView
@onready var back_to_menu_btn: Button = $Center/Panel/VBox/HeaderBar/BackToMenuButton

# BrowseView - Left (Available Rooms & Online Server Connector)
@onready var server_status_icon: TextureRect = $Center/Panel/VBox/BrowseView/Columns/ServerColumn/ServerStatusRow/ServerStatusIcon if has_node("Center/Panel/VBox/BrowseView/Columns/ServerColumn/ServerStatusRow/ServerStatusIcon") else null
@onready var server_status_label: Label = $Center/Panel/VBox/BrowseView/Columns/ServerColumn/ServerStatusRow/ServerStatusLabel if has_node("Center/Panel/VBox/BrowseView/Columns/ServerColumn/ServerStatusRow/ServerStatusLabel") else $Center/Panel/VBox/BrowseView/Columns/ServerColumn/ServerStatusLabel
@onready var server_url_input: LineEdit = $Center/Panel/VBox/BrowseView/Columns/ServerColumn/OnlineServerBox/OnlineVBox/ServerUrlRow/ServerUrlInput if has_node("Center/Panel/VBox/BrowseView/Columns/ServerColumn/OnlineServerBox/OnlineVBox/ServerUrlRow/ServerUrlInput") else null
@onready var connect_server_btn: Button = $Center/Panel/VBox/BrowseView/Columns/ServerColumn/OnlineServerBox/OnlineVBox/ServerUrlRow/ConnectServerButton if has_node("Center/Panel/VBox/BrowseView/Columns/ServerColumn/OnlineServerBox/OnlineVBox/ServerUrlRow/ConnectServerButton") else null
@onready var rooms_list: VBoxContainer = $Center/Panel/VBox/BrowseView/Columns/ServerColumn/RoomsScroll/RoomsList

# BrowseView - Right (Create Local Bot Match)
@onready var room_name_input: LineEdit = $Center/Panel/VBox/BrowseView/Columns/CreateColumn/RoomNameInput
@onready var create_cap_slider: HSlider = $Center/Panel/VBox/BrowseView/Columns/CreateColumn/CapRow/CreateCapSlider
@onready var create_cap_spin: SpinBox = $Center/Panel/VBox/BrowseView/Columns/CreateColumn/CapRow/CreateCapSpin
@onready var create_cap_info: Label = $Center/Panel/VBox/BrowseView/Columns/CreateColumn/CreateCapInfo
@onready var create_autofill_check: CheckBox = $Center/Panel/VBox/BrowseView/Columns/CreateColumn/CreateAutoFillCheck
@onready var create_local_btn: Button = $Center/Panel/VBox/BrowseView/Columns/CreateColumn/CreateLocalButton

# LobbyView (Waiting Room)
@onready var lobby_title_label: Label = $Center/Panel/VBox/LobbyView/LobbyTop/LobbyTitle
@onready var lobby_mode_label: Label = $Center/Panel/VBox/LobbyView/LobbyTop/LobbyModeBadge
@onready var connected_count_label: Label = $Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/TopStatusRow/ConnectedCountLabel
@onready var min_status_icon: TextureRect = $Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/TopStatusRow/MinStatusIcon if has_node("Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/TopStatusRow/MinStatusIcon") else null
@onready var min_status_label: Label = $Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/TopStatusRow/MinStatusLabel
@onready var min_progress_bar: ProgressBar = $Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/MinProgressBar
@onready var lobby_cap_slider: HSlider = $Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/CapEditRow/LobbyCapSlider
@onready var lobby_cap_spin: SpinBox = $Center/Panel/VBox/LobbyView/StatusCard/StatusVBox/CapEditRow/LobbyCapSpin
@onready var roster_list: VBoxContainer = $Center/Panel/VBox/LobbyView/RosterScroll/RosterList
@onready var add_bot_btn: Button = $Center/Panel/VBox/LobbyView/BotControlsRow/AddBotButton
@onready var remove_bot_btn: Button = $Center/Panel/VBox/LobbyView/BotControlsRow/RemoveBotButton
@onready var fill_room_btn: Button = $Center/Panel/VBox/LobbyView/BotControlsRow/FillRoomButton
@onready var lobby_autofill_check: CheckBox = $Center/Panel/VBox/LobbyView/BotControlsRow/LobbyAutoFillCheck
@onready var auto_start_check: CheckBox = $Center/Panel/VBox/LobbyView/BotControlsRow/AutoStartCheck
@onready var leave_lobby_btn: Button = $Center/Panel/VBox/LobbyView/LobbyFooter/LeaveLobbyButton
@onready var start_match_btn: Button = $Center/Panel/VBox/LobbyView/LobbyFooter/StartMatchButton

var rooms_catalog: Array[Dictionary] = []
var lobby_roster: Array[Dictionary] = []
var lobby_max_players: int = 10
var lobby_room_name: String = "Arena Local TANK.IO"
var lobby_mode: String = "local"
var in_lobby: bool = false
var navigate_on_launch: bool = true

var _syncing_cap: bool = false
var _syncing_network_ui: bool = false
var _bot_join_timer: float = 0.0
var _auto_start_delay: float = -1.0
var _bot_join_interval: float = 0.45
var _online_match_in_progress: bool = false
var _online_leader_peer_id: int = 0
var network_manager_override: Node = null

func _ready() -> void:
	_init_default_rooms()
	_sync_initial_server_url()
	_connect_signals()
	_connect_network_signals()
	show_browse_view()

func _process(delta: float) -> void:
	if not visible or not in_lobby:
		return
	if lobby_mode == "server":
		return

	if lobby_autofill_check != null and lobby_autofill_check.button_pressed:
		if lobby_roster.size() < lobby_max_players:
			_bot_join_timer += delta
			if _bot_join_timer >= _bot_join_interval:
				_bot_join_timer = 0.0
				add_bot_to_lobby()
	else:
		_bot_join_timer = 0.0

	if _auto_start_delay >= 0.0:
		if not can_start_match():
			_auto_start_delay = -1.0
		else:
			_auto_start_delay -= delta
			if _auto_start_delay <= 0.0:
				_auto_start_delay = -1.0
				start_configured_match()

func _connect_signals() -> void:
	if back_to_menu_btn != null:
		back_to_menu_btn.pressed.connect(_on_back_to_menu_pressed)
	if connect_server_btn != null:
		connect_server_btn.pressed.connect(_on_connect_server_pressed)
	if server_url_input != null:
		server_url_input.text_submitted.connect(_on_server_url_submitted)
	if create_cap_slider != null:
		create_cap_slider.value_changed.connect(_on_create_cap_changed)
	if create_cap_spin != null:
		create_cap_spin.value_changed.connect(_on_create_cap_changed)
	if create_local_btn != null:
		create_local_btn.pressed.connect(_on_create_local_pressed)

	if lobby_cap_slider != null:
		lobby_cap_slider.value_changed.connect(_on_lobby_cap_changed)
	if lobby_cap_spin != null:
		lobby_cap_spin.value_changed.connect(_on_lobby_cap_changed)
	if add_bot_btn != null:
		add_bot_btn.pressed.connect(_on_add_bot_pressed)
	if remove_bot_btn != null:
		remove_bot_btn.pressed.connect(_on_remove_bot_pressed)
	if fill_room_btn != null:
		fill_room_btn.pressed.connect(_on_fill_room_pressed)
	if lobby_autofill_check != null:
		lobby_autofill_check.toggled.connect(_on_lobby_autofill_toggled)
	if leave_lobby_btn != null:
		leave_lobby_btn.pressed.connect(_on_leave_lobby_pressed)
	if start_match_btn != null:
		start_match_btn.pressed.connect(_on_start_match_pressed)

func _get_network_manager() -> Node:
	if network_manager_override != null and is_instance_valid(network_manager_override):
		return network_manager_override
	return get_node_or_null("/root/NetworkManager")

func _sync_initial_server_url() -> void:
	if server_url_input == null:
		return
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("get_initial_server_url"):
		server_url_input.text = str(gs.get_initial_server_url())
	elif gs != null and "server_url" in gs:
		server_url_input.text = str(gs.get("server_url"))

func _connect_network_signals() -> void:
	var nm := _get_network_manager()
	if nm == null:
		return
	if nm.has_signal("connection_state_changed") and not nm.connection_state_changed.is_connected(_on_network_connection_state_changed):
		nm.connection_state_changed.connect(_on_network_connection_state_changed)
	if nm.has_signal("lobby_state_updated") and not nm.lobby_state_updated.is_connected(_on_network_lobby_state_updated):
		nm.lobby_state_updated.connect(_on_network_lobby_state_updated)
	if nm.has_signal("match_launch_requested") and not nm.match_launch_requested.is_connected(_on_network_match_launch_requested):
		nm.match_launch_requested.connect(_on_network_match_launch_requested)
	if nm.has_signal("server_error") and not nm.server_error.is_connected(_on_network_server_error):
		nm.server_error.connect(_on_network_server_error)

func _init_default_rooms() -> void:
	rooms_catalog = [
		{
			"name": "Arena Táctica #1 (Bots)",
			"type": "Local / Bots",
			"mode": "local",
			"initial_bots": 2,
			"max_players": 10,
			"min_players": MIN_PLAYERS,
			"online": true,
			"status": "Esperando jugadores (mín. 5)"
		},
		{
			"name": "Batalla Campal Masiva (30 Max)",
			"type": "Local / Bots",
			"mode": "local",
			"initial_bots": 3,
			"max_players": 30,
			"min_players": MIN_PLAYERS,
			"online": true,
			"status": "Esperando jugadores (mín. 5)"
		},
		{
			"name": "Sala Rápida (Mínimo 5)",
			"type": "Local / Bots",
			"mode": "local",
			"initial_bots": 4,
			"max_players": 5,
			"min_players": MIN_PLAYERS,
			"online": true,
			"status": "Casi lista (4/5)"
		}
	]

func show_browse_view() -> void:
	in_lobby = false
	_auto_start_delay = -1.0
	_online_match_in_progress = false
	_online_leader_peer_id = 0
	lobby_mode = "local"
	var nm := _get_network_manager()
	if nm != null and nm.get("role") == "client" and nm.has_method("disconnect_network"):
		nm.disconnect_network()
	if browse_view != null:
		browse_view.visible = true
	if lobby_view != null:
		lobby_view.visible = false
	_update_connect_button_ui(false)
	_populate_rooms_list()
	_update_create_cap_ui(int(create_cap_spin.value) if create_cap_spin != null else 10)

func show_lobby_view() -> void:
	in_lobby = true
	if browse_view != null:
		browse_view.visible = false
	if lobby_view != null:
		lobby_view.visible = true
	_refresh_lobby_ui()

func _populate_rooms_list() -> void:
	if rooms_list == null:
		return
	for child in rooms_list.get_children():
		child.queue_free()

	for i in range(rooms_catalog.size()):
		var room: Dictionary = rooms_catalog[i]
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		var is_online: bool = room.get("online", true) == true
		sb.bg_color = Color(0.10, 0.14, 0.20, 0.92) if is_online else Color(0.12, 0.11, 0.14, 0.78)
		sb.border_width_left = 3
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.28, 0.78, 0.96, 0.75) if is_online else Color(0.55, 0.35, 0.35, 0.65)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		sb.content_margin_left = 12
		sb.content_margin_top = 8
		sb.content_margin_right = 12
		sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", sb)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 2)

		var title_lbl := Label.new()
		title_lbl.text = "%s   [%s]" % [str(room.get("name", "Sala")), str(room.get("type", "Local"))]
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0) if is_online else Color(0.72, 0.72, 0.78, 0.9))
		title_lbl.add_theme_font_size_override("font_size", 14)
		info_vbox.add_child(title_lbl)

		var cur_p: int = int(room.get("initial_bots", 0))
		var max_p: int = int(room.get("max_players", 10))
		var min_p: int = int(room.get("min_players", MIN_PLAYERS))
		var sub_lbl := Label.new()
		sub_lbl.text = "Conectados: %d/%d  •  Mínimo: %d  •  %s" % [cur_p, max_p, min_p, str(room.get("status", ""))]
		sub_lbl.add_theme_color_override("font_color", Color(0.68, 0.84, 0.96, 0.92) if is_online else Color(0.88, 0.55, 0.52, 0.9))
		sub_lbl.add_theme_font_size_override("font_size", 12)
		info_vbox.add_child(sub_lbl)

		hbox.add_child(info_vbox)

		var join_btn := Button.new()
		join_btn.custom_minimum_size = Vector2(96, 34)
		join_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		join_btn.text = "UNIRSE" if is_online else "PROBAR"
		join_btn.pressed.connect(join_room_by_index.bind(i))
		hbox.add_child(join_btn)

		card.add_child(hbox)
		rooms_list.add_child(card)

func join_room_by_index(index: int) -> void:
	if index < 0 or index >= rooms_catalog.size():
		return
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	var room: Dictionary = rooms_catalog[index]
	if room.get("online", true) != true:
		_set_server_status("Servidor dedicado aún no iniciado (Fase Pre-Servidor). Usa una Sala Local con Bots o crea la tuya.", Color(1.0, 0.68, 0.28, 1.0), ICON_ALERT)
		return

	var r_name: String = str(room.get("name", "Arena Local"))
	var max_p: int = clampi(int(room.get("max_players", 10)), MIN_PLAYERS, MAX_PLAYERS)
	var init_bots: int = clampi(int(room.get("initial_bots", 0)), 0, max_p - 1)
	enter_local_lobby(r_name, max_p, init_bots, true)

func enter_local_lobby(room_name_val: String, max_cap: int, initial_bots: int = 0, autofill: bool = true) -> void:
	var nm := _get_network_manager()
	if nm != null and nm.get("role") == "client" and nm.has_method("disconnect_network"):
		nm.disconnect_network()
	lobby_room_name = room_name_val.strip_edges()
	if lobby_room_name.is_empty():
		lobby_room_name = "Arena Local TANK.IO"
	lobby_mode = "local"
	lobby_max_players = clampi(max_cap, MIN_PLAYERS, MAX_PLAYERS)
	_bot_join_timer = 0.0
	_auto_start_delay = -1.0

	var gs := get_node_or_null("/root/GameSettings")
	var p_name: String = str(gs.get("player_name")) if gs != null else "Player"
	if p_name.strip_edges().is_empty():
		p_name = "Player"

	lobby_roster.clear()
	lobby_roster.append({
		"name": p_name,
		"is_player": true,
		"is_bot": false,
		"ready": true
	})

	var bots_to_add: int = clampi(initial_bots, 0, lobby_max_players - 1)
	for i in range(bots_to_add):
		add_bot_to_lobby(false)

	if lobby_autofill_check != null:
		lobby_autofill_check.button_pressed = autofill

	show_lobby_view()

func add_bot_to_lobby(refresh_ui: bool = true) -> bool:
	if lobby_roster.size() >= lobby_max_players:
		return false
	var bot_idx: int = maxi(0, lobby_roster.size() - 1)
	var gs := get_node_or_null("/root/GameSettings")
	var bot_name: String = gs.get_bot_name_for_index(bot_idx) if (gs != null and gs.has_method("get_bot_name_for_index")) else ("Bot #%d" % (bot_idx + 1))
	lobby_roster.append({
		"name": bot_name,
		"is_player": false,
		"is_bot": true,
		"ready": true
	})
	if refresh_ui:
		_refresh_lobby_ui()
		_check_auto_start()
	return true

func remove_bot_from_lobby() -> bool:
	for i in range(lobby_roster.size() - 1, -1, -1):
		if lobby_roster[i].get("is_bot", false) == true:
			lobby_roster.remove_at(i)
			_auto_start_delay = -1.0
			_refresh_lobby_ui()
			return true
	return false

func fill_lobby_with_bots() -> void:
	while lobby_roster.size() < lobby_max_players:
		if not add_bot_to_lobby(false):
			break
	_refresh_lobby_ui()
	_check_auto_start()

func set_lobby_max_players(new_max: int) -> void:
	lobby_max_players = clampi(new_max, MIN_PLAYERS, MAX_PLAYERS)
	while lobby_roster.size() > lobby_max_players:
		var removed := false
		for i in range(lobby_roster.size() - 1, -1, -1):
			if lobby_roster[i].get("is_bot", false) == true:
				lobby_roster.remove_at(i)
				removed = true
				break
		if not removed:
			break
	_refresh_lobby_ui()
	_check_auto_start()

func can_start_match() -> bool:
	return lobby_roster.size() >= MIN_PLAYERS

func _check_auto_start() -> void:
	if auto_start_check != null and auto_start_check.button_pressed:
		if can_start_match() and lobby_roster.size() >= lobby_max_players and _auto_start_delay < 0.0:
			_auto_start_delay = 1.2

func _is_server_leader() -> bool:
	if lobby_mode != "server":
		return true
	var nm := _get_network_manager()
	return nm != null and nm.has_method("is_local_leader") and nm.is_local_leader()

func _count_bots_in_roster() -> int:
	var n := 0
	for entry in lobby_roster:
		if entry.get("is_bot", false) == true:
			n += 1
	return n

func _set_server_status(msg: String, col: Color, icon_tex: Texture2D = null) -> void:
	if server_status_label != null:
		server_status_label.text = msg
		server_status_label.add_theme_color_override("font_color", col)
	if server_status_icon != null:
		server_status_icon.texture = icon_tex
		server_status_icon.modulate = col
		server_status_icon.visible = (icon_tex != null)

func _make_roster_icon(tex: Texture2D, col: Color, icon_size: float = 15.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = tex
	icon.modulate = col
	return icon

func _refresh_lobby_ui() -> void:
	var count: int = lobby_roster.size()
	var is_server_mode: bool = (lobby_mode == "server")
	var is_leader: bool = _is_server_leader()
	var controls_enabled: bool = (not is_server_mode) or (is_leader and not _online_match_in_progress)

	if lobby_title_label != null:
		lobby_title_label.text = lobby_room_name
	if lobby_mode_label != null:
		if is_server_mode:
			lobby_mode_label.text = "MODO: SERVIDOR ONLINE (WSS/WS) • ERES LÍDER" if is_leader else "MODO: SERVIDOR ONLINE (WSS/WS) • ESPERANDO AL LÍDER"
		else:
			lobby_mode_label.text = "MODO: LOCAL CON BOTS (PRE-SERVIDOR)"

	if connected_count_label != null:
		connected_count_label.text = "CONECTADOS: %d / %d" % [count, lobby_max_players]

	if min_progress_bar != null:
		min_progress_bar.max_value = MIN_PLAYERS
		min_progress_bar.value = mini(count, MIN_PLAYERS)

	var ready_to_start: bool = can_start_match()
	if min_status_label != null:
		if is_server_mode and _online_match_in_progress:
			min_status_label.text = "PARTIDA EN CURSO EN EL SERVIDOR (ESPERANDO SIGUIENTE RONDA)"
			min_status_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0, 1.0))
			if min_status_icon != null:
				min_status_icon.texture = ICON_BOLT
				min_status_icon.modulate = Color(0.45, 0.85, 1.0, 1.0)
				min_status_icon.visible = true
		elif ready_to_start:
			min_status_label.text = "MÍNIMO ALCANZADO (%d/%d mín.) • LISTO PARA INICIAR" % [count, MIN_PLAYERS]
			min_status_label.add_theme_color_override("font_color", Color(0.32, 0.96, 0.52, 1.0))
			if min_status_icon != null:
				min_status_icon.texture = ICON_CHECK
				min_status_icon.modulate = Color(0.32, 0.96, 0.52, 1.0)
				min_status_icon.visible = true
		else:
			var missing: int = MIN_PLAYERS - count
			min_status_label.text = "ESPERANDO JUGADORES... (%d/%d mínimo, faltan %d)" % [count, MIN_PLAYERS, missing]
			min_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 1.0))
			if min_status_icon != null:
				min_status_icon.texture = ICON_HOURGLASS
				min_status_icon.modulate = Color(1.0, 0.78, 0.28, 1.0)
				min_status_icon.visible = true

	_syncing_cap = true
	if lobby_cap_slider != null:
		lobby_cap_slider.min_value = MIN_PLAYERS
		lobby_cap_slider.max_value = MAX_PLAYERS
		lobby_cap_slider.value = lobby_max_players
		lobby_cap_slider.editable = controls_enabled
	if lobby_cap_spin != null:
		lobby_cap_spin.min_value = MIN_PLAYERS
		lobby_cap_spin.max_value = MAX_PLAYERS
		lobby_cap_spin.value = lobby_max_players
		lobby_cap_spin.editable = controls_enabled
	_syncing_cap = false

	if lobby_autofill_check != null:
		lobby_autofill_check.disabled = not controls_enabled
	if auto_start_check != null:
		auto_start_check.visible = not is_server_mode

	if start_match_btn != null:
		start_match_btn.add_theme_constant_override("icon_max_width", 18)
		if is_server_mode and _online_match_in_progress:
			start_match_btn.disabled = true
			start_match_btn.text = "PARTIDA EN CURSO..."
			start_match_btn.icon = ICON_BOLT
			start_match_btn.add_theme_color_override("icon_disabled_color", Color(0.45, 0.85, 1.0, 0.85))
		elif is_server_mode and not is_leader:
			start_match_btn.disabled = true
			start_match_btn.text = "ESPERANDO AL LÍDER (%d/%d)" % [count, lobby_max_players]
			start_match_btn.icon = ICON_HOURGLASS
			start_match_btn.add_theme_color_override("icon_disabled_color", Color(1.0, 0.84, 0.35, 0.85))
		else:
			start_match_btn.disabled = not ready_to_start
			start_match_btn.text = "¡INICIAR PARTIDA! (%d/%d)" % [count, lobby_max_players] if ready_to_start else "ESPERANDO MÍN. %d (%d/%d)" % [MIN_PLAYERS, count, MIN_PLAYERS]
			start_match_btn.icon = ICON_CHECK if ready_to_start else ICON_HOURGLASS
			var btn_icon_col := Color(0.4, 1.0, 0.62, 1.0) if ready_to_start else Color(1.0, 0.82, 0.35, 0.85)
			start_match_btn.add_theme_color_override("icon_normal_color", btn_icon_col)
			start_match_btn.add_theme_color_override("icon_hover_color", Color.WHITE)
			start_match_btn.add_theme_color_override("icon_pressed_color", Color.WHITE)
			start_match_btn.add_theme_color_override("icon_disabled_color", btn_icon_col)

	if add_bot_btn != null:
		add_bot_btn.disabled = (not controls_enabled) or (count >= lobby_max_players)
	if remove_bot_btn != null:
		remove_bot_btn.disabled = (not controls_enabled) or (_count_bots_in_roster() <= 0)
	if fill_room_btn != null:
		fill_room_btn.disabled = (not controls_enabled) or (count >= lobby_max_players)

	_rebuild_roster_list()

func _rebuild_roster_list() -> void:
	if roster_list == null:
		return
	for child in roster_list.get_children():
		child.queue_free()

	var is_server_mode: bool = (lobby_mode == "server")
	for i in range(lobby_roster.size()):
		var entry: Dictionary = lobby_roster[i]
		var is_p: bool = entry.get("is_player", false) == true
		var is_bot: bool = entry.get("is_bot", false) == true
		var is_leader: bool = entry.get("is_leader", false) == true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var num_lbl := Label.new()
		num_lbl.custom_minimum_size = Vector2(38, 0)
		num_lbl.text = "#%d" % (i + 1)
		num_lbl.add_theme_font_size_override("font_size", 13)
		num_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0) if (is_p or is_leader) else Color(0.65, 0.75, 0.88, 1.0))

		var icon_tex: Texture2D = ICON_BOLT
		var icon_col := Color(0.55, 0.78, 0.9, 0.85)
		if is_server_mode and not is_bot and is_leader:
			icon_tex = ICON_STAR
			icon_col = Color(1.0, 0.86, 0.25, 1.0)
		elif not is_bot:
			icon_tex = ICON_CHECK
			icon_col = Color(0.35, 0.95, 0.55, 1.0)
		var role_icon := _make_roster_icon(icon_tex, icon_col, 15.0)

		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var base_name := str(entry.get("name", "Bot" if is_bot else "Player"))
		if is_p:
			name_lbl.text = "%s (TÚ)" % base_name
		else:
			name_lbl.text = base_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0, 1.0) if is_p else (Color(0.95, 0.92, 0.72, 1.0) if is_leader else Color(0.9, 0.93, 0.98, 1.0)))

		var role_lbl := Label.new()
		if is_server_mode:
			if is_p:
				role_lbl.text = "JUGADOR ONLINE • LÍDER" if is_leader else "JUGADOR ONLINE • LISTO"
			elif not is_bot:
				role_lbl.text = "COMPAÑERO ONLINE • LÍDER" if is_leader else "COMPAÑERO ONLINE • LISTO"
			else:
				role_lbl.text = "BOT IA (SERVIDOR)"
		else:
			role_lbl.text = "JUGADOR LOCAL • LISTO" if is_p else "BOT IA • CONECTADO"
		role_lbl.add_theme_font_size_override("font_size", 12)
		role_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55, 1.0) if not is_bot else Color(0.65, 0.82, 0.72, 0.92))

		row.add_child(num_lbl)
		row.add_child(role_icon)
		row.add_child(name_lbl)
		row.add_child(role_lbl)
		roster_list.add_child(row)

func start_configured_match() -> void:
	if not can_start_match():
		return
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if lobby_mode == "server":
		var nm := _get_network_manager()
		if nm != null and nm.has_method("request_start_match"):
			nm.request_start_match()
		return
	_launch_match_scene(lobby_roster, lobby_max_players, lobby_mode, lobby_room_name)

func _launch_match_scene(roster_data: Array, max_cap: int, mode: String, r_name: String) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("configure_lobby_match"):
		gs.configure_lobby_match(roster_data, max_cap, mode, r_name)
	match_launching.emit(roster_data.size(), max_cap)
	if navigate_on_launch and get_tree() != null and ResourceLoader.exists(MAIN_GAME_SCENE_PATH):
		get_tree().change_scene_to_file(MAIN_GAME_SCENE_PATH)

func _update_connect_button_ui(is_connecting: bool) -> void:
	if connect_server_btn != null:
		connect_server_btn.disabled = is_connecting
		connect_server_btn.text = "CONECTANDO..." if is_connecting else "CONECTAR"

func _start_online_connection(raw_url: String) -> void:
	var nm := _get_network_manager()
	if nm == null:
		_set_server_status("NetworkManager no disponible.", Color(1.0, 0.45, 0.35, 1.0), ICON_ALERT)
		return

	var gs := get_node_or_null("/root/GameSettings")
	var p_name := str(gs.get("player_name")) if gs != null else "Player"
	var p_color: Color = gs.get("player_color") if (gs != null and gs.get("player_color") is Color) else Color(0.2, 0.45, 0.75, 1.0)
	if gs != null and gs.has_method("set_server_url"):
		gs.set_server_url(raw_url, true)

	_update_connect_button_ui(true)
	nm.connect_to_server(raw_url, p_name, p_color)

func _on_connect_server_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	var url := server_url_input.text if server_url_input != null else "ws://127.0.0.1:7777"
	_start_online_connection(url)

func _on_server_url_submitted(submitted_text: String) -> void:
	_start_online_connection(submitted_text)

func _on_network_connection_state_changed(state: String, detail: String) -> void:
	_update_connect_button_ui(state == "connecting")
	if state == "connecting":
		_set_server_status("%s" % detail, Color(0.45, 0.9, 1.0, 1.0), ICON_HOURGLASS)
	elif state == "error" or state == "offline":
		if in_lobby and lobby_mode == "server":
			lobby_mode = "local"
			show_browse_view()
		if state == "error" and not detail.is_empty():
			_set_server_status(detail, Color(1.0, 0.55, 0.32, 1.0), ICON_ALERT)
		elif server_status_icon != null:
			server_status_icon.visible = false

func _on_network_server_error(message: String) -> void:
	_update_connect_button_ui(false)
	_set_server_status(message, Color(1.0, 0.52, 0.30, 1.0), ICON_ALERT)

func _on_network_lobby_state_updated(r_name: String, max_cap: int, roster: Array, leader_id: int, autofill: bool, in_prog: bool) -> void:
	lobby_mode = "server"
	lobby_room_name = r_name
	lobby_max_players = clampi(max_cap, MIN_PLAYERS, MAX_PLAYERS)
	_online_leader_peer_id = leader_id
	_online_match_in_progress = in_prog
	_auto_start_delay = -1.0

	lobby_roster.clear()
	for item in roster:
		if item is Dictionary:
			lobby_roster.append((item as Dictionary).duplicate(true))

	_syncing_network_ui = true
	if lobby_autofill_check != null:
		lobby_autofill_check.button_pressed = autofill
	_syncing_network_ui = false

	if not in_lobby:
		show_lobby_view()
	else:
		_refresh_lobby_ui()

func _on_network_match_launch_requested(r_name: String, max_cap: int, roster: Array) -> void:
	_launch_match_scene(roster, max_cap, "server", r_name)

func _on_create_cap_changed(val: float) -> void:
	if _syncing_cap:
		return
	_update_create_cap_ui(clampi(int(roundf(val)), MIN_PLAYERS, MAX_PLAYERS))

func _update_create_cap_ui(cap: int) -> void:
	_syncing_cap = true
	if create_cap_slider != null:
		create_cap_slider.value = cap
	if create_cap_spin != null:
		create_cap_spin.value = cap
	if create_cap_info != null:
		create_cap_info.text = "Capacidad: %d jugadores (1 Tú + %d Bots) • Mínimo para iniciar: %d" % [cap, cap - 1, MIN_PLAYERS]
	_syncing_cap = false

func _on_create_local_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	var r_name: String = room_name_input.text if room_name_input != null else "Arena Local TANK.IO"
	var cap: int = int(create_cap_spin.value) if create_cap_spin != null else 10
	var autofill: bool = create_autofill_check.button_pressed if create_autofill_check != null else true
	enter_local_lobby(r_name, cap, 0, autofill)

func _on_lobby_cap_changed(val: float) -> void:
	if _syncing_cap:
		return
	var target_cap := clampi(int(roundf(val)), MIN_PLAYERS, MAX_PLAYERS)
	if lobby_mode == "server":
		var nm := _get_network_manager()
		if nm != null and nm.has_method("request_set_capacity"):
			nm.request_set_capacity(target_cap)
		return
	set_lobby_max_players(target_cap)

func _on_lobby_autofill_toggled(toggled_on: bool) -> void:
	if _syncing_network_ui:
		return
	if lobby_mode == "server":
		var nm := _get_network_manager()
		if nm != null and nm.has_method("request_set_autofill"):
			nm.request_set_autofill(toggled_on)

func _on_add_bot_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if lobby_mode == "server":
		var nm := _get_network_manager()
		if nm != null and nm.has_method("request_add_bot"):
			nm.request_add_bot()
		return
	add_bot_to_lobby(true)

func _on_remove_bot_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if lobby_mode == "server":
		var nm := _get_network_manager()
		if nm != null and nm.has_method("request_remove_bot"):
			nm.request_remove_bot()
		return
	remove_bot_from_lobby()

func _on_fill_room_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if lobby_mode == "server":
		var nm := _get_network_manager()
		if nm != null and nm.has_method("request_fill_bots"):
			nm.request_fill_bots()
		return
	fill_lobby_with_bots()

func _on_leave_lobby_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	show_browse_view()

func _on_start_match_pressed() -> void:
	start_configured_match()

func _on_back_to_menu_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	show_browse_view()
	closed.emit()
