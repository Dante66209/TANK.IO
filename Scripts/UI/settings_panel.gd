# res://Scripts/UI/settings_panel.gd
class_name SettingsPanel extends Control

## Audio & Display Configuration Panel.

signal closed()

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

@onready var master_slider: HSlider = $Center/Panel/VBox/FormGrid/MasterRow/MasterSlider
@onready var master_value: Label = $Center/Panel/VBox/FormGrid/MasterRow/MasterValue
@onready var master_mute: CheckBox = $Center/Panel/VBox/FormGrid/MasterRow/MasterMute
@onready var sfx_slider: HSlider = $Center/Panel/VBox/FormGrid/SFXRow/SFXSlider
@onready var sfx_value: Label = $Center/Panel/VBox/FormGrid/SFXRow/SFXValue
@onready var sfx_mute: CheckBox = $Center/Panel/VBox/FormGrid/SFXRow/SFXMute
@onready var music_slider: HSlider = $Center/Panel/VBox/FormGrid/MusicRow/MusicSlider
@onready var music_value: Label = $Center/Panel/VBox/FormGrid/MusicRow/MusicValue
@onready var music_mute: CheckBox = $Center/Panel/VBox/FormGrid/MusicRow/MusicMute
@onready var fullscreen_check: CheckButton = $Center/Panel/VBox/FormGrid/FullscreenCheck
@onready var test_sfx_btn: Button = $Center/Panel/VBox/ActionsRow/TestSFXButton
@onready var reset_btn: Button = $Center/Panel/VBox/ActionsRow/ResetButton
@onready var back_btn: Button = $Center/Panel/VBox/ActionsRow/BackButton

var _syncing: bool = false

func _ready() -> void:
	_connect_signals()
	sync_from_settings()

func _connect_signals() -> void:
	if master_slider != null:
		master_slider.value_changed.connect(_on_master_changed)
	if master_mute != null:
		master_mute.toggled.connect(_on_master_mute_toggled)
	if sfx_slider != null:
		sfx_slider.value_changed.connect(_on_sfx_changed)
	if sfx_mute != null:
		sfx_mute.toggled.connect(_on_sfx_mute_toggled)
	if music_slider != null:
		music_slider.value_changed.connect(_on_music_changed)
	if music_mute != null:
		music_mute.toggled.connect(_on_music_mute_toggled)
	if fullscreen_check != null:
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	if test_sfx_btn != null:
		test_sfx_btn.pressed.connect(_on_test_sfx_pressed)
	if reset_btn != null:
		reset_btn.pressed.connect(_on_reset_pressed)
	if back_btn != null:
		back_btn.pressed.connect(_on_back_pressed)

func _get_settings() -> Node:
	return get_node_or_null("/root/GameSettings")

func sync_from_settings() -> void:
	_syncing = true
	var gs := _get_settings()
	var m_vol: float = float(gs.get("master_volume")) if gs != null else 0.85
	var s_vol: float = float(gs.get("sfx_volume")) if gs != null else 0.85
	var mu_vol: float = float(gs.get("music_volume")) if gs != null else 0.80
	var m_mute: bool = bool(gs.get("master_muted")) if gs != null else false
	var s_mute: bool = bool(gs.get("sfx_muted")) if gs != null else false
	var mu_mute: bool = bool(gs.get("music_muted")) if gs != null else false
	var fs: bool = bool(gs.get("fullscreen")) if gs != null else false

	if master_slider != null:
		master_slider.value = roundf(m_vol * 100.0)
	if master_value != null:
		master_value.text = "%d%%" % int(roundf(m_vol * 100.0))
	if master_mute != null:
		master_mute.button_pressed = m_mute
	if sfx_slider != null:
		sfx_slider.value = roundf(s_vol * 100.0)
	if sfx_value != null:
		sfx_value.text = "%d%%" % int(roundf(s_vol * 100.0))
	if sfx_mute != null:
		sfx_mute.button_pressed = s_mute
	if music_slider != null:
		music_slider.value = roundf(mu_vol * 100.0)
	if music_value != null:
		music_value.text = "%d%%" % int(roundf(mu_vol * 100.0))
	if music_mute != null:
		music_mute.button_pressed = mu_mute
	if fullscreen_check != null:
		fullscreen_check.button_pressed = fs
	_syncing = false

func _on_master_changed(val: float) -> void:
	if master_value != null:
		master_value.text = "%d%%" % int(roundf(val))
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_master_volume"):
		gs.set_master_volume(val / 100.0)
	if master_mute != null and val > 0.5 and master_mute.button_pressed:
		_syncing = true
		master_mute.button_pressed = false
		_syncing = false

func _on_sfx_changed(val: float) -> void:
	if sfx_value != null:
		sfx_value.text = "%d%%" % int(roundf(val))
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_sfx_volume"):
		gs.set_sfx_volume(val / 100.0)
	if sfx_mute != null and val > 0.5 and sfx_mute.button_pressed:
		_syncing = true
		sfx_mute.button_pressed = false
		_syncing = false

func _on_music_changed(val: float) -> void:
	if music_value != null:
		music_value.text = "%d%%" % int(roundf(val))
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_music_volume"):
		gs.set_music_volume(val / 100.0)
	if music_mute != null and val > 0.5 and music_mute.button_pressed:
		_syncing = true
		music_mute.button_pressed = false
		_syncing = false

func _on_master_mute_toggled(toggled: bool) -> void:
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_master_muted"):
		gs.set_master_muted(toggled)

func _on_sfx_mute_toggled(toggled: bool) -> void:
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_sfx_muted"):
		gs.set_sfx_muted(toggled)

func _on_music_mute_toggled(toggled: bool) -> void:
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_music_muted"):
		gs.set_music_muted(toggled)

func _on_fullscreen_toggled(enabled: bool) -> void:
	if _syncing:
		return
	var gs := _get_settings()
	if gs != null and gs.has_method("set_fullscreen"):
		gs.set_fullscreen(enabled)

func _on_test_sfx_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_shoot(Vector2.ZERO)

func _on_reset_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	var gs := _get_settings()
	if gs != null and gs.has_method("reset_defaults"):
		gs.reset_defaults()
	sync_from_settings()

func _on_back_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	closed.emit()
