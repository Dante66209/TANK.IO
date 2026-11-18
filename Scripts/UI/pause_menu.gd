# res://Scripts/UI/pause_menu.gd
class_name PauseMenu extends CanvasLayer

## In-Game ESC Pause & Options Menu.
## Allows live adjustment of Master, SFX, and Music volumes,
## returning to Main Menu, or exiting the game.

signal menu_opened()
signal menu_closed()
signal exit_to_menu_requested()

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const MAIN_MENU_SCENE_PATH: String = "res://Scenes/main_menu.tscn"

@onready var root: Control = $Root
@onready var master_slider: HSlider = $Root/Center/Panel/VBox/VolumeGrid/MasterSlider
@onready var master_value_label: Label = $Root/Center/Panel/VBox/VolumeGrid/MasterValue
@onready var master_mute_btn: CheckBox = $Root/Center/Panel/VBox/VolumeGrid/MasterMute
@onready var sfx_slider: HSlider = $Root/Center/Panel/VBox/VolumeGrid/SFXSlider
@onready var sfx_value_label: Label = $Root/Center/Panel/VBox/VolumeGrid/SFXValue
@onready var sfx_mute_btn: CheckBox = $Root/Center/Panel/VBox/VolumeGrid/SFXMute
@onready var music_slider: HSlider = $Root/Center/Panel/VBox/VolumeGrid/MusicSlider
@onready var music_value_label: Label = $Root/Center/Panel/VBox/VolumeGrid/MusicValue
@onready var music_mute_btn: CheckBox = $Root/Center/Panel/VBox/VolumeGrid/MusicMute
@onready var test_sfx_btn: Button = $Root/Center/Panel/VBox/TestSFXButton
@onready var resume_btn: Button = $Root/Center/Panel/VBox/ButtonsVBox/ResumeButton
@onready var menu_btn: Button = $Root/Center/Panel/VBox/ButtonsVBox/MainMenuButton
@onready var quit_btn: Button = $Root/Center/Panel/VBox/ButtonsVBox/QuitButton

var is_open: bool = false
var navigate_on_exit: bool = true
var _syncing_ui: bool = false

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	visible = false
	if quit_btn != null and OS.has_feature("web"):
		quit_btn.visible = false
	_connect_ui()
	_sync_from_settings()

func _exit_tree() -> void:
	if is_open and get_tree() != null:
		get_tree().paused = false

func _connect_ui() -> void:
	if master_slider != null:
		master_slider.value_changed.connect(_on_master_slider_changed)
	if master_mute_btn != null:
		master_mute_btn.toggled.connect(_on_master_mute_toggled)
	if sfx_slider != null:
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	if sfx_mute_btn != null:
		sfx_mute_btn.toggled.connect(_on_sfx_mute_toggled)
	if music_slider != null:
		music_slider.value_changed.connect(_on_music_slider_changed)
	if music_mute_btn != null:
		music_mute_btn.toggled.connect(_on_music_mute_toggled)
	if test_sfx_btn != null:
		test_sfx_btn.pressed.connect(_on_test_sfx_pressed)
	if resume_btn != null:
		resume_btn.pressed.connect(_on_resume_pressed)
	if menu_btn != null:
		menu_btn.pressed.connect(_on_main_menu_pressed)
	if quit_btn != null:
		quit_btn.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			var code: int = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if code == KEY_ESCAPE:
				toggle_menu()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()

func toggle_menu() -> void:
	if is_open:
		close_menu()
	else:
		open_menu()

func _is_online_match() -> bool:
	var gs := _get_settings()
	var nm := get_node_or_null("/root/NetworkManager")
	return gs != null and gs.get("lobby_mode") == "server" and nm != null and nm.has_method("is_online") and nm.is_online()

func open_menu() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_sync_from_settings()
	_release_player_inputs()
	if get_tree() != null and not _is_online_match():
		get_tree().paused = true
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if resume_btn != null:
		resume_btn.grab_focus()
	menu_opened.emit()

func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if get_tree() != null:
		get_tree().paused = false
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	menu_closed.emit()

func _release_player_inputs() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "shoot", "dash", "throw_mine"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)
	if get_tree() != null:
		for p in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(p):
				if p.has_method("set_chassis_input"):
					p.set_chassis_input(Vector2.ZERO)
				if p.has_method("set_dash_input"):
					p.set_dash_input(false)

func _get_settings() -> Node:
	if has_node("/root/GameSettings"):
		return get_node("/root/GameSettings")
	return null

func _sync_from_settings() -> void:
	_syncing_ui = true
	var gs := _get_settings()
	var m_vol: float = float(gs.get("master_volume")) if gs != null else _get_bus_linear("Master")
	var s_vol: float = float(gs.get("sfx_volume")) if gs != null else _get_bus_linear("SFX")
	var mu_vol: float = float(gs.get("music_volume")) if gs != null else _get_bus_linear("Music")
	var m_mute: bool = bool(gs.get("master_muted")) if gs != null else _is_bus_muted("Master")
	var s_mute: bool = bool(gs.get("sfx_muted")) if gs != null else _is_bus_muted("SFX")
	var mu_mute: bool = bool(gs.get("music_muted")) if gs != null else _is_bus_muted("Music")

	if master_slider != null:
		master_slider.value = roundf(m_vol * 100.0)
	if master_value_label != null:
		master_value_label.text = "%d%%" % int(roundf(m_vol * 100.0))
	if master_mute_btn != null:
		master_mute_btn.button_pressed = m_mute

	if sfx_slider != null:
		sfx_slider.value = roundf(s_vol * 100.0)
	if sfx_value_label != null:
		sfx_value_label.text = "%d%%" % int(roundf(s_vol * 100.0))
	if sfx_mute_btn != null:
		sfx_mute_btn.button_pressed = s_mute

	if music_slider != null:
		music_slider.value = roundf(mu_vol * 100.0)
	if music_value_label != null:
		music_value_label.text = "%d%%" % int(roundf(mu_vol * 100.0))
	if music_mute_btn != null:
		music_mute_btn.button_pressed = mu_mute

	_syncing_ui = false

func _get_bus_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 0.85
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)

func _is_bus_muted(bus_name: String) -> bool:
	var idx := AudioServer.get_bus_index(bus_name)
	return idx != -1 and AudioServer.is_bus_mute(idx)

func _on_master_slider_changed(val: float) -> void:
	if master_value_label != null:
		master_value_label.text = "%d%%" % int(roundf(val))
	if _syncing_ui:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_master_volume"):
		gs.set_master_volume(val / 100.0)
	else:
		_fallback_set_bus("Master", val / 100.0, master_mute_btn != null and master_mute_btn.button_pressed)
	if master_mute_btn != null and val > 0.5 and master_mute_btn.button_pressed:
		_syncing_ui = true
		master_mute_btn.button_pressed = false
		_syncing_ui = false

func _on_sfx_slider_changed(val: float) -> void:
	if sfx_value_label != null:
		sfx_value_label.text = "%d%%" % int(roundf(val))
	if _syncing_ui:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_sfx_volume"):
		gs.set_sfx_volume(val / 100.0)
	else:
		_fallback_set_bus("SFX", val / 100.0, sfx_mute_btn != null and sfx_mute_btn.button_pressed)
	if sfx_mute_btn != null and val > 0.5 and sfx_mute_btn.button_pressed:
		_syncing_ui = true
		sfx_mute_btn.button_pressed = false
		_syncing_ui = false

func _on_music_slider_changed(val: float) -> void:
	if music_value_label != null:
		music_value_label.text = "%d%%" % int(roundf(val))
	if _syncing_ui:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_music_volume"):
		gs.set_music_volume(val / 100.0)
	else:
		_fallback_set_bus("Music", val / 100.0, music_mute_btn != null and music_mute_btn.button_pressed)
	if music_mute_btn != null and val > 0.5 and music_mute_btn.button_pressed:
		_syncing_ui = true
		music_mute_btn.button_pressed = false
		_syncing_ui = false

func _on_master_mute_toggled(toggled: bool) -> void:
	if _syncing_ui:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_master_muted"):
		gs.set_master_muted(toggled)

func _on_sfx_mute_toggled(toggled: bool) -> void:
	if _syncing_ui:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_sfx_muted"):
		gs.set_sfx_muted(toggled)

func _on_music_mute_toggled(toggled: bool) -> void:
	if _syncing_ui:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_music_muted"):
		gs.set_music_muted(toggled)

func _fallback_set_bus(bus_name: String, lin: float, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var silent := muted or lin <= 0.001
	AudioServer.set_bus_mute(idx, silent)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(lin, 0.001, 1.0)) if not silent else -80.0)

func _on_test_sfx_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_shoot(Vector2.ZERO)

func _on_resume_pressed() -> void:
	close_menu()

func _on_main_menu_pressed() -> void:
	is_open = false
	visible = false
	if get_tree() != null:
		get_tree().paused = false
	if SoundManagerScript != null:
		SoundManagerScript.stop_all_match_audio()
	var gs := _get_settings()
	if gs != null and gs.has_method("clear_lobby_match"):
		gs.clear_lobby_match()
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("is_online") and nm.is_online() and nm.has_method("disconnect_network"):
		nm.disconnect_network()
	exit_to_menu_requested.emit()
	if navigate_on_exit and get_tree() != null and ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _on_quit_pressed() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if SoundManagerScript != null:
		SoundManagerScript.stop_all_match_audio()
	if get_tree() != null:
		get_tree().quit()
